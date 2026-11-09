-- WordCore — your account: profile, password, signed-in devices.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local crypto = require("wc.lib.crypto")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local account = {}

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function describe_agent(ua)
  ua = ua or ""
  local browser = ua:find("Edg/") and "Edge" or ua:find("Firefox/") and "Firefox" or ua:find("Chrome/") and "Chrome"
    or ua:find("Safari/") and "Safari" or (ua ~= "" and "Browser" or "Unknown")
  local os_name = ua:find("Windows") and "Windows" or ua:find("Android") and "Android" or (ua:find("iPhone") or ua:find("iPad")) and "iOS"
    or ua:find("Mac OS") and "macOS" or ua:find("Linux") and "Linux" or nil
  return browser .. (os_name and (" on " .. os_name) or "")
end

local function render(req, errors, values, status)
  errors, values = errors or {}, values or {}
  local u = req.user
  local profile = ui.form({ action = req:url_for("/admin/account/profile"), csrf = req.session.csrf, submit = "Save profile", sections = {
    { title = "Profile", fields = {
      { name = "username", label = "Username", value = u.username, hint = "Your username can't be changed yet.", type = "text", readonly = true },
      { name = "display_name", label = "Your name", value = values.display_name or u.display_name, max = 80, error = errors.display_name, autocomplete = "name" },
      { name = "email", label = "Email", type = "email", value = values.email or u.email, max = 254, error = errors.email, optional = true, autocomplete = "email" },
    }},
  }})

  local password = ui.form({ action = req:url_for("/admin/account/password"), csrf = req.session.csrf, submit = "Change password", sections = {
    { title = "Password", intro = "Changing your password signs you out on every other device.", fields = {
      { name = "current", label = "Current password", type = "password", error = errors.current, autocomplete = "current-password", required = true },
      { name = "new", label = "New password", type = "password", error = errors.new, autocomplete = "new-password", strength = true, hint = "At least 10 characters.", required = true },
      { name = "new2", label = "Repeat new password", type = "password", error = errors.new2, autocomplete = "new-password", required = true },
    }},
  }})

  local rows = {}
  local list = session.list_for_user(req.db, u.id)
  for _, s in ipairs(list) do
    local this = s.token_hash == req.session.token_hash
    rows[#rows + 1] = ('<li class="session-row"><span class="grow"><strong>%s</strong>%s<br><span class="muted small">%s · started %s</span></span><span class="when">active %s</span></li>'):format(
      esc(describe_agent(s.user_agent)), this and ' <span class="badge ok">This device</span>' or "",
      esc(s.ip or "unknown address"), esc(ui.ago(s.created_at)), esc(ui.ago(s.seen_at)))
  end
  local others = #list - 1
  local sessions_html = '<ul class="list">' .. table.concat(rows) .. "</ul>"
  if others > 0 then
    sessions_html = sessions_html .. ('<div class="card-foot"><form method="post" action="%s" data-confirm="Sign out on every other device?">%s<button type="submit" class="btn btn-danger">Sign out %d other device%s</button></form></div>'):format(
      esc(req:url_for("/admin/account/sessions")), ui.csrf(req.session.csrf), others, others == 1 and "" or "s")
  end
  local devices = ui.card("Signed-in devices", sessions_html, { id = "devices-h" })

  local res = page.admin(req, {
    title = "Your account", subtitle = users.role_label(u.role) .. " · last signed in " .. ui.ago(u.last_login_at),
    active = "account", body = profile .. password .. devices, narrow = true,
  })
  if status then res.status = status end
  return res
end

local function get(req) return render(req) end

local function post_profile(req)
  local f = req:form()
  local v = { display_name = trim(f.display_name), email = trim(f.email) }
  local errors = {}
  if #v.display_name > 80 then errors.display_name = "Use at most 80 characters." end
  errors.email = users.validate_email(v.email, false)
  if next(errors) then return render(req, errors, v, 422) end
  users.update_profile(req.db, req.user.id, v.display_name ~= "" and v.display_name or req.user.username, v.email)
  log.add(req.db, req, "account.profile", nil)
  session.flash(req, "ok", "Profile saved.")
  return http.new_response():redirect(req:url_for("/admin/account"))
end

local function post_password(req)
  local f = req:form()
  local errors = {}
  if not crypto.verify_password(f.current or "", req.user.password_hash) then
    errors.current = "That isn't your current password."
  else
    errors.new = users.validate_password(f.new, req.user.username)
    if not errors.new and f.new ~= f.new2 then errors.new2 = "The passwords don't match." end
    if not errors.new and f.new == f.current then errors.new = "Choose a different password from the current one." end
  end
  if next(errors) then return render(req, errors, nil, 422) end
  users.set_password(req.db, req.user.id, f.new)
  local user = users.get(req.db, req.user.id)
  session.login(req, req.db, user, true)       -- new session token
  session.destroy_others(req, req.db)          -- everyone else is signed out
  log.add(req.db, req, "account.password", nil)
  session.flash(req, "ok", "Password changed. Other devices have been signed out.")
  return http.new_response():redirect(req:url_for("/admin/account"))
end

local function post_sessions(req)
  local n = session.destroy_others(req, req.db)
  log.add(req.db, req, "account.sessions", nil)
  session.flash(req, "ok", ("Signed out %d other device%s."):format(n, n == 1 and "" or "s"))
  return http.new_response():redirect(req:url_for("/admin/account"))
end

function account.register(r)
  r:get("/admin/account", get, { name = "account", auth = "admin.access" })
  r:post("/admin/account/profile", post_profile, { auth = "admin.access" })
  r:post("/admin/account/password", post_password, { auth = "admin.access" })
  r:post("/admin/account/sessions", post_sessions, { auth = "admin.access" })
end

return account
