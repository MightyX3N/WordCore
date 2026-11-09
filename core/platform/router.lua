-- WordCore — URL router.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
--   local r = router.new()
--   r:get("/admin/users/:id", handler, { name = "admin.user", auth = "admin.access" })
--   r:post("/admin/users/:id", handler)
--   local route, params, allowed = r:match("GET", "/admin/users/7")
--   r:url("admin.user", { id = 7 })  -> "/admin/users/7"
--
-- Patterns: literal segments, ":name" (one segment), and "*rest" as the last segment.

local http = require("wc.platform.http")

local router = {}
local Router = {}
Router.__index = Router

function router.new()
  return setmetatable({ routes = {}, by_name = {} }, Router)
end

local function compile(pattern)
  local segs = {}
  for seg in pattern:gmatch("[^/]+") do
    local kind, name = "lit", seg
    if seg:sub(1, 1) == ":" then kind, name = "param", seg:sub(2)
    elseif seg:sub(1, 1) == "*" then kind, name = "rest", seg:sub(2) end
    segs[#segs + 1] = { kind = kind, name = name }
  end
  return segs
end

function Router:add(method, pattern, handler, opts)
  opts = opts or {}
  local route = {
    method = method, pattern = pattern, segs = compile(pattern), handler = handler,
    name = opts.name, auth = opts.auth, csrf = opts.csrf ~= false, opts = opts,
  }
  self.routes[#self.routes + 1] = route
  if route.name then self.by_name[route.name] = route end
  return route
end

function Router:get(p, h, o) return self:add("GET", p, h, o) end
function Router:post(p, h, o) return self:add("POST", p, h, o) end

local function try(route, parts)
  local params = {}
  local segs = route.segs
  for i, seg in ipairs(segs) do
    if seg.kind == "rest" then
      params[seg.name] = table.concat(parts, "/", i)
      return params
    end
    local part = parts[i]
    if part == nil then return nil end
    if seg.kind == "lit" then
      if part ~= seg.name then return nil end
    else
      params[seg.name] = part
    end
  end
  if #parts ~= #segs then return nil end
  return params
end

-- Returns route, params  |  nil, nil, allowed_methods (path exists, wrong method)  |  nil
function Router:match(method, path)
  local parts = {}
  for seg in path:gmatch("[^/]+") do parts[#parts + 1] = seg end
  local allowed = {}
  for _, route in ipairs(self.routes) do
    local params = try(route, parts)
    if params then
      if route.method == method or (method == "HEAD" and route.method == "GET") then
        return route, params
      end
      allowed[#allowed + 1] = route.method
    end
  end
  if #allowed > 0 then return nil, nil, allowed end
  return nil
end

-- Build the path for a named route (without base path).
function Router:url(name, params)
  local route = self.by_name[name]
  if not route then error("no route named '" .. tostring(name) .. "'", 2) end
  local out = {}
  for _, seg in ipairs(route.segs) do
    if seg.kind == "lit" then
      out[#out + 1] = seg.name
    else
      local v = params and params[seg.name]
      if v == nil then error("missing '" .. seg.name .. "' for route " .. name, 2) end
      out[#out + 1] = seg.kind == "rest" and tostring(v) or http.url_encode(tostring(v))
    end
  end
  return "/" .. table.concat(out, "/")
end

return router
