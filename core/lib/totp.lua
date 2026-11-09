-- WordCore — 2-step login codes (TOTP, RFC 6238) with SHA-1/HMAC and base32.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Authenticator apps (Google Authenticator, Authy, 1Password, ...) use
-- HMAC-SHA1, 30-second steps and 6 digits, so that's what this implements.

local native = require("wc.native")

local totp = {}

---------------------------------------------------------------- SHA-1

local function lrot(x, n) return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF end

function totp.sha1(msg)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local ml = #msg * 8
  msg = msg .. "\128" .. string.rep("\0", (55 - #msg) % 64) .. string.pack(">I8", ml)
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do w[i] = string.unpack(">I4", msg, chunk + i * 4) end
    for i = 16, 79 do w[i] = lrot(w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16], 1) end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then f, k = (b & c) | ((~b) & d), 0x5A827999
      elseif i < 40 then f, k = b ~ c ~ d, 0x6ED9EBA1
      elseif i < 60 then f, k = (b & c) | (b & d) | (c & d), 0x8F1BBCDC
      else f, k = b ~ c ~ d, 0xCA62C1D6 end
      local temp = (lrot(a, 5) + (f & 0xFFFFFFFF) + e + k + w[i]) & 0xFFFFFFFF
      e, d, c, b, a = d, c, lrot(b, 30), a, temp
    end
    h0 = (h0 + a) & 0xFFFFFFFF
    h1 = (h1 + b) & 0xFFFFFFFF
    h2 = (h2 + c) & 0xFFFFFFFF
    h3 = (h3 + d) & 0xFFFFFFFF
    h4 = (h4 + e) & 0xFFFFFFFF
  end
  return string.pack(">I4I4I4I4I4", h0, h1, h2, h3, h4)
end

function totp.hmac_sha1(key, msg)
  if #key > 64 then key = totp.sha1(key) end
  key = key .. string.rep("\0", 64 - #key)
  local ipad = key:gsub(".", function(c) return string.char(c:byte() ~ 0x36) end)
  local opad = key:gsub(".", function(c) return string.char(c:byte() ~ 0x5C) end)
  return totp.sha1(opad .. totp.sha1(ipad .. msg))
end

---------------------------------------------------------------- base32 (RFC 4648)

local B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

function totp.base32_encode(s)
  local out, bits, value = {}, 0, 0
  for i = 1, #s do
    value = (value << 8) | s:byte(i)
    bits = bits + 8
    while bits >= 5 do
      bits = bits - 5
      local idx = (value >> bits) & 31
      out[#out + 1] = B32:sub(idx + 1, idx + 1)
    end
  end
  if bits > 0 then
    local idx = (value << (5 - bits)) & 31
    out[#out + 1] = B32:sub(idx + 1, idx + 1)
  end
  return table.concat(out)
end

function totp.base32_decode(s)
  s = s:upper():gsub("[%s=%-]", "")
  local out, bits, value = {}, 0, 0
  for i = 1, #s do
    local idx = B32:find(s:sub(i, i), 1, true)
    if not idx then return nil end
    value = ((value << 5) | (idx - 1)) & 0xFFFF
    bits = bits + 5
    if bits >= 8 then
      bits = bits - 8
      out[#out + 1] = string.char((value >> bits) & 255)
    end
  end
  return table.concat(out)
end

---------------------------------------------------------------- TOTP

totp.STEP = 30
totp.DIGITS = 6

function totp.new_secret()
  return totp.base32_encode(native.random_bytes(20))
end

-- HOTP value for a counter (RFC 4226).
function totp.hotp(secret_bytes, counter)
  local mac = totp.hmac_sha1(secret_bytes, string.pack(">I8", counter))
  local offset = (mac:byte(20) & 0x0F) + 1
  local bin = ((mac:byte(offset) & 0x7F) << 24) | (mac:byte(offset + 1) << 16) | (mac:byte(offset + 2) << 8) | mac:byte(offset + 3)
  return ("%0" .. totp.DIGITS .. "d"):format(bin % math.tointeger(10 ^ totp.DIGITS))
end

function totp.code(secret_b32, t)
  local key = totp.base32_decode(secret_b32)
  return totp.hotp(key, (t or os.time()) // totp.STEP)
end

-- Check a code, allowing one step of clock drift either way.
-- Returns the matched step (to block reuse), or nil.
function totp.verify(secret_b32, code, last_step, t)
  code = (code or ""):gsub("%s", "")
  if not code:match("^%d%d%d%d%d%d$") then return nil end
  local key = totp.base32_decode(secret_b32)
  if not key then return nil end
  local now = (t or os.time()) // totp.STEP
  for _, step in ipairs({ now, now - 1, now + 1 }) do
    if (not last_step or step > last_step) and totp.hotp(key, step) == code then return step end
  end
  return nil
end

function totp.uri(secret_b32, account, issuer)
  local function enc(s) return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end)) end
  return ("otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30"):format(
    enc(issuer), enc(account), secret_b32, enc(issuer))
end

return totp
