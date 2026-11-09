#!/usr/bin/env python3
"""
WordCore test suite.

    python tests/run.py                      # everything available on this machine
    python tests/run.py unit server flow     # pick groups

Groups:
  unit     Lua unit tests inside the program (+ compile check of every core file)
  server   built-in web server: HTTP robustness, keep-alive, concurrency, assets
  flow     the whole product over HTTP in server mode: setup wizard, sign-in,
           lockout, CSRF, settings, account, sessions
  cgi      CGI mode driven directly with environment variables
  apache   the same flow through a real Apache + .htaccess (subfolder and web root)
  wine     the Windows build under Wine: unit tests + the flow
  arm64    the linux-arm64 build under qemu: unit tests + CGI
  browser  Playwright click-through of setup and admin (needs node + playwright)
"""
import http.client
import json
import os
import re
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.parse
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


def wait_port(port, timeout=10):
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.05)
    return False


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


class Client:
    """A tiny browser: keeps cookies, follows nothing automatically, finds CSRF tokens."""

    def __init__(self, port, base="", host="127.0.0.1"):
        self.port, self.base, self.host = port, base, host
        self.cookies = {}
        self.last = None

    def request(self, method, path, form=None, headers=None, body=None):
        h = dict(headers or {})
        if self.cookies:
            h["Cookie"] = "; ".join(f"{k}={v}" for k, v in self.cookies.items())
        if form is not None:
            body = urllib.parse.urlencode(form)
            h["Content-Type"] = "application/x-www-form-urlencoded"
        conn = http.client.HTTPConnection(self.host, self.port, timeout=30)
        conn.request(method, self.base + path, body=body, headers=h)
        r = conn.getresponse()
        data = r.read()
        hdrs = {}
        cookies = []
        for k, v in r.getheaders():
            if k.lower() == "set-cookie":
                cookies.append(v)
            hdrs[k.lower()] = v
        conn.close()
        for c in cookies:
            name, _, rest = c.partition("=")
            value = rest.split(";")[0]
            if "Max-Age=0" in c:
                self.cookies.pop(name, None)
            else:
                self.cookies[name] = value
        hdrs["_set_cookie"] = cookies
        self.last = (r.status, hdrs, data.decode("utf-8", "replace"))
        return self.last

    def get(self, path, **kw):
        return self.request("GET", path, **kw)

    def post(self, path, form=None, csrf=True, **kw):
        form = dict(form or {})
        if csrf and "_csrf" not in form:
            form["_csrf"] = self.csrf()
        return self.request("POST", path, form=form, **kw)

    def csrf(self):
        m = re.search(r'name="_csrf" value="([^"]+)"', self.last[2] if self.last else "")
        return m.group(1) if m else ""

    def location(self):
        loc = self.last[1].get("location", "")
        return loc[len(self.base):] if self.base and loc.startswith(self.base) else loc


# ---------------------------------------------------------------- unit

def test_unit(exe=LINUX, runner=None):
    r = subprocess.run((runner or []) + [str(exe), "run", str(ROOT / "tests/unit/compile_all.lua"), str(ROOT / "core")],
                       capture_output=True, text=True, timeout=120)
    ok(r.returncode == 0, "every core file compiles " + r.stderr[-400:])
    r = subprocess.run((runner or []) + [str(exe), "run", str(ROOT / "tests/unit/run.lua")], capture_output=True, text=True, timeout=300)
    sys.stdout.write("  " + r.stdout.strip() + "\n")
    if r.stderr.strip():
        sys.stdout.write(r.stderr)
    ok(r.returncode == 0, "unit tests pass")


# ---------------------------------------------------------------- server helpers

def start_server(exe, site, extra=(), runner=None):
    port = free_port()
    cmd = (runner or []) + [str(exe), "serve", "--port", str(port), "--site", str(site), *extra]
    env = {**os.environ, "WINEDEBUG": "-all"}
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    if not wait_port(port, 60):
        proc.kill()
        out = proc.stdout.read().decode(errors="replace")
        raise RuntimeError(f"server did not start: {out}")
    return proc, port


def stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


# ---------------------------------------------------------------- server: HTTP robustness

def test_server(exe=LINUX, runner=None):
    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    proc, port = start_server(exe, site, runner=runner)
    try:
        c = Client(port)
        s, h, b = c.get("/_wc/health")
        j = json.loads(b)
        ok(s == 200 and j["ok"] and j["mode"] == "server", "health")
        ok(j["lua"].startswith("Lua 5.5"), "Lua 5.5 inside")
        ok(h.get("x-content-type-options") == "nosniff", "security headers")
        ok(j["public_url"] == f"http://127.0.0.1:{port}", "public url")

        s, h, b = c.get("/")
        ok(s == 303 and h["location"] == "/setup", "fresh site sends everything to setup")
        ok((site / "setup-code.txt").exists(), "setup code file created")

        s, h, b = c.get("/_wc/assets/admin.css")
        ok(s == 200 and h["content-type"].startswith("text/css") and "immutable" in h.get("cache-control", ""), "admin.css served and cached")
        etag = h.get("etag")
        s, h, b = c.get("/_wc/assets/admin.css", headers={"If-None-Match": etag})
        ok(s == 304, "304 when unchanged")
        s, h, b = c.get("/_wc/assets/fonts/inter-latin-wght-normal.woff2")
        ok(s == 200 and h["content-type"] == "font/woff2", "fonts served")
        for p in ("/_wc/assets/../boot.lua", "/_wc/assets/%2e%2e/boot.lua", "/_wc/assets/..%2fboot.lua", "/_wc/assets/fonts/../../boot.lua"):
            s, h, b = c.get(p)
            ok(s != 200 and "WORDCORE_VERSION" not in b, f"no path traversal in assets: {p} -> {s}")
        s, h, b = c.get("/_wc/notices")
        ok(s == 200 and "Monocypher" in b and "SIL Open Font License" in b, "licence notices served")

        s, h, b = c.request("HEAD", "/_wc/health")
        ok(s == 200 and b == "" and int(h["content-length"]) > 50, "HEAD has length, no body")

        big = "x" * 200000
        s, h, b = c.request("POST", "/setup/code", body=big, headers={"Content-Type": "text/plain"})
        ok(s == 403, "200 KB body read fully, then CSRF refuses it")

        resp = raw(port, b"NONSENSE\r\n\r\n")
        ok(resp.startswith(b"HTTP/1.1 400"), "malformed request line -> 400")
        ok(raw(port, b"GET / HTTP/1.1\r\n\r\n").startswith(b"HTTP/1.1 400"), "HTTP/1.1 without Host -> 400")
        resp = raw(port, b"GET / HTTP/1.1\r\nHost: x\r\nX-Big: " + b"a" * 40000 + b"\r\n\r\n")
        ok(resp.startswith(b"HTTP/1.1 431"), "huge headers -> 431")
        resp = raw(port, b"POST /setup/code HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
        ok(resp.startswith(b"HTTP/1.1 501"), "chunked -> 501")
        resp = raw(port, b"POST /setup/code HTTP/1.1\r\nHost: x\r\nContent-Length: 99999999999\r\n\r\n")
        ok(resp.startswith(b"HTTP/1.1 413"), "too large -> 413")
        resp = raw(port, b"GET /../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n")
        ok(b"root:" not in resp, "path traversal goes nowhere")

        idle = [socket.create_connection(("127.0.0.1", port)) for _ in range(20)]
        slow = socket.create_connection(("127.0.0.1", port))
        slow.sendall(b"GET /_wc/health HTTP/1.1\r\nHost: x\r\n")
        t0 = time.time()
        s, h, b = c.get("/_wc/health")
        took = time.time() - t0
        ok(s == 200 and took < 1, f"not blocked by 20 idle + 1 slow client ({took * 1000:.0f} ms)")
        for x in idle + [slow]:
            x.close()

        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        statuses = []
        for p in ("/_wc/health", "/_wc/assets/admin.js", "/_wc/health"):
            conn.request("GET", p)
            r = conn.getresponse()
            r.read()
            statuses.append((r.status, r.getheader("Connection")))
        conn.close()
        ok(statuses == [(200, "keep-alive")] * 3, f"keep-alive reuses the connection {statuses}")
        resp = raw(port, b"GET /_wc/health HTTP/1.1\r\nHost: x\r\n\r\nGET /_wc/health HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
        ok(resp.count(b"HTTP/1.1 200") == 2, "pipelined requests both answered")
        ok(b"Connection: close" in raw(port, b"GET /_wc/health HTTP/1.0\r\n\r\n"), "HTTP/1.0 closes by default")

        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(16) as pool:
            res = list(pool.map(lambda i: Client(port).get("/_wc/health")[0], range(200)))
        ok(res.count(200) == 200, f"200 concurrent requests ({res.count(200)} ok)")

        times = []
        for _ in range(50):
            t0 = time.perf_counter()
            c.get("/_wc/health")
            times.append((time.perf_counter() - t0) * 1000)
        print(f"  server: median {statistics.median(times):.2f} ms per request")
        ok(statistics.median(times) < 50, "fast enough")
    finally:
        stop(proc)
        shutil.rmtree(site, ignore_errors=True)

    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    proc, port = start_server(exe, site, ["--trust-proxy"], runner=runner)
    try:
        s, h, b = Client(port).get("/_wc/health", headers={"X-Forwarded-Proto": "https", "X-Forwarded-Host": "preview.example"})
        j = json.loads(b)
        ok(j["public_url"] == "https://preview.example" and j["proxy_trusted"], "trusted tunnel address")
        s, h, b = Client(port).get("/", headers={"X-Forwarded-Proto": "https", "X-Forwarded-Host": "preview.example"})
        ok(s == 303, "redirect behind proxy")
    finally:
        stop(proc)
        shutil.rmtree(site, ignore_errors=True)

    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    (site / "config.json").write_text('{"base_path": "/blog"}')
    proc, port = start_server(exe, site, runner=runner)
    try:
        s, h, b = Client(port).get("/blog/_wc/health")
        j = json.loads(b)
        ok(j["base_path"] == "/blog", "configured base path")
        s, h, b = Client(port).get("/blog/")
        ok(s == 303 and h["location"] == "/blog/setup", "redirects keep the base path")
    finally:
        stop(proc)
        shutil.rmtree(site, ignore_errors=True)


# ---------------------------------------------------------------- the product flow

STRONG = "Correct-Horse-Battery-9"
STRONG2 = "Another-Strong-Pass-42"


def setup_wizard(c, site_dir, label):
    s, h, b = c.get("/")
    ok(s == 303 and c.location() == "/setup", f"{label}: / goes to setup")
    s, h, b = c.get("/setup")
    ok(s == 200 and "Enter your setup code" in b, f"{label}: setup asks for the code")
    ok("default-src 'self'" in h.get("content-security-policy", ""), f"{label}: strict CSP on setup")
    ok(any("HttpOnly" in x and "SameSite=Lax" in x for x in h["_set_cookie"]), f"{label}: session cookie is HttpOnly + SameSite")

    s, h, b = c.post("/setup/code", {"code": "AAAA-AAAA"})
    ok(s == 422 and "Check site/setup-code.txt" in b, f"{label}: wrong code refused")
    s, h, b = c.post("/setup/code", {"code": "AAAA-AAAA", "_csrf": "forged"}, csrf=False)
    ok(s == 403, f"{label}: forged CSRF token refused")

    code = re.search(r"Setup code: (\S+)", (site_dir / "setup-code.txt").read_text()).group(1)
    c.get("/setup")
    s, h, b = c.post("/setup/code", {"code": code.lower().replace("-", " ")})
    ok(s == 303, f"{label}: right code accepted (case and dash don't matter)")

    s, h, b = c.get("/setup")
    ok("Step 1 of 5" in b, f"{label}: step 1")
    s, h, b = c.post("/setup/step/1", {"name": "", "tagline": "", "language": "en", "timezone": "UTC"})
    ok(s == 200 and "Give your site a name" in b, f"{label}: step 1 validation")
    s, h, b = c.post("/setup/step/1", {"name": "Nordlys <Studio>", "tagline": "Design & things", "language": "da", "timezone": "Europe/Copenhagen"})
    ok(s == 303, f"{label}: step 1 saved")
    c.get("/setup")
    s, h, b = c.post("/setup/step/3", {"mode": "local"})
    ok(s == 303 and c.location() == "/setup", f"{label}: can't skip ahead ({s} {c.location()})")

    s, h, b = c.get("/setup?step=2")
    ok("Create your account" in b, f"{label}: step 2")
    s, h, b = c.post("/setup/step/2", {"username": "patrick", "display_name": "Patrick", "email": "p@example.com", "password": "short", "password2": "short"})
    ok("at least 10 characters" in b, f"{label}: short password refused")
    s, h, b = c.post("/setup/step/2", {"username": "patrick", "email": "p@example.com", "password": "patrick12345678", "password2": "patrick12345678"})
    ok("username in the password" in b, f"{label}: username in password refused")
    s, h, b = c.post("/setup/step/2", {"username": "patrick", "email": "nope", "password": STRONG, "password2": STRONG + "x"})
    ok("look like an email" in b and "passwords don&#39;t match" in b, f"{label}: bad email and mismatch reported together")
    ok(STRONG not in b, f"{label}: password never echoed back")
    s, h, b = c.post("/setup/step/2", {"username": "patrick", "display_name": "Patrick", "email": "p@example.com", "password": STRONG, "password2": STRONG})
    ok(s == 303, f"{label}: step 2 saved")

    s, h, b = c.get("/setup?step=3")
    ok("Where is this site running" in b and "Detected" in b, f"{label}: step 3 shows a detected mode")
    s, h, b = c.post("/setup/step/3", {"mode": "nonsense"})
    ok("Choose one" in b, f"{label}: step 3 validation")
    s, h, b = c.post("/setup/step/3", {"mode": "shared"})
    ok(s == 303, f"{label}: step 3 saved")

    s, h, b = c.get("/setup?step=4")
    ok("Pick a starting point" in b and "wordcore.space/repo" in b, f"{label}: step 4 with official repo")
    s, h, b = c.post("/setup/step/4", {"starter": "blog", "repo": "http://insecure.example/"})
    ok("Empty or Simple" in b and "https://" in b, f"{label}: step 4 refuses addon starters and http repos")
    s, h, b = c.post("/setup/step/4", {"starter": "simple", "repo": "https://wordcore.space/repo/"})
    ok(s == 303, f"{label}: step 4 saved")

    s, h, b = c.get("/setup?step=5")
    ok("Ready to create your site" in b and "Nordlys &lt;Studio&gt;" in b and "patrick" in b, f"{label}: summary, escaped")
    old_cookie = dict(c.cookies)
    s, h, b = c.post("/setup/finish")
    ok(s == 303 and c.location() == "/admin", f"{label}: site created")
    ok(c.cookies != old_cookie, f"{label}: new session token after sign-in")
    ok(not (site_dir / "setup-code.txt").exists(), f"{label}: setup code file deleted")


def admin_flow(c, port, base, site_dir, label):
    s, h, b = c.get("/admin")
    ok(s == 200 and "Dashboard" in b and "Your site is ready" in b, f"{label}: dashboard with welcome message")
    ok("Site health" in b and "Recent activity" in b and "Site created" in b, f"{label}: dashboard sections")
    ok("default-src 'self'" in h.get("content-security-policy", "") and h.get("cache-control") == "no-store", f"{label}: admin CSP + no-store")
    ok(' style="' not in b and "<script>" not in b, f"{label}: no inline styles or scripts (CSP-safe)")
    s, h, b = c.get("/admin")
    ok("Your site is ready" not in b, f"{label}: flash shown once")
    s, h, b = c.get("/setup")
    ok(s == 303 and c.location() == "/admin", f"{label}: setup closed after creation")

    s, h, b = c.get("/")
    ok(s == 200 and "Nordlys &lt;Studio&gt;" in b and "Design &amp; things" in b and 'lang="da"' in b, f"{label}: front page uses settings, escaped")

    # settings
    s, h, b = c.get("/admin/settings")
    ok(s == 200 and "Trust proxy headers" in b and "Europe/Copenhagen" in b, f"{label}: settings page")
    s, h, b = c.post("/admin/settings", {"site.name": "", "site.tagline": "", "site.language": "en", "site.timezone": "UTC", "repo.urls": "https://wordcore.space/repo/"})
    ok(s == 422 and "Give your site a name" in b, f"{label}: settings validation")
    s, h, b = c.post("/admin/settings", {"site.name": "Renamed", "site.tagline": "", "site.language": "xx", "site.timezone": "UTC", "repo.urls": "https://wordcore.space/repo/"})
    ok(s == 422 and "Choose an option" in b, f"{label}: settings refuse unknown language")
    s, h, b = c.post("/admin/settings", {"site.name": "Renamed", "site.tagline": "New tagline", "site.language": "en", "site.timezone": "UTC",
                                         "repo.urls": "https://wordcore.space/repo/\nhttps://example.com/repo/"})
    ok(s == 303, f"{label}: settings saved")
    s, h, b = c.get("/admin/settings")
    ok("Saved." in b and 'value="Renamed"' in b and "example.com/repo" in b, f"{label}: settings persisted")
    s, h, b = c.get("/")
    ok("Renamed" in b and "New tagline" in b, f"{label}: front page updated")
    s, h, b = c.post("/admin/settings", {"site.name": "Renamed", "_csrf": "wrong"}, csrf=False)
    ok(s == 403, f"{label}: settings CSRF")
    c.get("/admin/settings")
    s, h, b = c.post("/admin/settings", {"site.name": "Evil"}, headers={"Origin": "https://evil.example"})
    ok(s == 403, f"{label}: cross-site Origin refused")

    # second device
    d = Client(port, base)
    s, h, b = d.get("/admin/settings")
    ok(s == 303 and d.location().startswith("/admin/login?next="), f"{label}: signed-out visitor sent to login with next")
    d.get(d.location())
    s, h, b = d.post("/admin/login", {"login": "patrick", "password": "wrong-password", "next": "/admin/settings"})
    ok(s == 401 and "Wrong username or password" in b, f"{label}: wrong password")
    s, h, b = d.post("/admin/login", {"login": "P@EXAMPLE.COM", "password": STRONG, "next": "/admin/settings"})
    ok(s == 303 and d.location() == "/admin/settings", f"{label}: login by email, back to where you were")
    s, h, b = d.get("/admin/account")
    ok("This device" in b and "other device" in b, f"{label}: account lists devices")

    # open redirect protection
    e = Client(port, base)
    e.get("/admin/login")
    s, h, b = e.post("/admin/login", {"login": "patrick", "password": STRONG, "next": "//evil.example/x"})
    ok(s == 303 and e.location() == "/admin", f"{label}: no open redirect")

    # account: profile + password
    s, h, b = c.get("/admin/account")
    ok(s == 200 and "Signed-in devices" in b and "readonly" in b, f"{label}: account page")
    s, h, b = c.post("/admin/account/profile", {"display_name": "Pat", "email": "bad"})
    ok(s == 422 and "look like an email" in b, f"{label}: profile validation")
    c.get("/admin/account")
    s, h, b = c.post("/admin/account/profile", {"display_name": "Pat", "email": "pat@example.com"})
    ok(s == 303, f"{label}: profile saved")
    c.get("/admin/account")
    s, h, b = c.post("/admin/account/password", {"current": "nope", "new": STRONG2, "new2": STRONG2})
    ok(s == 422 and "your current password" in b, f"{label}: password change needs current password")
    s, h, b = c.post("/admin/account/password", {"current": STRONG, "new": STRONG2, "new2": STRONG2})
    ok(s == 303, f"{label}: password changed")
    s, h, b = d.get("/admin")
    ok(s == 303 and "/admin/login" in d.location(), f"{label}: other devices signed out after password change")
    s, h, b = e.get("/admin")
    ok(s == 303, f"{label}: third device signed out too")
    s, h, b = c.get("/admin")
    ok(s == 200, f"{label}: this device stays signed in")

    # sign out other devices
    d.get("/admin/login")
    d.post("/admin/login", {"login": "patrick", "password": STRONG2})
    c.get("/admin/account")
    s, h, b = c.post("/admin/account/sessions")
    ok(s == 303, f"{label}: sign out others")
    ok(d.get("/admin")[0] == 303, f"{label}: other device signed out")

    # GET on a POST-only route, logout
    s, h, b = c.get("/admin/logout")
    ok(s == 405, f"{label}: logout is POST only")
    c.get("/admin")
    s, h, b = c.post("/admin/logout")
    ok(s == 303 and "/admin/login" in c.location(), f"{label}: logged out")
    ok(c.get("/admin")[0] == 303, f"{label}: admin needs login again")

    # hostcheck needs sign-in; health doesn't
    ok(c.get("/_wc/hostcheck")[0] == 303, f"{label}: host check needs sign-in")

    # lockout (last: it blocks the account for 15 minutes)
    f = Client(port, base)
    f.get("/admin/login")
    codes = []
    for _ in range(8):
        codes.append(f.post("/admin/login", {"login": "patrick", "password": "wrong"})[0])
    s, h, b = f.post("/admin/login", {"login": "patrick", "password": STRONG2})
    ok(codes == [401] * 8 and s == 429 and "Too many failed attempts" in b, f"{label}: account locked after 8 failures {codes} {s}")


def test_flow(exe=LINUX, runner=None):
    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    proc, port = start_server(exe, site, runner=runner)
    try:
        c = Client(port)
        setup_wizard(c, site, "server")
        admin_flow(c, port, "", site, "server")
        t0 = time.perf_counter()
        g = Client(port)
        g.get("/admin/login")
        g.post("/admin/login", {"login": "nobody", "password": "x" * 12})
        print(f"  sign-in check takes {(time.perf_counter() - t0) * 1000:.0f} ms (Argon2id)")
    finally:
        stop(proc)
        shutil.rmtree(site, ignore_errors=True)


# ---------------------------------------------------------------- cgi (direct)

def run_cgi(exe, env, body=b"", argv=(), runner=None):
    full = {"PATH": os.environ.get("PATH", ""), "GATEWAY_INTERFACE": "CGI/1.1", **env}
    r = subprocess.run((runner or []) + [str(exe), *argv], input=body, capture_output=True, env=full, timeout=60)
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
    prog = work / "wordcore.cgi"
    shutil.copy2(exe, prog)
    env = {"SERVER_NAME": "example.com", "SERVER_PORT": "443", "HTTPS": "on", "HTTP_HOST": "example.com",
           "SCRIPT_NAME": "/wc/wordcore.cgi", "REMOTE_ADDR": "203.0.113.9"}
    try:
        s, h, b, r = run_cgi(prog, {**env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/_wc/health"}, runner=runner)
        j = json.loads(b)
        ok(s == 200 and j["mode"] == "cgi" and j["public_url"] == "https://example.com/wc", "cgi health + address")
        ok(int(h["content-length"]) == len(b), "content-length matches")
        ok((work / "site" / "site.db").exists(), "site folder next to program")
        ok((work / "site" / ".htaccess").exists(), "site folder guarded")
        s, h, b, r = run_cgi(prog, {**env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/"}, runner=runner)
        ok(s == 303 and h.get("location") == "/wc/setup", "cgi: setup redirect keeps subfolder")
        s, h, b, r = run_cgi(prog, {**env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/setup"}, runner=runner)
        ok(s == 200 and b"File Manager" in b and "Secure" in h.get("set-cookie", "") and "Path=/wc" in h.get("set-cookie", ""),
           "cgi: code page explains File Manager, cookie Secure + Path=/wc")
        s, h, b, r = run_cgi(prog, {**env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/_wc/health"}, argv=["run", "/etc/passwd"], runner=runner)
        ok(s == 200, "cgi ignores command-line arguments")
        times = []
        for _ in range(15):
            t0 = time.perf_counter()
            run_cgi(prog, {**env, "REQUEST_METHOD": "GET", "REQUEST_URI": "/wc/"}, runner=runner)
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
    for port, base, site in ((8085, "/wctest", Path("/srv/wc/sub_root/wctest/site")), (8086, "", Path("/srv/wc/root_root/site"))):
        label = f"apache {'subfolder' if base else 'web root'}"
        c = Client(port, base)
        s, h, b = c.get("/_wc/health")
        j = json.loads(b)
        ok(j["mode"] == "cgi" and j["base_path"] == base, f"{label}: CGI with base path")
        setup_wizard(c, site, label)
        admin_flow(c, port, base, site, label)
        s, h, b = c.get("/site/site.db")
        ok(s in (403, 404) and "SQLite" not in b, f"{label}: database not downloadable ({s})")
        s, h, b = c.get("/public/hello.txt")
        ok(s == 200 and b.strip() == "static file", f"{label}: public/ served by Apache")
        s, h, b = c.get("/wordcore.cgi/_wc/health")
        ok(s == 200, f"{label}: direct program URL works")
        times = []
        for _ in range(30):
            t0 = time.perf_counter()
            Client(port, base).get("/admin/login")
            times.append((time.perf_counter() - t0) * 1000)
        print(f"  {label}: median {statistics.median(times):.1f} ms for the login page through Apache CGI")
        ok(statistics.median(times) < 150, f"{label}: fast enough")


# ---------------------------------------------------------------- other platforms

def test_wine():
    exe = DIST / "windows-x64" / "wordcore.exe"
    if not exe.exists() or not shutil.which("wine"):
        print("  skipped: no Windows build or no wine")
        return
    env = {**os.environ, "WINEDEBUG": "-all"}
    r = subprocess.run(["wine", str(exe), "version"], capture_output=True, text=True, env=env, timeout=120)
    ok(r.returncode == 0 and "Lua 5.5" in r.stdout and "windows" in r.stdout, "windows: version")
    test_unit(exe, runner=["wine"])
    test_flow(exe, runner=["wine"])


def test_arm64():
    exe = DIST / "linux-arm64" / "wordcore"
    q = shutil.which("qemu-aarch64-static") or shutil.which("qemu-aarch64")
    if not exe.exists() or not q:
        print("  skipped: no arm64 build or no qemu")
        return
    r = subprocess.run([q, str(exe), "version"], capture_output=True, text=True, timeout=60)
    ok(r.returncode == 0 and "arm64" in r.stdout, "arm64: version")
    test_unit(exe, runner=[q])
    test_cgi(exe, runner=[q])


def test_browser():
    script = ROOT / "tests" / "browser" / "clickthrough.js"
    node = shutil.which("node")
    if not node:
        print("  skipped: no node")
        return
    site = Path(tempfile.mkdtemp(prefix="wc-site-"))
    proc, port = start_server(LINUX, site)
    out = Path(os.environ.get("WC_SHOTS") or tempfile.mkdtemp(prefix="wc-shots-"))
    try:
        env = {**os.environ, "NODE_PATH": subprocess.run(["npm", "root", "-g"], capture_output=True, text=True).stdout.strip()}
        r = subprocess.run([node, str(script), f"http://127.0.0.1:{port}", str(site), str(out)],
                           capture_output=True, text=True, env=env, timeout=300)
        sys.stdout.write("".join("  " + line + "\n" for line in r.stdout.strip().splitlines()))
        if r.stderr.strip():
            sys.stdout.write(r.stderr[-2000:])
        ok(r.returncode == 0, "browser click-through")
        print(f"  screenshots: {out}")
    finally:
        stop(proc)
        shutil.rmtree(site, ignore_errors=True)


GROUPS = {"unit": test_unit, "server": test_server, "flow": test_flow, "cgi": test_cgi, "apache": test_apache,
          "wine": test_wine, "arm64": test_arm64, "browser": test_browser}


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
            import traceback
            traceback.print_exc()
            ok(False, f"crashed: {e!r}")
    print(f"\n{results['passed']} passed, {results['failed']} failed")
    sys.exit(1 if results["failed"] else 0)


if __name__ == "__main__":
    main()
