-- WordCore — HTTP request/response objects shared by server mode and CGI mode.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local json = require("wc.lib.json")
local html = require("wc.lib.html")

local http = {}

http.status_text = {
  [200] = "OK", [201] = "Created", [204] = "No Content",
  [301] = "Moved Permanently", [302] = "Found", [303] = "See Other", [304] = "Not Modified",
  [307] = "Temporary Redirect", [308] = "Permanent Redirect",
  [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden", [404] = "Not Found",
  [405] = "Method Not Allowed", [408] = "Request Timeout", [411] = "Length Required",
  [413] = "Content Too Large", [414] = "URI Too Long", [429] = "Too Many Requests",
  [431] = "Request Header Fields Too Large",
  [500] = "Internal Server Error", [501] = "Not Implemented", [503] = "Service Unavailable",
}

http.MAX_HEADER_BYTES = 32 * 1024
http.MAX_BODY_BYTES = 16 * 1024 * 1024

---------------------------------------------------------------- decoding

function http.url_decode(s)
  s = s:gsub("+", " ")
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Decode a path without turning "+" into a space (that rule is for query strings).
function http.path_decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function http.url_encode(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- "a=1&b=2&b=3" -> { a = "1", b = "3" }, plus a list of all pairs in order.
function http.parse_query(qs)
  local map, list = {}, {}
  if not qs or qs == "" then return map, list end
  for pair in qs:gmatch("[^&;]+") do
    local k, v = pair:match("^([^=]*)=?(.*)$")
    k, v = http.url_decode(k), http.url_decode(v)
    if k ~= "" then
      map[k] = v
      list[#list + 1] = { k, v }
    end
  end
  return map, list
end

-- Normalise a request path: decode, collapse "//", resolve "." and "..",
-- never climb above "/".
function http.clean_path(p)
  p = http.path_decode(p or "/")
  if p:find("%z") then return nil end
  local out = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then
      out[#out] = nil
    elseif seg ~= "." then
      out[#out + 1] = seg
    end
  end
  local cleaned = "/" .. table.concat(out, "/")
  if p:sub(-1) == "/" and cleaned ~= "/" then cleaned = cleaned .. "/" end
  return cleaned
end

---------------------------------------------------------------- request

local Request = {}
Request.__index = Request

-- fields: method, target (raw path+query), headers (lower-case keys), body,
-- remote_addr, mode ("server" | "cgi"), plus address info added by address.lua
function http.new_request(fields)
  local req = setmetatable(fields, Request)
  local raw_path, qs = (req.target or "/"):match("^([^?#]*)%??([^#]*)")
  req.raw_path = raw_path ~= "" and raw_path or "/"
  req.query_string = qs or ""
  req.query = http.parse_query(req.query_string)
  req.headers = req.headers or {}
  req.body = req.body or ""
  return req
end

function Request:header(name)
  return self.headers[name:lower()]
end

-- Form fields from an application/x-www-form-urlencoded body.
function Request:form()
  if self._form then return self._form end
  local ct = self:header("content-type") or ""
  if ct:lower():find("application/x-www-form-urlencoded", 1, true) then
    self._form = http.parse_query(self.body)
  else
    self._form = {}
  end
  return self._form
end

-- Build a URL inside this site, respecting the base path (subfolder installs).
function Request:url_for(p)
  p = p or "/"
  if p:sub(1, 1) ~= "/" then p = "/" .. p end
  local base = self.base_path or ""
  return base .. p
end

---------------------------------------------------------------- response

local Response = {}
Response.__index = Response

function http.new_response(status)
  return setmetatable({ status = status or 200, headers = {}, header_order = {}, body = "" }, Response)
end

function Response:set_header(name, value)
  local key = name:lower()
  if self.headers[key] == nil then
    self.header_order[#self.header_order + 1] = { key, name }
  end
  self.headers[key] = value
  return self
end

function Response:html(body, status)
  if status then self.status = status end
  self:set_header("Content-Type", "text/html; charset=utf-8")
  self.body = body
  return self
end

function Response:text(body, status)
  if status then self.status = status end
  self:set_header("Content-Type", "text/plain; charset=utf-8")
  self.body = body
  return self
end

function Response:json(value, status)
  if status then self.status = status end
  self:set_header("Content-Type", "application/json; charset=utf-8")
  self.body = json.encode(value, { pretty = true }) .. "\n"
  return self
end

function Response:redirect(location, status)
  self.status = status or 303
  self:set_header("Location", location)
  self.body = ""
  return self
end

-- Headers every response gets unless the handler set its own.
function Response:apply_defaults()
  local defaults = {
    { "Content-Type", "text/plain; charset=utf-8" },
    { "X-Content-Type-Options", "nosniff" },
    { "Referrer-Policy", "strict-origin-when-cross-origin" },
    { "X-Frame-Options", "SAMEORIGIN" },
  }
  for _, h in ipairs(defaults) do
    if self.headers[h[1]:lower()] == nil then self:set_header(h[1], h[2]) end
  end
end

-- Iterate headers in the order they were set: for name, value in res:each_header()
function Response:each_header()
  local i = 0
  return function()
    i = i + 1
    local entry = self.header_order[i]
    if entry then return entry[2], self.headers[entry[1]] end
  end
end

---------------------------------------------------------------- error pages

function http.error_page(status, detail)
  local title = ("%d %s"):format(status, http.status_text[status] or "Error")
  local res = http.new_response(status)
  res:html(([[<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<style>body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;background:#F6F6F3;color:#17171A;display:flex;min-height:100vh;align-items:center;justify-content:center}
main{max-width:520px;padding:32px}h1{font-size:28px;margin:0 0 8px}p{color:#4A4A50;line-height:1.6;margin:0}</style>
</head><body><main><h1>%s</h1><p>%s</p></main></body></html>
]]):format(html.escape(title), html.escape(title), html.escape(detail or "")))
  return res
end

return http
