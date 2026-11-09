-- WordCore — HTML templates (etlua) with a safe, explicit set of helpers.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Templates live in core/views/*.etlua. <%= x %> escapes, <%- x %> doesn't.
-- Templates see only what they're given plus the helpers below — never _G.

local etlua = require("wc.vendor.etlua")
local files = require("wc.platform.files")
local html = require("wc.lib.html")

local view = {}
local cache = {}

local function compile(name)
  if cache[name] and not files.dev then return cache[name] end
  local src = files.read("views/" .. name .. ".etlua")
  if not src then error("missing view: " .. name, 2) end
  local fn, err = etlua.compile(src)
  if not fn then error("view " .. name .. ": " .. tostring(err), 2) end
  cache[name] = fn
  return fn
end

-- Safe standard functions templates may use.
local BASE = {
  ipairs = ipairs, pairs = pairs, tostring = tostring, tonumber = tonumber, type = type,
  select = select, next = next, math = math, string = string, table = { concat = table.concat, unpack = table.unpack },
  os = { date = os.date, time = os.time },
  h = html.escape,
}

-- render(name, params, req) -> string
function view.render(name, params, req)
  local helpers = setmetatable({}, { __index = BASE })
  if req then
    helpers.url = function(p) return req:url_for(p) end
    helpers.asset = function(p) return req:url_for("/_wc/assets/" .. p) .. "?v=" .. (WORDCORE_VERSION or "dev"):gsub("[^%w%.%-]", "-") end
    helpers.csrf = req.session and req.session.csrf or ""
    helpers.csrf_field = function()
      return '<input type="hidden" name="_csrf" value="' .. html.escape(helpers.csrf) .. '">'
    end
    helpers.req = req
  end
  helpers.partial = function(pname, pparams)
    return view.render(pname, setmetatable(pparams or {}, { __index = params }), req)
  end
  local env = setmetatable(params or {}, { __index = helpers })
  return compile(name)(env)
end

return view
