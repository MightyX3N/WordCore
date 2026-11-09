-- WordCore — admin sign in (with 2-step login) and sign out.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local login = require("wc.people.login")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local auth = {}

auth.safe_next = login.safe_next

local function login_page(req, err, login_value, status)
  local nxt = login.safe_next(req.query.next or req:form().next)
  local body = ('<div><h1>Sign in</h1><p class="intro">to %s</p></div>'):format(esc(settings.get(req.db, "site.name")))
    .. ('<form method="post" action="%s" class="form" novalidate>'):format(esc(req:url_for("/admin/login")))
    .. ui.csrf(req.session.csrf)
    .. (nxt and ('<input type="hidden" name="next" value="%s">'):format(esc(nxt)) or "")
    .. (err and ('<div class="flash bad" role="alert">%s</div>'):format(esc(err)) or "")
    .. ui.field({ name = "login", label = "Username or email", value = login_value, required = true, autocomplete = "username", autofocus = true, spellcheck = "false" })
    .. ui.field({ name = "password", label = "Password", type = "password", required = true, autocomplete = "current-password" })
    .. '<button type="submit" class="btn btn-primary btn-lg btn-block">Sign in</button></form>'
  local res = page.auth(req, {
    title = "Sign in", body = body, small = true,
    side_kicker = settings.get(req.db, "site.name"), side_lead = "Welcome back.",
  })
  if status then res.status = status end
  return res
end

local function code_page(req, err, status)
  local body = '<div><h1>2-step login</h1><p class="intro">Enter the 6-digit code from your authenticator app. Lost your phone? Use one of your recovery codes.</p></div>'
    .. ('<form method="post" action="%s" class="form" novalidate>'):format(esc(req:url_for("/admin/login/verify")))
    .. ui.csrf(req.session.csrf)
    .. (err and ('<div class="flash bad" role="alert">%s</div>'):format(esc(err)) or "")
    .. ui.field({ name = "code", label = "Code", required = true, autocomplete = "one-time-code", autofocus = true, inputmode = "numeric", class = "code-input", spellcheck = "false" })
    .. '<button type="submit" class="btn btn-primary btn-lg btn-block">Verify</button></form>'
    .. ('<p class="small muted"><a href="%s">Start over</a></p>'):format(esc(req:url_for("/admin/login")))
  local res = page.auth(req, { title = "2-step login", body = body, small = true,
    side_kicker = settings.get(req.db, "site.name"), side_lead = "One more step." })
  if status then res.status = status end
  return res
end

local function get_login(req)
  if req.user and users.can(req.user, "admin.access") then
    return http.new_response():redirect(req:url_for(login.safe_next(req.query.next) or "/admin"))
  end
  session.ensure(req, req.db)
  return login_page(req)
end

local function post_login(req)
  local f = req:form()
  local result, err, status = login.attempt(req, f.login, f.password, f.next, "admin")
  if result == "2fa" then return http.new_response():redirect(req:url_for("/admin/login/verify")) end
  if not result then return login_page(req, err, (f.login or ""):sub(1, 254), status) end
  return http.new_response():redirect(req:url_for(login.safe_next(f.next) or "/admin"))
end

local function get_verify(req)
  if not login.pending(req) then return http.new_response():redirect(req:url_for("/admin/login")) end
  return code_page(req)
end

local function post_verify(req)
  local result, nxt_or_err, status = login.verify(req, req:form().code)
  if result == "ok" then return http.new_response():redirect(req:url_for(nxt_or_err or "/admin")) end
  if status == 410 then
    session.flash(req, "bad", nxt_or_err)
    return http.new_response():redirect(req:url_for("/admin/login"))
  end
  return code_page(req, nxt_or_err, status)
end

local function post_logout(req)
  if req.user then log.add(req.db, req, "logout", nil) end
  session.destroy(req, req.db)
  return http.new_response():redirect(req:url_for("/admin/login"))
end

function auth.register(r)
  r:get("/admin/login", get_login, { name = "login" })
  r:post("/admin/login", post_login)
  r:get("/admin/login/verify", get_verify)
  r:post("/admin/login/verify", post_verify)
  r:post("/admin/logout", post_logout)
end

return auth
