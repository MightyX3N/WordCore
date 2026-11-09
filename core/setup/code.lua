-- WordCore — the one-time setup code that protects a fresh install.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Until an owner account exists, anyone who can reach the site could claim it.
-- So setup needs a code that only the person with access to the files (or the
-- console window) can see. It's written to site/setup-code.txt and removed
-- when setup finishes. On your own PC the program opens the browser with the
-- code already filled in, so you never type it.

local native = require("wc.native")
local path = require("wc.lib.path")
local crypto = require("wc.lib.crypto")

local code = {}

local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" -- no 0/O/1/I

local function generate()
  local bytes = native.random_bytes(8)
  local out = {}
  for i = 1, 8 do
    local b = bytes:byte(i) % #ALPHABET + 1
    out[#out + 1] = ALPHABET:sub(b, b)
    if i == 4 then out[#out + 1] = "-" end
  end
  return table.concat(out)
end

function code.file(site) return path.join(site.dir, "setup-code.txt") end

local function normalize(s)
  return ((s or ""):upper():gsub("[^%w]", ""))
end

-- Read the current code, creating it if needed.
function code.get(site)
  local raw = path.read(code.file(site))
  local current = raw and raw:match("Setup code:%s*([%w%-]+)")
  if current then return current end
  current = generate()
  path.write(code.file(site), table.concat({
    "WordCore setup code",
    "",
    "Setup code: " .. current,
    "",
    "Enter this code on your site's setup page to create the owner account.",
    "This file is deleted automatically when setup is finished.",
    "",
  }, "\n"))
  return current
end

function code.check(site, given)
  local want = normalize(code.get(site))
  return #normalize(given) == #want and crypto.equal(normalize(given), want)
end

function code.remove(site)
  os.remove(code.file(site))
end

return code
