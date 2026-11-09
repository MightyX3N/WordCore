-- WordCore — turn a request into a response (shared by every run mode).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Order of work for each request:
--   built-in assets → session → first-run gate → route → sign-in / capability
--   check → CSRF check (POST) → handler → save session → security headers.

local http = require("wc.platform.http")
local router = require("wc.platform.router")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local assets = require("wc.platform.assets")
local users = require("wc.people.users")

local app = {}

local routes = router.new()
require("wc.setup.wizard").register(routes)
require("wc.admin.auth").register(routes)
require("wc.admin.dashboard").register(routes)
require("wc.admin.settings").register(routes)
require("wc.admin.account").register(routes)

-- Phase 0 host check stays available for diagnosing a host.
local hello = require("wc.app.hello")
routes:get("/_wc/health", function(req) req.path = "/health" return hello(req, req.app_ctx) end)
routes:get("/_wc/hostcheck", function(req) req.path = "/" return hello(req, req.app_ctx) end, { auth = "settings.manage" })

require("wc.admin.pages").register(routes)
require("wc.admin.media").register(routes)
require("wc.admin.menus").register(routes)
require("wc.admin.themes").register(routes)
require("wc.admin.users").register(routes)

local front = require("wc.content.front")
front.register(routes)
require("wc.people.accounts").register(routes)
-- The public pages (and the catch-all "/*path") must come last.
front.register_pages(routes)

app.routes = routes

local ADMIN_CSP = table.concat({
  "default-src 'self'", "img-src 'self' data:", "style-src 'self'", "script-src 'self'", "font-src 'self'",
  "connect-src 'self'", "form-action 'self'", "frame-ancestors 'none'", "base-uri 'none'", "object-src 'none'",
}, "; ")

local function is_private(path)
  return path == "/setup" or path:sub(1, 7) == "/setup/" or path == "/admin" or path:sub(1, 7) == "/admin/"
end

local function dispatch(req)
  local static = assets.handle(req)
  if static then return static end

  local db = req.db
  if math.random(1, 100) == 1 then
    session.cleanup(db)
    require("wc.platform.ratelimit").cleanup(db)
  end
  session.load(req, db, req.site.id, users)

  -- First run: nothing but the setup wizard until an owner exists.
  local has_owner = users.has_owner(db)
  local in_setup = req.path == "/setup" or req.path:sub(1, 7) == "/setup/"
  if not has_owner and not in_setup and req.path ~= "/_wc/health" and req.path:sub(1, 10) ~= "/_wc/theme" then
    return http.new_response():redirect(req:url_for("/setup"))
  end
  if has_owner and in_setup then
    return http.new_response():redirect(req:url_for("/admin"))
  end

  local route, params, allowed = routes:match(req.method, req.path)
  if route and route.opts and route.opts.catch_all then
    -- "/admin/logout" is POST only: say so instead of showing a page-not-found
    local other = routes:match("POST", req.path)
    if other and not (other.opts and other.opts.catch_all) then
      return http.error_page(405, "That action isn't allowed here."):set_header("Allow", "POST")
    end
  end
  if not route then
    if allowed then
      return http.error_page(405, "That action isn't allowed here."):set_header("Allow", table.concat(allowed, ", "))
    end
    return http.error_page(404, "There's nothing at " .. req.path .. ".")
  end

  if route.auth then
    if not req.user then
      local nxt = req.method == "GET" and req.path ~= "/admin" and ("?next=" .. http.url_encode(req.path)) or ""
      return http.new_response():redirect(req:url_for("/admin/login" .. nxt))
    end
    if not users.can(req.user, route.auth) then
      return http.error_page(403, "Your account doesn't have access to this page.")
    end
  end

  if req.method == "POST" and route.csrf then
    local ok = session.check_csrf(req)
    if not ok then
      return http.error_page(403, "This form expired or came from somewhere else. Go back, reload the page and try again.")
    end
  end

  return route.handler(req, params)
end

-- ctx: { site, mode, version }
function app.handle(req, ctx)
  req.site = ctx.site
  req.db = ctx.site.db
  req.app_ctx = ctx
  local ok, res = xpcall(dispatch, debug.traceback, req)
  if not ok then
    io.stderr:write("wordcore: error handling ", req.method or "?", " ", req.raw_path or "?", "\n", tostring(res), "\n")
    res = http.error_page(500, "Something went wrong while building this page. The details are in the server log.")
  elseif type(res) ~= "table" or getmetatable(res) == nil then
    io.stderr:write("wordcore: handler returned no response for ", req.raw_path or "?", "\n")
    res = http.error_page(500, "This page didn't produce a response.")
  end
  pcall(session.save, req, req.db)
  session.apply(req, res)
  if is_private(req.path or "") then
    res:set_header("Content-Security-Policy", ADMIN_CSP)
    res:set_header("X-Robots-Tag", "noindex, nofollow")
    if not res.headers["cache-control"] then res:set_header("Cache-Control", "no-store") end
  end
  res:apply_defaults()
  if req.method == "HEAD" then res.head_only = true end
  return res
end

return app
