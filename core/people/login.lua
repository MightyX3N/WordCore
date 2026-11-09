-- WordCore — the sign-in logic shared by the admin and the public site:
-- rate limits, password check, the 2-step login step, starting the session.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local session = require("wc.platform.session")
local ratelimit = require("wc.platform.ratelimit")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local twofactor = require("wc.people.twofactor")

local login = {}

login.IP_LIMIT, login.IP_WINDOW = 20, 900
login.USER_LIMIT, login.USER_WINDOW = 8, 900
login.PENDING_TTL = 300
login.CODE_TRIES = 5

-- Only allow redirects to paths inside this site (no open redirects).
function login.safe_next(n)
  if type(n) ~= "string" or n == "" then return nil end
  if n:sub(1, 1) ~= "/" or n:sub(1, 2) == "//" or n:find("[\\%c]") or n:find("^/[^/]*:") then return nil end
  return n
end

local function minutes(s) return math.max(1, math.ceil(s / 60)) end

-- Step 1: username/email + password.
-- Returns "ok" | "2fa" | nil, message, status
function login.attempt(req, login_name, password, next_path, area)
  login_name = (login_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local user_key = "login:user:" .. login_name:lower()
  local blocked, retry = ratelimit.blocked(req.db, user_key, login.USER_LIMIT)
  if blocked then
    return nil, ("Too many failed attempts for this account. Try again in %d minutes."):format(minutes(retry)), 429
  end
  local ok_ip, retry_ip = ratelimit.hit(req.db, "login:ip:" .. (req.client_ip or "?"), login.IP_LIMIT, login.IP_WINDOW)
  if not ok_ip then
    return nil, ("Too many sign-in attempts from your network. Try again in %d minutes."):format(minutes(retry_ip)), 429
  end
  local user = users.authenticate(req.db, login_name, password)
  if not user then
    ratelimit.hit(req.db, user_key, login.USER_LIMIT, login.USER_WINDOW)
    log.add(req.db, req, "login.failed", login_name ~= "" and ("for " .. login_name:sub(1, 64)) or nil)
    return nil, "Wrong username or password.", 401
  end
  if area == "admin" and not users.can(user, "admin.access") then
    log.add(req.db, req, "login.denied", "no admin access: " .. user.username)
    return nil, "This account can't use the admin. Sign in on the site instead.", 403
  end
  ratelimit.clear(req.db, user_key)
  if twofactor.enabled(user) then
    session.ensure(req, req.db)
    session.set(req, "pending_login", { user_id = user.id, at = os.time(), next = login.safe_next(next_path), area = area, tries = 0 })
    return "2fa"
  end
  login.complete(req, user)
  return "ok"
end

function login.complete(req, user, how)
  session.login(req, req.db, user)
  log.add(req.db, req, "login", how and ("signed in with " .. how) or nil)
end

-- The pending sign-in waiting for a code, or nil.
function login.pending(req)
  local p = req.session and req.session.data.pending_login
  if type(p) ~= "table" then return nil end
  if os.time() - (p.at or 0) > login.PENDING_TTL then
    session.set(req, "pending_login", nil)
    return nil
  end
  return p
end

-- Step 2: the code. Returns "ok", next | nil, message, status
function login.verify(req, code)
  local p = login.pending(req)
  if not p then return nil, "That took too long. Sign in again.", 410 end
  local user = users.get(req.db, p.user_id)
  if not user or not twofactor.enabled(user) then return nil, "Sign in again.", 410 end
  local ok_rate, retry = ratelimit.hit(req.db, "2fa:user:" .. user.id, 10, 900)
  if not ok_rate then return nil, ("Too many wrong codes. Try again in %d minutes."):format(minutes(retry)), 429 end
  local ok, how = twofactor.check(req.db, user, code)
  if not ok then
    p.tries = (p.tries or 0) + 1
    if p.tries >= login.CODE_TRIES then
      session.set(req, "pending_login", nil)
      log.add(req.db, req, "login.failed", "wrong 2-step codes for " .. user.username)
      return nil, "Too many wrong codes. Sign in again.", 410
    end
    session.set(req, "pending_login", p)
    return nil, "That code didn't work. Try the newest code from your app.", 401
  end
  session.set(req, "pending_login", nil)
  login.complete(req, users.get(req.db, user.id), how == "recovery" and "a recovery code" or "2-step login")
  return "ok", p.next
end

return login
