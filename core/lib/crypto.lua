-- WordCore — passwords, tokens and hashes.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local native = require("wc.native")
local raw = require("wc.crypto")
local base64 = require("wc.lib.base64")

local crypto = {}

-- Argon2id parameters (OWASP minimum: 19 MiB, 2 passes, 1 lane).
crypto.ARGON2 = { m = 19456, t = 2, p = 1 }

function crypto.hex(s)
  return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

function crypto.random(n) return native.random_bytes(n) end

-- URL-safe random token, e.g. for session cookies (32 bytes -> 43 chars).
function crypto.token(nbytes)
  return base64.url_encode(native.random_bytes(nbytes or 32))
end

function crypto.blake2b_hex(data, size, key)
  return crypto.hex(raw.blake2b(data, size or 32, key))
end

crypto.equal = raw.equal

-- Hash a password into a PHC string: $argon2id$v=19$m=..,t=..,p=..$salt$hash
function crypto.hash_password(password)
  local p = crypto.ARGON2
  local salt = native.random_bytes(16)
  local h = raw.argon2id(password, salt, p.m, p.t, p.p, 32)
  return ("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s"):format(p.m, p.t, p.p,
    base64.encode_nopad(salt), base64.encode_nopad(h))
end

-- Check a password against a PHC string. Returns ok, needs_rehash.
function crypto.verify_password(password, phc)
  if type(phc) ~= "string" then return false, false end
  local m, t, p, salt_b64, hash_b64 = phc:match("^%$argon2id%$v=19%$m=(%d+),t=(%d+),p=(%d+)%$([%w+/]+)%$([%w+/]+)$")
  if not m then return false, false end
  local salt, want = base64.decode(salt_b64), base64.decode(hash_b64)
  if not salt or not want or #salt < 8 or #want < 16 then return false, false end
  m, t, p = tonumber(m), tonumber(t), tonumber(p)
  local ok_call, got = pcall(raw.argon2id, password, salt, m, t, p, #want)
  if not ok_call then return false, false end
  local ok = raw.equal(got, want)
  local cur = crypto.ARGON2
  return ok, ok and (m ~= cur.m or t ~= cur.t or p ~= cur.p)
end

-- Run Argon2 on a dummy hash so a missing user takes as long as a wrong password.
local dummy
function crypto.burn_time(password)
  dummy = dummy or crypto.hash_password("not a real password")
  crypto.verify_password(password or "", dummy)
end

return crypto
