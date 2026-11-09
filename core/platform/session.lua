-- WordCore — sessions, login state, CSRF tokens and flash messages.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- The cookie holds a random token; the database stores only its BLAKE2b hash,
-- so a leaked database can't be used to take over sessions.

local crypto = require("wc.lib.crypto")
local json = require("wc.lib.json")
local http = require("wc.platform.http")

local session = {}

session.IDLE = 14 * 86400      -- signed-in sessions expire after 14 days without use
session.MAX_AGE = 60 * 86400   -- and after 60 days regardless
session.ANON_IDLE = 2 * 3600   -- anonymous sessions (login/setup forms) last 2 hours
local TOUCH_EVERY = 300

function session.migrate(db)
  db:migrate("core.sessions", {
    [[CREATE TABLE wc_sessions (
        token_hash TEXT PRIMARY KEY,
        user_id INTEGER REFERENCES wc_users(id) ON DELETE CASCADE,
        csrf TEXT NOT NULL,
        data TEXT NOT NULL DEFAULT '{}',
        created_at INTEGER NOT NULL,
        seen_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        ip TEXT,
        user_agent TEXT)]],
    "CREATE INDEX wc_sessions_user ON wc_sessions (user_id)",
  })
end

local function hash(token) return crypto.blake2b_hex(token, 32) end

-- Cookie name is unique per site, so several WordCore sites on localhost
-- (different ports share cookies) don't log each other out.
function session.cookie_name(site_id)
  return "wc_" .. site_id:sub(1, 8)
end

function session.parse_cookies(header)
  local out = {}
  if not header then return out end
  for pair in header:gmatch("[^;]+") do
    local k, v = pair:match("^%s*([^=]+)=(.*)$")
    if k then out[k:gsub("%s+$", "")] = v:gsub("^%s+", ""):gsub("%s+$", "") end
  end
  return out
end

local function cookie_header(req, name, value, max_age)
  local parts = { name .. "=" .. value, "Path=" .. (req.base_path ~= "" and req.base_path or "/"), "HttpOnly", "SameSite=Lax" }
  if max_age then parts[#parts + 1] = "Max-Age=" .. max_age end
  if req.scheme == "https" then parts[#parts + 1] = "Secure" end
  return table.concat(parts, "; ")
end

-- Load the session for this request (or none). Sets req.session and req.user.
function session.load(req, db, site_id, users)
  req.cookie_name = session.cookie_name(site_id)
  local token = session.parse_cookies(req.headers["cookie"])[req.cookie_name]
  if not token or #token < 20 or #token > 100 then return end
  local row = db:first("SELECT * FROM wc_sessions WHERE token_hash = ?", hash(token))
  local now = os.time()
  if not row or row.expires_at <= now then
    if row then db:run("DELETE FROM wc_sessions WHERE token_hash = ?", row.token_hash) end
    req.clear_cookie = true
    return
  end
  row.data = json.decode(row.data) or {}
  if row.data == json.null then row.data = {} end
  row.token = token
  req.session = row
  if row.user_id then
    req.user = users.get(db, row.user_id)
    if not req.user then
      session.destroy(req, db)
      return
    end
  end
  if now - row.seen_at > TOUCH_EVERY then
    local idle = row.user_id and session.IDLE or session.ANON_IDLE
    local expires = math.min(now + idle, row.created_at + session.MAX_AGE)
    db:run("UPDATE wc_sessions SET seen_at = ?, expires_at = ? WHERE token_hash = ?", now, expires, row.token_hash)
  end
end

local function create(req, db, user_id, data)
  local token = crypto.token(32)
  local now = os.time()
  local idle = user_id and session.IDLE or session.ANON_IDLE
  local row = {
    token_hash = hash(token), user_id = user_id, csrf = crypto.token(32), data = data or {},
    created_at = now, seen_at = now, expires_at = now + idle, token = token,
  }
  db:run([[INSERT INTO wc_sessions (token_hash, user_id, csrf, data, created_at, seen_at, expires_at, ip, user_agent)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    row.token_hash, user_id, row.csrf, json.encode(json.object(row.data)), now, now, row.expires_at,
    req.client_ip, (req.headers["user-agent"] or ""):sub(1, 300))
  req.session = row
  req.set_cookie = cookie_header(req, req.cookie_name, token, user_id and session.MAX_AGE or nil)
  return row
end

-- Make sure there is a session (needed before showing a form with a CSRF token).
function session.ensure(req, db)
  if not req.session then create(req, db, nil) end
  return req.session
end

-- Start a signed-in session. Always a brand new token (prevents session fixation).
function session.login(req, db, user, keep_data)
  local data = keep_data and req.session and req.session.data or {}
  if req.session then db:run("DELETE FROM wc_sessions WHERE token_hash = ?", req.session.token_hash) end
  data.setup = nil
  create(req, db, user.id, data)
  req.user = user
end

function session.destroy(req, db)
  if req.session then db:run("DELETE FROM wc_sessions WHERE token_hash = ?", req.session.token_hash) end
  req.session = nil
  req.user = nil
  req.clear_cookie = true
end

-- Sign out every other session of this user (after a password change, or on request).
function session.destroy_others(req, db)
  if not (req.user and req.session) then return 0 end
  local n = db:run("DELETE FROM wc_sessions WHERE user_id = ? AND token_hash <> ?", req.user.id, req.session.token_hash)
  return n
end

function session.list_for_user(db, user_id)
  return db:query("SELECT token_hash, created_at, seen_at, ip, user_agent FROM wc_sessions WHERE user_id = ? ORDER BY seen_at DESC", user_id)
end

function session.save(req, db)
  if req.session and req.session_dirty then
    db:run("UPDATE wc_sessions SET data = ? WHERE token_hash = ?", json.encode(json.object(req.session.data)), req.session.token_hash)
    req.session_dirty = false
  end
end

function session.set(req, key, value)
  req.session.data[key] = value
  req.session_dirty = true
end

---------------------------------------------------------------- flash messages

function session.flash(req, kind, text)
  if not req.session then return end
  local list = req.session.data.flash or {}
  list[#list + 1] = { kind = kind, text = text }
  session.set(req, "flash", list)
end

function session.take_flash(req)
  if not req.session then return {} end
  local list = req.session.data.flash or {}
  if #list > 0 then session.set(req, "flash", nil) end
  return list
end

---------------------------------------------------------------- CSRF

-- Check the CSRF token and Origin header of a state-changing request.
function session.check_csrf(req)
  local origin = req.headers["origin"]
  if origin and origin ~= "null" then
    local host = origin:match("^https?://([^/]+)$")
    if not host or host:lower() ~= (req.host or ""):lower() then return false, "origin" end
  end
  if not req.session then return false, "no session" end
  local sent = req:form()._csrf or req.headers["x-csrf-token"]
  if not sent or not crypto.equal(sent, req.session.csrf) then return false, "token" end
  return true
end

-- Apply cookie changes to the response.
function session.apply(req, res)
  if req.set_cookie then
    res:set_header("Set-Cookie", req.set_cookie)
  elseif req.clear_cookie and req.cookie_name then
    res:set_header("Set-Cookie", cookie_header(req, req.cookie_name, "", 0))
  end
  if req.session or req.set_cookie or req.clear_cookie then
    res:set_header("Cache-Control", "no-store")
  end
end

function session.cleanup(db)
  db:run("DELETE FROM wc_sessions WHERE expires_at <= ?", os.time())
end

session.http = http
return session
