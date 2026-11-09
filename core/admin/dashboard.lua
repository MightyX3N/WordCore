-- WordCore — admin dashboard.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local native = require("wc.native")
local sqlite = require("wc.sqlite")
local settings = require("wc.platform.settings")
local log = require("wc.platform.log")
local path = require("wc.lib.path")
local html = require("wc.lib.html")
local users = require("wc.people.users")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local dashboard = {}

local MODE_TEXT = {
  cgi = "Running on shared hosting (CGI)",
  server_local = "Running locally",
  server = "Running as a server",
}

local function is_local(req)
  local ip = req.client_ip or ""
  local h = (req.host or ""):gsub(":%d+$", "")
  return (ip == "127.0.0.1" or ip == "::1") and (h == "localhost" or h == "127.0.0.1" or h == "[::1]")
end

-- Site health checks: { state = ok|warn|bad, html = ... }
function dashboard.health(req)
  local items = {}
  local function add(state, text) items[#items + 1] = { state = state, html = text } end

  -- HTTPS
  if req.scheme == "https" then
    add("ok", "Visitors connect over HTTPS")
  elseif is_local(req) then
    add("ok", "HTTP on this computer only (fine for building the site)")
  else
    add("warn", "This address uses plain HTTP. Logins and pages can be read on the way. Use HTTPS before going live.")
  end

  -- Proxy headers
  if #req.proxy.seen > 0 and not req.proxy.trusted then
    add("warn", ('Requests come through a proxy or tunnel (<code>%s</code>) but its headers aren\'t trusted, so links may use the wrong address. <a href="%s">Turn on trust proxy headers</a> if this is your tunnel.'):format(
      esc(table.concat(req.proxy.seen, ", ")), esc(req:url_for("/admin/settings#proxy"))))
  elseif req.proxy.trusted and #req.proxy.seen == 0 and not is_local(req) then
    add("warn", "Trust proxy headers is on, but this request didn't come through a proxy. If nothing sits in front of WordCore, turn it off — otherwise visitors could fake their address.")
  else
    add("ok", req.proxy.trusted and "Proxy headers trusted — the site address comes from your tunnel or proxy" or "Site address detected directly")
  end

  -- Data folder protection
  if req.mode == "cgi" then
    if path.exists(path.join(req.site.dir, ".htaccess")) then
      add("ok", "Data folder is blocked from the web")
    else
      add("bad", "The data folder's .htaccess is missing — your database might be downloadable.")
    end
  else
    add("ok", "Data folder is never served by the built-in server")
  end

  -- Database
  if req.db.journal_mode == "wal" then
    add("ok", "Database in WAL mode (safe with several visitors at once)")
  else
    add("warn", ("Database journal mode is %s; WAL isn't available on this filesystem."):format(esc(req.db.journal_mode)))
  end

  -- Setup code file left behind
  if path.exists(path.join(req.site.dir, "setup-code.txt")) then
    os.remove(path.join(req.site.dir, "setup-code.txt"))
  end
  return items
end

local function stat(label, value, note, note_class)
  return ('<div class="card stat"><p class="stat-label">%s</p><p class="stat-value">%s</p>%s</div>'):format(
    esc(label), esc(value), note and ('<p class="stat-note %s">%s</p>'):format(esc(note_class or ""), esc(note)) or "")
end

local ACTION_TEXT = {
  ["login"] = "signed in", ["logout"] = "signed out", ["login.failed"] = "Failed sign-in",
  ["login.denied"] = "Sign-in refused", ["setup.done"] = "created the site", ["setup.code"] = "Setup code accepted",
  ["settings.saved"] = "Settings changed", ["account.password"] = "changed their password",
  ["account.profile"] = "updated their profile", ["account.sessions"] = "signed out other devices",
  ["account.2fa_on"] = "turned on 2-step login", ["account.2fa_off"] = "turned off 2-step login", ["account.2fa_codes"] = "made new recovery codes",
  ["login.2fa_failed"] = "Wrong 2-step code", ["page.created"] = "Page created", ["page.saved"] = "Page saved", ["page.deleted"] = "Page deleted",
  ["page.restored"] = "Page restored", ["media.uploaded"] = "Uploaded", ["media.deleted"] = "File deleted", ["menus.changed"] = "Menu changed",
  ["themes.activated"] = "Theme changed", ["themes.customised"] = "Theme customised", ["users.added"] = "Person added",
  ["users.role"] = "Role changed", ["users.password"] = "Password reset", ["users.signout"] = "Signed out everywhere",
  ["users.2fa_off"] = "2-step login turned off", ["users.deleted"] = "Account deleted", ["account.registered"] = "New member signed up",
}

local function get(req)
  local os_name, arch = native.platform()
  local mode_key = req.mode == "cgi" and "cgi" or (is_local(req) and "server_local" or "server")
  local _, db_size = native.stat(req.site.db_path)
  local _, wal_size = native.stat(req.site.db_path .. "-wal")

  -- status strip
  local strip = ('<section class="card status-strip" aria-label="Where the site is running">'
    .. '<span class="status-item"><span class="status-live" aria-hidden="true"></span><strong>%s</strong></span>'
    .. '<span class="status-item"><span class="muted">Address</span><code>%s</code></span>'
    .. '<span class="status-item">%s</span>'
    .. '%s</section>'):format(
      esc(MODE_TEXT[mode_key]), esc(req.public_url),
      req.proxy.trusted and ui.badge("via proxy / tunnel", "accent") or (req.scheme == "https" and ui.badge("HTTPS", "ok") or ui.badge("HTTP", "")),
      users.can(req.user, "settings.manage") and ('<a href="' .. esc(req:url_for("/admin/settings")) .. '">Settings</a>') or "")

  local pages = require("wc.content.pages")
  local media = require("wc.content.media")
  local n_pages, n_drafts = pages.count(req.db)
  local n_media, media_bytes = media.stats(req.db)
  local n_members = req.db:first("SELECT COUNT(*) AS n FROM wc_users WHERE role = 'member'").n
  local n_users = users.count(req.db)
  local stats = '<section class="grid" aria-label="Site numbers">'
    .. stat("Pages", tostring(n_pages), n_drafts > 0 and (n_drafts .. " draft" .. (n_drafts == 1 and "" or "s")) or "All published")
    .. stat("Media", tostring(n_media), ui.bytes(media_bytes))
    .. stat("People", tostring(n_users), n_members > 0 and (n_members .. " member" .. (n_members == 1 and "" or "s")) or "No members yet")
    .. stat("Database", ui.bytes((db_size or 0) + (wal_size or 0)), "SQLite " .. sqlite.version())
    .. "</section>"

  -- activity
  local rows = log.recent(req.db, 8)
  local act = {}
  for _, r in ipairs(rows) do
    local text = ACTION_TEXT[r.action] or r.action
    local who = r.username and (r.username .. " ") or ""
    if text:match("^%l") then text = who .. text else text = text .. (r.detail and (" — " .. r.detail) or "") end
    act[#act + 1] = ('<li><span class="grow">%s</span><span class="when">%s</span></li>'):format(esc(text), esc(ui.ago(r.at)))
  end
  local activity = ui.card("Recent activity", #act > 0 and ('<ul class="list">' .. table.concat(act) .. "</ul>") or '<p class="empty">Nothing yet.</p>', { id = "activity-h" })

  -- recently edited pages
  local recent = req.db:query([[SELECT p.id, p.title, p.status, p.publish_at, p.updated_at, u.username FROM wc_pages p
                                LEFT JOIN wc_users u ON u.id = p.updated_by ORDER BY p.updated_at DESC, p.id DESC LIMIT 5]])
  local rp = {}
  for _, p in ipairs(recent) do
    local st = pages.state(p)
    rp[#rp + 1] = ('<li><span class="grow"><a href="%s">%s</a><br><span class="small muted">%s%s</span></span>%s</li>'):format(
      esc(req:url_for("/admin/pages/" .. p.id)), esc(p.title), esc(ui.ago(p.updated_at)), p.username and (" · " .. esc(p.username)) or "",
      st == "published" and "" or ui.badge(st == "draft" and "Draft" or "Scheduled", st == "draft" and "warn" or "accent"))
  end
  local recent_pages = ""
  if users.can(req.user, "content.edit_own") then
    recent_pages = ui.card("Recently edited", #rp > 0 and ('<ul class="list">' .. table.concat(rp) .. "</ul>") or '<p class="empty">No pages yet.</p>',
      { id = "recent-h", aside = ('<a class="btn btn-sm" href="%s">New page</a>'):format(esc(req:url_for("/admin/pages/new"))) })
  end
  local about = ui.card("This copy of WordCore", ('<div class="card-body"><dl class="facts"><dt>Version</dt><dd>%s</dd><dt>System</dt><dd>%s %s</dd><dt>Site created</dt><dd>%s</dd></dl></div>'):format(
    esc((WORDCORE_VERSION or "dev"):match("^[^+]+")), esc(os_name), esc(arch), esc(os.date("%d %b %Y", settings.get(req.db, "site.created_at", os.time())))), { id = "about-h" })

  local health = ui.card("Site health", '<div class="card-body">' .. ui.checks(dashboard.health(req)) .. "</div>", { id = "health-h" })

  local body = strip .. stats .. '<div class="cols"><div class="col-main">' .. recent_pages .. activity .. "</div>"
    .. '<div class="col-side">' .. health .. about .. "</div></div>"

  return page.admin(req, {
    title = "Dashboard", subtitle = "Everything about your site at a glance.", active = "dashboard", body = body,
  })
end

function dashboard.register(r)
  r:get("/admin", get, { name = "admin", auth = "admin.access" })
end

return dashboard
