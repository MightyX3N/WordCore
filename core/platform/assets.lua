-- WordCore — serve the core's built-in assets (admin CSS/JS, fonts) and notices.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local files = require("wc.platform.files")
local http = require("wc.platform.http")

local assets = {}

local TYPES = {
  css = "text/css; charset=utf-8", js = "text/javascript; charset=utf-8",
  woff2 = "font/woff2", svg = "image/svg+xml", png = "image/png", ico = "image/x-icon",
  txt = "text/plain; charset=utf-8", json = "application/json",
}

-- Handle /_wc/assets/<path> and /_wc/notices. Returns a response or nil.
function assets.handle(req)
  local p = req.path
  if p == "/_wc/notices" then
    local res = http.new_response(200)
    res:text(files.read("NOTICES.txt") or "")
    return res
  end
  local rel = p:match("^/_wc/assets/(.+)$")
  if not rel then return nil end
  if rel:find("%.%.") or not rel:match("^[%w%-_/%.]+$") then return http.error_page(404, "No such file.") end
  local data = files.read("assets/" .. rel)
  if not data then return http.error_page(404, "No such file.") end
  local ext = rel:match("%.(%w+)$") or ""
  local res = http.new_response(200)
  res:set_header("Content-Type", TYPES[ext] or "application/octet-stream")
  local etag = '"' .. (WORDCORE_VERSION or "dev") .. '"'
  if files.dev then
    res:set_header("Cache-Control", "no-cache")
  else
    res:set_header("Cache-Control", "public, max-age=31536000, immutable")
    res:set_header("ETag", etag)
    if req.headers["if-none-match"] == etag then
      res.status = 304
      return res
    end
  end
  res.body = data
  return res
end

return assets
