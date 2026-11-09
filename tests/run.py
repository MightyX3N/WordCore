#!/usr/bin/env python3
"""
WordCore Phase 0 test suite.

    python tests/run.py                      # everything available on this machine
    python tests/run.py unit server cgi      # pick groups
    python tests/run.py apache               # needs Apache set up by tests/apache/setup.sh

Groups:
  unit     Lua unit tests inside the program
  server   built-in web server over real HTTP
  cgi      CGI mode driven directly with environment variables
  apache   CGI through a real Apache + .htaccess, like cPanel (subfolder and web root)
  wine     the Windows build under Wine (if installed)
  arm64    the linux-arm64 build under qemu (if installed)
"""
import http.client
import json
import os
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
LINUX = DIST / "linux-x86_64" / "wordcore"

results = {"passed": 0, "failed": 0}
group = ""


def ok(cond, msg):
    if cond:
        results["passed"] += 1
    else:
        results["failed"] += 1
        print(f"  FAIL [{group}] {msg}")
    return cond


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def request(port, method, path, body=None, headers=None, host="127.0.0.1"):
    conn = http.client.HTTPConnection(host, port, timeout=10)
    conn.request(method, path, body=body, headers=headers or {})
    r = conn.getresponse()
    data = r.read()
    conn.close()
    return r.status, {k.lower(): v for k, v in r.getheaders()}, data


def raw(port, payload, read_timeout=5):
    with socket.create_connection(("127.0.0.1", port), timeout=read_timeout) as s:
        s.sendall(payload)
        chunks = []
        try:
            while True:
                d = s.recv(65536)
                if not d:
                    break
                chunks.append(d)
        except socket.timeout:
            pass
    return b"".join(chunks)


def wait_port(port, timeout=10):
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.05)
    return False


# ---------------------------------------------------------------- unit

def test_unit(exe=LINUX, runner=None):
    cmd = (runner or []) + [str(exe), "run", str(ROOT / "tests/unit/run.lua")]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    sys.stdout.write("  " + r.stdout.strip() + "\n")
    if r.stderr.strip():
        sys.stdout.write(r.stderr)
    ok(r.returncode == 0, "unit tests pass")


# ---------------------------------------------------------------- server

def start_server(exe, site, extra=(), runner=None):
    port = free_port()
    cmd = (runner or []) + [str(exe), "serve", "--port", str(port), "--site", str(site), *extra]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if not wait_port(port, 30):
        proc.kill()
        out = proc.stdout.read().decode(errors="replace")
        raise RuntimeError(f"server did not start: {out}")
    return proc, port


def test_server(exe=LINUX, runner=None):
    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    proc, port = start_server(exe, site, runner=runner)
    try:
        s, h, b = request(port, "GET", "/health")
        j = json.loads(b)
        ok(s == 200 and j["ok"] and j["mode"] == "server", "health")
        ok(j["lua"].startswith("Lua 5.5"), "Lua 5.5 inside")
        ok(h.get("x-content-type-options") == "nosniff", "security headers")

        s, h, b = request(port, "GET", "/")
        ok(s == 200 and b"Host check" in b, "host check page")
        ok(b"loaded <strong>1</strong> time" in b, "visit counter starts at 1")
        ok(b'class="bad"' not in b, "all checks green")
        s, h, b = request(port, "GET", "/")
        ok(b"loaded <strong>2</strong> times" in b, "visit counter persists")
        ok((site / "site.db").exists(), "site.db created in site folder")

        s, h, b = request(port, "GET", "/echo?a=1&b=x%20y&c=%C3%B8")
        j = json.loads(b)
        ok(j["query"] == {"a": "1", "b": "x y", "c": "ø"}, "query decoding")
        ok(j["public_url"] == f"http://127.0.0.1:{port}", "public url")

        s, h, b = request(port, "POST", "/echo", body="name=A%26B&n=2",
                          headers={"Content-Type": "application/x-www-form-urlencoded"})
        j = json.loads(b)
        ok(j["form"] == {"name": "A&B", "n": "2"} and j["method"] == "POST", "form body")

        big = "x" * 200000
        s, h, b = request(port, "POST", "/echo", body=big, headers={"Content-Type": "text/plain"})
        ok(json.loads(b)["body_length"] == 200000, "200 KB body read fully")

        s, h, b = request(port, "GET", "/echo", headers={"X-Forwarded-Proto": "https", "X-Forwarded-Host": "evil.example"})
        j = json.loads(b)
        ok(j["scheme"] == "http" and j["host"] == f"127.0.0.1:{port}" and not j["proxy"]["trusted"], "proxy headers not trusted by default")

        s, h, b = request(port, "HEAD", "/")
        ok(s == 200 and b == b"" and int(h["content-length"]) > 1000, "HEAD has length, no body")

        s, h, b = request(port, "GET", "/nope")
        ok(s == 404 and b"nothing at /nope" in b, "404 page")
        s, h, b = request(port, "GET", "/%3Cscript%3E")
        ok(s == 404 and b"<script>" not in b, "404 page escapes path")
        s, h, b = request(port, "POST", "/")
        ok(s == 405 and h.get("allow") == "GET, HEAD", "405 with Allow")

        resp = raw(port, b"NONSENSE\r\n\r\n")
        ok(resp.startswith(b"HTTP/1.1 400"), "malformed request line -> 400")
        resp = raw(port, b"GET / HTTP/1.1\r\nHost: x\r\nX-Big: " + b"a" * 40000 + b"\r\n\r\n")
        ok(raw(port, b"GET / HTTP/1.1\r\n\r\n").startswith(b"HTTP/1.1 400"), "HTTP/1.1 without Host -> 400")
        ok(resp.startswith(b"HTTP/1.1 431"), "huge headers -> 431")
        resp = raw(port, b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
        ok(resp.startswith(b"HTTP/1.1 501"), "chunked -> 501")
        resp = raw(port, b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 99999999999\r\n\r\n")
        ok(resp.startswith(b"HTTP/1.1 413"), "too large -> 413")
        resp = raw(port, b"GET /../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n")
        ok(b"root:" not in resp and resp.startswith(b"HTTP/1.1 404"), "path traversal goes nowhere")

        # idle and half-finished clients must not hold anyone else up
        idle = [socket.create_connection(("127.0.0.1", port)) for _ in range(20)]
        slow = socket.create_connection(("127.0.0.1", port))
        slow.sendall(b"GET /health HTTP/1.1\r\nHost: x\r\n")  # never finishes its headers
        t0 = time.time()
        s, h, b = request(port, "GET", "/health")
        took = time.time() - t0
        ok(s == 200 and took < 1, f"not blocked by 20 idle + 1 slow client ({took * 1000:.0f} ms)")
        for c in idle + [slow]:
            c.close()

        # keep-alive: several requests on one connection
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        statuses = []
        for p in ("/health", "/echo?n=2", "/health"):
            conn.request("GET", p)
            r = conn.getresponse()
            r.read()
            statuses.append((r.status, r.getheader("Connection")))
        conn.close()
        ok(statuses == [(200, "keep-alive")] * 3, f"keep-alive reuses the connection {statuses}")
        resp = raw(port, b"GET /health HTTP/1.1\r\nHost: x\r\n\r\nGET /echo?p=2 HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
        ok(resp.count(b"HTTP/1.1 200") == 2 and b'"p": "2"' in resp, "pipelined requests both answered")
        resp = raw(port, b"GET /health HTTP/1.0\r\n\r\n")
        ok(b"Connection: close" in resp, "HTTP/1.0 closes by default")

        # many clients at once
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(16) as pool:
            res = list(pool.map(lambda i: request(port, "GET", f"/echo?i={i}")[0], range(200)))
        ok(res.count(200) == 200, f"200 concurrent requests ({res.count(200)} ok)")

        times = []
        for _ in range(50):
            t0 = time.perf_counter()
            request(port, "GET", "/health")
            times.append((time.perf_counter() - t0) * 1000)
        print(f"  server: median {statistics.median(times):.2f} ms per request")
        ok(statistics.median(times) < 50, "fast enough")
    finally:
        proc.terminate()
        proc.wait(timeout=5)
        shutil.rmtree(site, ignore_errors=True)

    # trust proxy on
    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    proc, port = start_server(exe, site, ["--trust-proxy"], runner=runner)
    try:
        s, h, b = request(port, "GET", "/echo", headers={"X-Forwarded-Proto": "https", "X-Forwarded-Host": "preview.example"})
        j = json.loads(b)
        ok(j["public_url"] == "https://preview.example" and j["proxy"]["trusted"], "trusted tunnel address")
    finally:
        proc.terminate()
        proc.wait(timeout=5)
        shutil.rmtree(site, ignore_errors=True)

    # base path from site/config.json
    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    (site / "config.json").write_text('{"base_path": "/blog"}')
    proc, port = start_server(exe, site, runner=runner)
    try:
        s, h, b = request(port, "GET", "/blog/echo")
        j = json.loads(b)
        ok(j["base_path"] == "/blog" and j["path"] == "/echo" and j["url_for_example"] == "/blog/some/page", "configured base path")
    finally:
        proc.terminate()
        proc.wait(timeout=5)
        shutil.rmtree(site, ignore_errors=True)


# ---------------------------------------------------------------- cgi (direct)

def run_cgi(exe, env, body=b"", argv=(), runner=None):
    full = {"PATH": os.environ.get("PATH", ""), "GATEWAY_INTERFACE": "CGI/1.1", **env}
    r = subprocess.run((runner or []) + [str(exe), *argv], input=body, capture_output=True, env=full, timeout=30)
    head, _, payload = r.stdout.partition(b"\r\n\r\n")
    lines = head.decode().split("\r\n")
    status = int(lines[0].split()[1]) if lines and lines[0].startswith("Status:") else 0
    headers = {}
    for line in lines[1:]:
        k, _, v = line.partition(": ")
        headers[k.lower()] = v
    return status, headers, payload, r


def test_cgi(exe=LINUX, runner=None):
    work = Path(tempfile.mkdtemp(prefix="wc-cgi-"))
    prog = work / ("wordcore.exe" if str(exe).endswith(".exe") else "wordcore.cgi")
    shutil.copy2(exe, prog)
    base_env = {"SERVER_NAME": "example.com", "SERVER_PORT": "443", "HTTPS": "on", "HTTP_HOST": "example.com",
                "SCRIPT_NAME": "/wc/wordcore.cgi", "REMOTE_ADDR": "203.0.113.9"}
    try:
        s, h, b, r = run_cgi(prog, {**base_env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/echo?x=1"}, runner=runner)
        j = json.loads(b)
        ok(s == 200 and j["mode"] == "cgi", "cgi echo")
        ok(j["base_path"] == "/wc" and j["path"] == "/echo" and j["public_url"] == "https://example.com/wc", "cgi address")
        ok(int(h["content-length"]) == len(b), "content-length matches")
        ok((work / "site" / "site.db").exists(), "site folder next to program")
        ok((work / "site" / ".htaccess").exists() and "denied" in (work / "site" / ".htaccess").read_text(), "site folder guarded")

        s, h, b, r = run_cgi(prog, {**base_env, "REQUEST_METHOD": "POST", "REQUEST_URI": "/wc/echo",
                                    "CONTENT_TYPE": "application/x-www-form-urlencoded", "CONTENT_LENGTH": "7"},
                             body=b"a=1&b=2", runner=runner)
        ok(json.loads(b)["form"] == {"a": "1", "b": "2"}, "cgi POST body")

        # argv must be ignored when run as CGI (servers may pass query words as arguments)
        s, h, b, r = run_cgi(prog, {**base_env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/health"},
                             argv=["run", "/etc/passwd"], runner=runner)
        ok(s == 200 and b'"ok": true' in b, "cgi ignores command-line arguments")

        s, h, b, r = run_cgi(prog, {**base_env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/"}, runner=runner)
        ok(s == 200 and b"Host check" in b, "cgi host check page")

        s, h, b, r = run_cgi(prog, {**base_env, "REQUEST_METHOD": "HEAD", "REQUEST_URI": "/wc/"}, runner=runner)
        ok(s == 200 and b == b"" and int(h["content-length"]) > 1000, "cgi HEAD")

        times = []
        for _ in range(20):
            t0 = time.perf_counter()
            run_cgi(prog, {**base_env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/health"}, runner=runner)
            times.append((time.perf_counter() - t0) * 1000)
        print(f"  cgi: median {statistics.median(times):.1f} ms per request (process start to exit)")
        if not runner:
            ok(statistics.median(times) < 100, "cgi fast enough")
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ---------------------------------------------------------------- apache

def test_apache():
    if not Path("/srv/wc").exists():
        print("  skipped: run tests/apache/setup.sh first")
        return
    subprocess.run(["bash", str(ROOT / "tests/apache/setup.sh"), "deploy"], check=True)
    for port, base in ((8085, "/wctest"), (8086, "")):
        label = f"apache {'subfolder' if base else 'web root'}"
        s, h, b = request(port, "GET", f"{base}/")
        ok(s == 200 and b"Host check" in b and b'class="bad"' not in b, f"{label}: host check all green")
        s, h, b = request(port, "GET", f"{base}/echo?q=hello%20there&x=%C3%A6")
        j = json.loads(b)
        ok(j["mode"] == "cgi" and j["base_path"] == base and j["path"] == "/echo", f"{label}: routing and base path")
        ok(j["query"] == {"q": "hello there", "x": "æ"}, f"{label}: query")
        ok(j["public_url"] == f"http://127.0.0.1:{port}{base}", f"{label}: public url")
        s, h, b = request(port, "GET", f"{base}/deeper/page/")
        ok(s == 404, f"{label}: unknown page -> WordCore 404")
        ok(b"nothing at /deeper/page/" in b and b"<title>404 Not Found</title>" in b, f"{label}: 404 comes from WordCore, not Apache")
        s, h, b = request(port, "POST", f"{base}/echo", body="a=1&b=%26",
                          headers={"Content-Type": "application/x-www-form-urlencoded"})
        ok(json.loads(b)["form"] == {"a": "1", "b": "&"}, f"{label}: POST body")
        s, h, b = request(port, "GET", f"{base}/site/site.db")
        ok(s in (403, 404) and b"SQLite" not in b, f"{label}: database not downloadable ({s})")
        s, h, b = request(port, "GET", f"{base}/site/config.json")
        ok(s in (403, 404), f"{label}: site config not downloadable ({s})")
        s, h, b = request(port, "GET", f"{base}/wordcore.cgi/echo")
        ok(s == 200 and json.loads(b)["path"] == "/echo", f"{label}: direct program URL works")
        s, h, b = request(port, "GET", f"{base}/public/hello.txt")
        ok(s == 200 and b.strip() == b"static file", f"{label}: public/ served directly by Apache")
        s, h, b = request(port, "GET", f"{base}/echo", headers={"Authorization": "Bearer abc"})
        ok(s == 200, f"{label}: Authorization header accepted")

        times = []
        for _ in range(40):
            t0 = time.perf_counter()
            request(port, "GET", f"{base}/health")
            times.append((time.perf_counter() - t0) * 1000)
        print(f"  {label}: median {statistics.median(times):.1f} ms per request through Apache CGI")
        ok(statistics.median(times) < 150, f"{label}: fast enough")


# ---------------------------------------------------------------- other platforms

def test_wine():
    exe = DIST / "windows-x64" / "wordcore.exe"
    if not exe.exists() or not shutil.which("wine"):
        print("  skipped: no Windows build or no wine")
        return
    env = {**os.environ, "WINEDEBUG": "-all"}
    r = subprocess.run(["wine", str(exe), "version"], capture_output=True, text=True, env=env, timeout=120)
    ok(r.returncode == 0 and "Lua 5.5" in r.stdout and "windows" in r.stdout, "windows: version " + r.stdout.strip().replace("\n", " | "))
    r = subprocess.run(["wine", str(exe), "run", str(ROOT / "tests/unit/run.lua")], capture_output=True, text=True, env=env, timeout=300)
    print("  windows unit: " + r.stdout.strip())
    ok(r.returncode == 0, "windows: unit tests " + r.stderr[-500:])
    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    port = free_port()
    proc = subprocess.Popen(["wine", str(exe), "serve", "--port", str(port), "--site", str(site)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    try:
        ok(wait_port(port, 60), "windows: server starts")
        s, h, b = request(port, "GET", "/")
        ok(s == 200 and b"Host check" in b and b'class="bad"' not in b, "windows: host check all green")
        s, h, b = request(port, "POST", "/echo", body="x" * 100000, headers={"Content-Type": "text/plain"})
        ok(json.loads(b)["body_length"] == 100000, "windows: large body")
    finally:
        proc.kill()
        proc.wait(timeout=10)
        shutil.rmtree(site, ignore_errors=True)


def test_arm64():
    exe = DIST / "linux-arm64" / "wordcore"
    q = shutil.which("qemu-aarch64-static") or shutil.which("qemu-aarch64")
    if not exe.exists() or not q:
        print("  skipped: no arm64 build or no qemu")
        return
    r = subprocess.run([q, str(exe), "version"], capture_output=True, text=True, timeout=60)
    ok(r.returncode == 0 and "arm64" in r.stdout, "arm64: version " + r.stdout.strip().replace("\n", " | "))
    test_unit(exe, runner=[q])
    test_cgi(exe, runner=[q])


GROUPS = {"unit": test_unit, "server": test_server, "cgi": test_cgi, "apache": test_apache,
          "wine": test_wine, "arm64": test_arm64}


def main():
    global group
    names = sys.argv[1:] or list(GROUPS)
    if not LINUX.exists():
        sys.exit("Build first: python runtime/build/build.py linux-x86_64")
    for n in names:
        group = n
        print(f"[{n}]")
        try:
            GROUPS[n]()
        except Exception as e:  # report and keep going
            ok(False, f"crashed: {e!r}")
    print(f"\n{results['passed']} passed, {results['failed']} failed")
    sys.exit(1 if results["failed"] else 0)


if __name__ == "__main__":
    main()
