-- WordCore — sign in and sign out.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local ratelimit = require("wc.platform.ratelimit")
local settings = require("wc.platform.settings")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local auth = {}

auth.IP_LIMIT, auth.IP_WINDOW = 20, 900       -- per address: 20 tries per 15 minutes
auth.USER_LIMIT, auth.USER_WINDOW = 8, 900    -- per account: 8 tries per 15 minutes

-- Only allow redirects to paths inside this site (no open redirects).
function auth.safe_next(n)
  if type(n) ~= "string" or n == "" then return nil end
  if n:sub(1, 1) ~= "/" or n:sub(1, 2) == "//" or n:find("[\\%c]") or n:find("^/[^/]*:") then return nil end
  return n
end

local function login_page(req, err, login_value, status)
  local nxt = auth.safe_next(req.query.next or req:form().next)
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

local function get_login(req)
  if req.user and users.can(req.user, "admin.access") then
    return http.new_response():redirect(req:url_for(auth.safe_next(req.query.next) or "/admin"))
  end
  session.ensure(req, req.db)
  return login_page(req)
end

local function minutes(s) return math.max(1, math.ceil(s / 60)) end

local function post_login(req)
  local f = req:form()
  local login = (f.login or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local ip_key = "login:ip:" .. (req.client_ip or "?")
  local user_key = "login:user:" .. login:lower()

  local blocked, retry = ratelimit.blocked(req.db, user_key, auth.USER_LIMIT)
  if blocked then
    return login_page(req, ("Too many failed attempts for this account. Try again in %d minutes."):format(minutes(retry)), login, 429)
  end
  local ok_ip, retry_ip = ratelimit.hit(req.db, ip_key, auth.IP_LIMIT, auth.IP_WINDOW)
  if not ok_ip then
    return login_page(req, ("Too many sign-in attempts from your network. Try again in %d minutes."):format(minutes(retry_ip)), login, 429)
  end

  local user = users.authenticate(req.db, login, f.password)
  if not user then
    ratelimit.hit(req.db, user_key, auth.USER_LIMIT, auth.USER_WINDOW)
    log.add(req.db, req, "login.failed", login ~= "" and ("for " .. login:sub(1, 64)) or nil)
    return login_page(req, "Wrong username or password.", login, 401)
  end
  if not users.can(user, "admin.access") then
    log.add(req.db, req, "login.denied", "no admin access: " .. user.username)
    return login_page(req, "This account can't use the admin.", login, 403)
  end

  ratelimit.clear(req.db, user_key)
  session.login(req, req.db, user)
  log.add(req.db, req, "login", "signed in")
  return http.new_response():redirect(req:url_for(auth.safe_next(f.next) or "/admin"))
end

local function post_logout(req)
  if req.user then log.add(req.db, req, "logout", "signed out") end
  session.destroy(req, req.db)
  return http.new_response():redirect(req:url_for("/admin/login"))
end

function auth.register(r)
  r:get("/admin/login", get_login, { name = "login" })
  r:post("/admin/login", post_login)
  r:post("/admin/logout", post_logout)
end

return auth
