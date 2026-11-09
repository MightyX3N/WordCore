-- WordCore — Phase 0 "hello" application.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- A host check: proves the program runs here, can write its site folder, can
-- use SQLite, and works out its own address correctly. Replaced by the real
-- core in Phase 1.

local native = require("wc.native")
local sqlite = require("wc.sqlite")
local http = require("wc.platform.http")
local html = require("wc.lib.html")
local path = require("wc.lib.path")
local json = require("wc.lib.json")

local esc = html.escape

local function elapsed_ms(req)
  if req.started then return (native.now() - req.started) * 1000 end
  return native.uptime() * 1000 -- CGI: the whole process lifetime so far
end

local function check_write(site)
  local probe = path.join(site.dir, ".write-check")
  local ok, err = path.write(probe, "ok")
  if not ok then return false, tostring(err) end
  os.remove(probe)
  return true, "site/ next to the program"
end

local function hex(s)
  return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

local function count_visit(site, req)
  local conn = site.db
  conn:migrate("hello", {
    [[CREATE TABLE hello_visits (
        id INTEGER PRIMARY KEY,
        at TEXT NOT NULL DEFAULT (datetime('now')),
        mode TEXT NOT NULL,
        ms REAL)]],
  })
  conn:run("INSERT INTO hello_visits (mode) VALUES (?)", req.mode)
  return conn:first("SELECT COUNT(*) AS n FROM hello_visits").n
end

local function row(ok, label, detail)
  local mark = ok and '<span class="ok" aria-label="OK">✓</span>' or '<span class="bad" aria-label="Problem">!</span>'
  return ('<li>%s<div><strong>%s</strong><span>%s</span></div></li>'):format(mark, esc(label), detail)
end

local function page(req, ctx)
  local site = ctx.site
  local os_name, arch = native.platform()
  local write_ok, write_detail = check_write(site)
  local visits_ok, visits = pcall(count_visit, site, req)
  local rnd_ok, rnd = pcall(native.random_bytes, 8)
  local ms = elapsed_ms(req)

  local proxy_detail
  if #req.proxy.seen == 0 then
    proxy_detail = "No proxy or tunnel headers in this request."
  else
    proxy_detail = ("Seen: <code>%s</code> — %s"):format(esc(table.concat(req.proxy.seen, ", ")),
      req.proxy.trusted and "trusted (the address above uses them)."
        or "not trusted. If this site is behind a tunnel or proxy, turn on <em>trust proxy headers</em>.")
  end

  local items = {
    row(true, "WordCore runs here", ("%s mode · %s %s · %s · SQLite %s"):format(
      esc(req.mode == "cgi" and "CGI" or "Server"), esc(os_name), esc(arch), esc(LUA_RELEASE or _VERSION), esc(sqlite.version()))),
    row(write_ok, "Site folder is writable", write_ok and esc(write_detail) or ("<code>%s</code>"):format(esc(write_detail))),
    row(visits_ok and site.db.journal_mode == "wal", "Database works",
      visits_ok and ("SQLite in %s mode · this page has been loaded <strong>%d</strong> time%s"):format(
        esc(site.db.journal_mode:upper()), visits, visits == 1 and "" or "s") or esc(tostring(visits))),
    row(rnd_ok, "Secure random numbers", rnd_ok and ("<code>%s</code>"):format(hex(rnd)) or esc(tostring(rnd))),
    row(true, "Site address", ("<code>%s</code> · base path <code>%s</code> · visitor %s"):format(
      esc(req.public_url), esc(req.base_path == "" and "/" or req.base_path), esc(req.client_ip))),
    row(true, "Proxy and tunnel", proxy_detail),
    row(ms < 250, "Speed", ("%.1f ms to build this page%s"):format(ms, req.mode == "cgi" and " (including starting the program)" or "")),
  }

  return ([[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WordCore host check</title>
<style>
:root{--bg:#F6F6F3;--card:#fff;--ink:#17171A;--ink2:#4A4A50;--line:#E4E4DF;--accent:#2456D6;--ok:#1F7A4D;--okbg:#E6F4EC;--bad:#9A5B00;--badbg:#FDF3E1}
@media (prefers-color-scheme: dark){:root{--bg:#121214;--card:#1C1C20;--ink:#F1F1F3;--ink2:#B4B4BC;--line:#2E2E34;--accent:#7FA2FF;--ok:#6FD3A0;--okbg:#173326;--bad:#F2B661;--badbg:#3A2A12}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:48px 20px 64px}
.brand{display:flex;align-items:center;gap:10px;font-weight:600;font-size:18px;margin-bottom:28px}
.logo{width:30px;height:30px;border-radius:7px;background:#2456D6;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700}
h1{font-size:30px;line-height:1.2;margin:0 0 6px}
.lead{color:var(--ink2);margin:0 0 28px}
ul{list-style:none;margin:0;padding:0;background:var(--card);border:1px solid var(--line);border-radius:12px}
li{display:flex;gap:14px;align-items:flex-start;padding:16px 18px;border-bottom:1px solid var(--line)}
li:last-child{border-bottom:0}
li div{display:flex;flex-direction:column;gap:2px;min-width:0}
li span{color:var(--ink2);font-size:14px;overflow-wrap:anywhere}
.ok,.bad{flex-shrink:0;width:24px;height:24px;border-radius:50%%;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:13px}
.ok{background:var(--okbg);color:var(--ok)}
.bad{background:var(--badbg);color:var(--bad)}
code{font-family:ui-monospace,"JetBrains Mono",Consolas,monospace;font-size:13px}
.links{margin-top:22px;font-size:14px;color:var(--ink2)}
a{color:var(--accent)}
</style>
</head>
<body>
<main>
<div class="brand"><span class="logo" aria-hidden="true">W</span>WordCore</div>
<h1>Host check</h1>
<p class="lead">WordCore %s is running. This page checks everything WordCore needs on this host.</p>
<ul>
%s
</ul>
<p class="links">Machine-readable: <a href="%s">health</a> · <a href="%s">request echo</a></p>
</main>
</body>
</html>
]]):format(esc(ctx.version), table.concat(items, "\n"), esc(req:url_for("/health")), esc(req:url_for("/echo?hello=world")))
end

local function health(req, ctx)
  local os_name, arch = native.platform()
  return {
    ok = true,
    wordcore = ctx.version,
    lua = LUA_RELEASE or _VERSION,
    sqlite = sqlite.version(),
    platform = os_name .. "-" .. arch,
    mode = req.mode,
    public_url = req.public_url,
    base_path = req.base_path,
    proxy_trusted = req.proxy.trusted,
  }
end

local function echo(req)
  local form = req:form()
  return {
    method = req.method,
    path = req.path,
    raw_path = req.raw_path,
    base_path = req.base_path,
    query = json.object(req.query),
    form = json.object(form),
    body_length = #req.body,
    scheme = req.scheme,
    host = req.host,
    public_url = req.public_url,
    client_ip = req.client_ip,
    proxy = { seen = json.array(req.proxy.seen), trusted = req.proxy.trusted },
    mode = req.mode,
    url_for_example = req:url_for("/some/page"),
  }
end

return function(req, ctx)
  local res = http.new_response(200)
  res:set_header("Cache-Control", "no-store")
  local p = req.path
  if p == "/" then
    if req.method ~= "GET" and req.method ~= "HEAD" then
      return http.error_page(405, "Only GET works here."):set_header("Allow", "GET, HEAD")
    end
    return res:html(page(req, ctx))
  elseif p == "/health" then
    return res:json(health(req, ctx))
  elseif p == "/echo" then
    return res:json(echo(req))
  end
  return http.error_page(404, "There's nothing at " .. p .. " yet.")
end
