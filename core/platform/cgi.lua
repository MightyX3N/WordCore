-- WordCore — CGI mode: handle exactly one request from a web server, then exit.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Used on shared hosting: .htaccess sends every request to the program, the
-- web server passes the request in environment variables + stdin, and we
-- write the response to stdout.

local native = require("wc.native")
local http = require("wc.platform.http")
local address = require("wc.platform.address")
local site_mod = require("wc.platform.site")
local app = require("wc.platform.app")
local path = require("wc.lib.path")

local SITE_HTACCESS = [[
# WordCore — this folder holds the site's database and settings. Never serve it.
<IfModule mod_authz_core.c>
  Require all denied
</IfModule>
<IfModule !mod_authz_core.c>
  Order allow,deny
  Deny from all
</IfModule>
]]

local cgi = {}

local function write_response(res)
  local out = { ("Status: %d %s\r\n"):format(res.status, http.status_text[res.status] or "") }
  local body = res.head_only and "" or (res.body or "")
  local has_length = false
  for name, value in res:each_header() do
    if name:lower() == "content-length" then has_length = true end
    out[#out + 1] = name .. ": " .. tostring(value) .. "\r\n"
  end
  if not has_length then out[#out + 1] = "Content-Length: " .. #(res.body or "") .. "\r\n" end
  out[#out + 1] = "\r\n"
  out[#out + 1] = body
  io.stdout:write(table.concat(out))
  io.stdout:flush()
end

function cgi.run(opts)
  native.stdio_binary()
  local env = native.environ()

  local headers = {}
  for k, v in pairs(env) do
    local name = k:match("^HTTP_(.+)$")
    if name then headers[name:lower():gsub("_", "-")] = v end
  end
  if env.CONTENT_TYPE then headers["content-type"] = env.CONTENT_TYPE end
  if env.CONTENT_LENGTH then headers["content-length"] = env.CONTENT_LENGTH end

  local length = tonumber(env.CONTENT_LENGTH or "0") or 0
  if length > http.MAX_BODY_BYTES then
    local res = http.error_page(413, "The request is too large.")
    res:apply_defaults()
    write_response(res)
    return 0
  end
  local body = ""
  if length > 0 then body = io.stdin:read(length) or "" end

  local target = env.REQUEST_URI
  if not target or target == "" then
    target = (env.SCRIPT_NAME or "") .. (env.PATH_INFO or "")
    if env.QUERY_STRING and env.QUERY_STRING ~= "" then target = target .. "?" .. env.QUERY_STRING end
  end

  local req = http.new_request({
    method = (env.REQUEST_METHOD or "GET"):upper(),
    target = target,
    headers = headers,
    body = body,
    mode = "cgi",
  })

  local site, err = site_mod.open(nil)
  if not site then
    io.stderr:write("wordcore: ", err, "\n")
    local res = http.error_page(500, "WordCore can't open its site folder. Check that the folder next to the program is writable.")
    res:apply_defaults()
    write_response(res)
    return 0
  end

  -- The site folder sits inside the web root on shared hosting: make sure the
  -- web server refuses to serve it, even if mod_rewrite is ever turned off.
  local guard = path.join(site.dir, ".htaccess")
  if not path.exists(guard) then
    path.write(guard, SITE_HTACCESS)
  end

  address.resolve(req, { mode = "cgi", env = env, trust_proxy = site.config.trust_proxy == true })
  local res = app.handle(req, { site = site, mode = "cgi", version = opts.version, env = env })
  write_response(res)
  site:close()
  return 0
end

return cgi
