-- WordCore — base64 (standard and URL-safe, no padding for URL-safe).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local base64 = {}

local STD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local function make_decode(alpha)
  local map = {}
  for i = 1, 64 do map[alpha:byte(i)] = i - 1 end
  return map
end
local DEC_STD, DEC_URL = make_decode(STD), make_decode(URL)

local function encode(s, alpha, pad)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = (n >> 18) & 63
    local c2 = (n >> 12) & 63
    local c3 = (n >> 6) & 63
    local c4 = n & 63
    out[#out + 1] = alpha:sub(c1 + 1, c1 + 1) .. alpha:sub(c2 + 1, c2 + 1)
      .. (b and alpha:sub(c3 + 1, c3 + 1) or (pad and "=" or ""))
      .. (c and alpha:sub(c4 + 1, c4 + 1) or (pad and "=" or ""))
  end
  return table.concat(out)
end

local function decode(s, map)
  s = s:gsub("=+$", "")
  local out = {}
  local bits, nbits = 0, 0
  for i = 1, #s do
    local v = map[s:byte(i)]
    if v == nil then return nil end
    bits = (bits << 6) | v
    nbits = nbits + 6
    if nbits >= 8 then
      nbits = nbits - 8
      out[#out + 1] = string.char((bits >> nbits) & 255)
    end
  end
  return table.concat(out)
end

function base64.encode(s) return encode(s, STD, true) end
function base64.decode(s) return decode(s, DEC_STD) end
-- PHC strings use standard alphabet without padding
function base64.encode_nopad(s) return encode(s, STD, false) end
function base64.url_encode(s) return encode(s, URL, false) end
function base64.url_decode(s) return decode(s, DEC_URL) end

return base64
