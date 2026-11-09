# tests/

See [PLAN.md §11](../PLAN.md#11-testing).

```
tests/
├── run.py         # the test runner (Python 3, no extra packages)
├── unit/run.lua   # Lua unit tests, run inside the real program
└── apache/        # local Apache set up like a cPanel host (CGI + .htaccess)
```

Build first (`python runtime/build/build.py`), then:

```
python tests/run.py                  # everything this machine can run
python tests/run.py unit server cgi  # pick groups
```

| Group | What it checks |
|---|---|
| `unit` | JSON, paths, query parsing, address detection (subfolder, web root, proxies, bad Host), database helpers, native functions |
| `server` | the built-in server over real HTTP: pages, forms, large bodies, proxy trust, HEAD, 404/405, malformed requests, huge headers, path traversal, idle/slow clients, keep-alive, pipelining, 200 concurrent requests, speed |
| `cgi` | CGI mode driven with environment variables: address, POST, HEAD, site folder guard, command line ignored, speed |
| `apache` | CGI through a real Apache with `.htaccess`, in a subfolder and the web root: routing, query, POST, `site/` blocked, direct program URL, `public/` files served by Apache, speed. Needs `sudo bash tests/apache/setup.sh` once (Debian/Ubuntu). |
| `wine` | the Windows build under Wine: version, unit tests, server, large body |
| `arm64` | the Linux ARM build under qemu: version, unit tests, CGI |

Still planned: browser end-to-end tests (Playwright) once there is an admin to click through, and security tests for the addon sandbox.
