-- WordCore — user accounts, roles and capabilities.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local crypto = require("wc.lib.crypto")

local users = {}

-- Roles from most to least powerful. The owner can never be locked out by roles.
users.ROLES = {
  { id = "owner",  label = "Owner",  caps = { "*" } },
  { id = "admin",  label = "Administrator", caps = { "admin.access", "settings.manage", "users.manage", "themes.manage",
                                                   "menus.manage", "media.upload", "content.edit_any", "content.edit_own", "content.publish" } },
  { id = "editor", label = "Editor", caps = { "admin.access", "menus.manage", "media.upload", "content.edit_any", "content.edit_own", "content.publish" } },
  { id = "author", label = "Author", caps = { "admin.access", "media.upload", "content.edit_own" } },
  { id = "member", label = "Member", caps = {} },
}
local ROLE_BY_ID = {}
for _, r in ipairs(users.ROLES) do
  local set = {}
  for _, c in ipairs(r.caps) do set[c] = true end
  ROLE_BY_ID[r.id] = { label = r.label, caps = set }
end

function users.role_label(id)
  return ROLE_BY_ID[id] and ROLE_BY_ID[id].label or id
end

function users.can(user, cap)
  if not user then return false end
  local role = ROLE_BY_ID[user.role]
  if not role then return false end
  return role.caps["*"] == true or role.caps[cap] == true
end

function users.migrate(db)
  db:migrate("core.users", {
    [[CREATE TABLE wc_users (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        email TEXT NOT NULL DEFAULT '',
        display_name TEXT NOT NULL DEFAULT '',
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (unixepoch()),
        last_login_at INTEGER,
        password_changed_at INTEGER NOT NULL DEFAULT (unixepoch()))]],
    -- 2-step login
    "ALTER TABLE wc_users ADD COLUMN totp_secret TEXT",
    "ALTER TABLE wc_users ADD COLUMN totp_enabled INTEGER NOT NULL DEFAULT 0",
    "ALTER TABLE wc_users ADD COLUMN totp_last_step INTEGER",
    [[CREATE TABLE wc_recovery_codes (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES wc_users(id) ON DELETE CASCADE,
        code_hash TEXT NOT NULL,
        used_at INTEGER)]],
  })
end

function users.count(db)
  return db:first("SELECT COUNT(*) AS n FROM wc_users").n
end

function users.has_owner(db)
  return db:first("SELECT 1 AS x FROM wc_users WHERE role = 'owner' LIMIT 1") ~= nil
end

function users.get(db, id)
  return db:first("SELECT * FROM wc_users WHERE id = ?", id)
end

function users.find_by_login(db, login)
  return db:first("SELECT * FROM wc_users WHERE username = ? OR (email <> '' AND lower(email) = lower(?))", login, login)
end

---------------------------------------------------------------- validation

function users.validate_username(name)
  if not name or #name < 3 then return "Use at least 3 characters." end
  if #name > 32 then return "Use at most 32 characters." end
  if not name:match("^[%w][%w%._%-]*$") then
    return "Use letters, numbers, dots, dashes and underscores, starting with a letter or number."
  end
  return nil
end

function users.validate_email(email, required)
  if not email or email == "" then return required and "Enter an email address." or nil end
  if #email > 254 or not email:match("^[^%s@]+@[^%s@]+%.[^%s@]+$") then
    return "That doesn't look like an email address."
  end
  return nil
end

-- A few of the most common passwords; the length rule catches most of the rest.
local COMMON = {}
for w in ([[password1234 password123 1234567890 qwertyuiop 0123456789 1q2w3e4r5t passwordpassword
  iloveyou123 administrator qwerty12345 abcdefghij 11111111111 letmein123 welcome123 changeme123
  admin12345 trustno1234 football123 superman123 monkey12345]]):gmatch("%S+") do COMMON[w] = true end

-- Rough strength score 0-4 shown in the UI and used to reject weak passwords.
function users.password_score(pw)
  if not pw or #pw < 10 then return 0 end
  local classes = 0
  if pw:find("%l") then classes = classes + 1 end
  if pw:find("%u") then classes = classes + 1 end
  if pw:find("%d") then classes = classes + 1 end
  if pw:find("[^%w]") then classes = classes + 1 end
  local unique = {}
  local n = 0
  for c in pw:gmatch(".") do if not unique[c] then unique[c] = true n = n + 1 end end
  if n < 5 or COMMON[pw:lower()] then return 1 end
  local score = 1
  if #pw >= 12 then score = score + 1 end
  if #pw >= 16 or classes >= 3 then score = score + 1 end
  if #pw >= 20 or (#pw >= 14 and classes >= 3) then score = score + 1 end
  return math.min(score, 4)
end

function users.validate_password(pw, username)
  if not pw or #pw < 10 then return "Use at least 10 characters." end
  if #pw > 1024 then return "That password is too long." end
  if username and pw:lower():find(username:lower(), 1, true) then return "Don't use your username in the password." end
  if users.password_score(pw) < 2 then return "That password is too easy to guess. Make it longer or less predictable." end
  return nil
end

---------------------------------------------------------------- changes

function users.create(db, fields)
  local _, id = db:run([[INSERT INTO wc_users (username, email, display_name, password_hash, role)
                         VALUES (?, ?, ?, ?, ?)]],
    fields.username, fields.email or "", fields.display_name or fields.username,
    fields.password_hash or crypto.hash_password(fields.password), fields.role)
  return id
end

function users.set_password(db, id, password)
  db:run("UPDATE wc_users SET password_hash = ?, password_changed_at = unixepoch() WHERE id = ?",
    crypto.hash_password(password), id)
end

function users.update_profile(db, id, display_name, email)
  db:run("UPDATE wc_users SET display_name = ?, email = ? WHERE id = ?", display_name, email, id)
end

-- Check a login. Returns user or nil. Always spends the same time on hashing.
function users.authenticate(db, login, password)
  local user = login and login ~= "" and users.find_by_login(db, login) or nil
  if not user then
    crypto.burn_time(password)
    return nil
  end
  local ok, rehash = crypto.verify_password(password or "", user.password_hash)
  if not ok then return nil end
  if rehash then users.set_password(db, user.id, password) end
  db:run("UPDATE wc_users SET last_login_at = unixepoch() WHERE id = ?", user.id)
  return users.get(db, user.id)
end

return users
