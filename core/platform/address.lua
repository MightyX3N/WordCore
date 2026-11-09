-- WordCore — work out the site's real address for a request.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- The same site must work at localhost:8080, through a tunnel, behind a proxy,
-- in a subfolder on shared hosting and at a real domain, without the address
-- being hardcoded anywhere. This module fills in, on the request:
--   scheme, host, base_path, path, client_ip, public_url,
--   proxy = { seen = {header names}, trusted = bool }

local http = require("wc.platform.http")

local address = {}

local PROXY_HEADERS = { "forwarded", "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host",
                        "x-forwarded-prefix", "x-forwarded-port", "x-real-ip" }

local function first_value(v)
  if not v then return nil end
  return (v:match("^%s*([^,]+)") or ""):gsub("%s+$", "")
end

local function clean_host(h)
  if not h or h == "" then return nil end
  h = h:lower()
  -- host, IPv4/IPv6 literal, optional port; nothing else
  if not h:match("^[%w%.%-]+$") and not h:match("^[%w%.%-]+:%d+$") and not h:match("^%[[%x:%.]+%]:?%d*$") then
    return nil
  end
  return h
end

local function clean_prefix(p)
  if not p or p == "" then return "" end
  p = http.clean_path(p)
  if not p or p == "/" then return "" end
  return (p:gsub("/+$", ""))
end

-- Parse RFC 7239 "Forwarded: for=1.2.3.4;proto=https;host=example.com" (first element only)
local function parse_forwarded(v)
  local out = {}
  if not v then return out end
  local first = v:match("^[^,]+") or ""
  for k, val in first:gmatch("([%w]+)%s*=%s*\"?([^;\"]*)\"?") do
    out[k:lower()] = val
  end
  return out
end

local function strip_prefix(p, prefix)
  if prefix == "" then return p end
  if p == prefix then return "/" end
  if p:sub(1, #prefix + 1) == prefix .. "/" then return p:sub(#prefix + 1) end
  return nil
end

-- ctx: { mode = "server"|"cgi", env = table (cgi), trust_proxy = bool,
--        base_path = string (server mode, optional), socket_ip = string (server) }
function address.resolve(req, ctx)
  local env = ctx.env or {}
  local scheme, host, base, client_ip
  local path = http.clean_path(req.raw_path) or "/"

  if ctx.mode == "cgi" then
    local https = (env.HTTPS or ""):lower()
    if https == "on" or https == "1" or (env.REQUEST_SCHEME or ""):lower() == "https" or env.SERVER_PORT == "443" then
      scheme = "https"
    else
      scheme = "http"
    end
    host = clean_host(env.HTTP_HOST)
    if not host and env.SERVER_NAME then
      local port = env.SERVER_PORT
      host = clean_host(env.SERVER_NAME .. ((port and port ~= "80" and port ~= "443") and (":" .. port) or ""))
    end
    client_ip = env.REMOTE_ADDR

    local script = http.clean_path(env.SCRIPT_NAME or "") or ""
    if script == "/" then script = "" end
    local rest = script ~= "" and strip_prefix(path, script)
    if rest then
      -- called directly: /folder/wordcore.cgi/some/page
      base, path = script, rest
    else
      -- called through .htaccess rewrite: the site lives in the script's folder
      base = clean_prefix(script:match("^(.*)/[^/]*$") or "")
      path = strip_prefix(path, base) or path
    end
  else
    scheme = "http"
    host = clean_host(req.headers["host"])
    client_ip = ctx.socket_ip
    base = clean_prefix(ctx.base_path or "")
    path = strip_prefix(path, base) or path
  end

  -- Proxy / tunnel headers: always reported, only used when trusted.
  local seen = {}
  for _, name in ipairs(PROXY_HEADERS) do
    if req.headers[name] then seen[#seen + 1] = name end
  end
  if ctx.trust_proxy and #seen > 0 then
    local fwd = parse_forwarded(req.headers["forwarded"])
    local proto = (fwd.proto or first_value(req.headers["x-forwarded-proto"]) or ""):lower()
    if proto == "https" or proto == "http" then scheme = proto end
    host = clean_host(fwd.host or first_value(req.headers["x-forwarded-host"])) or host
    local fport = first_value(req.headers["x-forwarded-port"])
    if fport and host and not host:find(":%d+$") and not ((scheme == "https" and fport == "443") or (scheme == "http" and fport == "80")) then
      host = host .. ":" .. fport
    end
    local prefix = req.headers["x-forwarded-prefix"]
    if prefix then
      base = clean_prefix(first_value(prefix)) .. base
    end
    local fip = fwd["for"] or first_value(req.headers["x-forwarded-for"]) or first_value(req.headers["x-real-ip"])
    if fip and fip ~= "" then client_ip = fip:gsub("^%[", ""):gsub("%]:?%d*$", "") end
  end

  host = host or "localhost"
  req.scheme = scheme
  req.host = host
  req.base_path = base
  req.path = path
  req.client_ip = client_ip or ""
  req.public_url = scheme .. "://" .. host .. base
  req.proxy = { seen = seen, trusted = ctx.trust_proxy and true or false }
  return req
end

return address
