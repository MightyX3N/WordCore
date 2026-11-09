-- WordCore — themes: one package styles every page of the site.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- A theme is a folder:
--   theme.json                id, name, version, description, layouts, settings
--   templates/layout.etlua    the HTML shell around every page
--   templates/page.etlua      a content page
--   templates/404.etlua       not found
--   templates/message.etlua   simple pages (sign-in forms, notices) built by the core and addons
--   templates/partials/*.etlua
--   assets/...                CSS, images, fonts — served at /_wc/theme/<id>/...
--
-- Built-in themes live inside the program (core/themes/<id>); installed ones
-- in site/themes/<id>. Templates are sandboxed: they only see the variables
-- and helpers passed in, never Lua's globals.

local etlua = require("wc.vendor.etlua")
local native = require("wc.native")
local json = require("wc.lib.json")
local html = require("wc.lib.html")
local path = require("wc.lib.path")
local files = require("wc.platform.files")
local http = require("wc.platform.http")
local settings = require("wc.platform.settings")

local engine = {}

engine.BUILTIN = { "quiet" }
engine.DEFAULT = "quiet"

local cache = {}

local function valid_id(id) return type(id) == "string" and id:match("^[a-z0-9][a-z0-9%-]*$") ~= nil and #id <= 40 end

local function reader(site, id)
  for _, b in ipairs(engine.BUILTIN) do
    if b == id then
      return function(rel) return files.read("themes/" .. id .. "/" .. rel) end, "built-in"
    end
  end
  local root = path.join(site.dir, "themes", id)
  if path.is_dir(root) then
    return function(rel)
      if rel:find("%.%.") then return nil end
      return path.read(path.join(root, rel))
    end, "installed"
  end
  return nil
end

-- Load a theme's metadata. Returns theme or nil.
function engine.load(site, id)
  if not valid_id(id) then return nil end
  local read, source = reader(site, id)
  if not read then return nil end
  local raw = read("theme.json")
  if not raw then return nil end
  local meta = json.decode(raw)
  if type(meta) ~= "table" then return nil end
  return { id = id, meta = meta, source = source, read = read }
end

function engine.list(site)
  local out = {}
  for _, id in ipairs(engine.BUILTIN) do
    local t = engine.load(site, id)
    if t then out[#out + 1] = t end
  end
  local root = path.join(site.dir, "themes")
  if path.is_dir(root) then
    for _, name in ipairs(native.listdir(root) or {}) do
      local t = valid_id(name) and engine.load(site, name)
      if t and t.source == "installed" then out[#out + 1] = t end
    end
  end
  return out
end

function engine.active(req)
  if req._theme then return req._theme end
  local id = settings.get(req.db, "theme.active", engine.DEFAULT)
  local t = engine.load(req.site, id) or engine.load(req.site, engine.DEFAULT)
  req._theme = t
  return t
end

-- Current settings values for a theme (defaults filled in).
function engine.settings(db, theme)
  local saved = settings.get(db, "theme." .. theme.id, {})
  if type(saved) ~= "table" then saved = {} end
  local out = {}
  for _, s in ipairs(theme.meta.settings or {}) do
    local v = saved[s.key]
    if v == nil then v = s.default end
    -- never let a bad value reach CSS or markup
    if s.type == "color" and not (type(v) == "string" and v:match("^#%x%x%x%x%x%x$")) then v = s.default end
    if s.type == "select" then
      local okv = false
      for _, o in ipairs(s.options or {}) do if o[1] == v then okv = true end end
      if not okv then v = s.default end
    end
    if s.type == "checkbox" then v = v == true end
    out[s.key] = v
  end
  return out
end

function engine.clear_cache() cache = {} end

local function compile(theme, name)
  local key = theme.id .. ":" .. name
  if cache[key] and not files.dev then return cache[key] end
  local src = theme.read("templates/" .. name .. ".etlua")
  if not src then return nil end
  local fn, err = etlua.compile(src)
  if not fn then error(("theme %s, template %s: %s"):format(theme.id, name, tostring(err)), 0) end
  cache[key] = fn
  return fn
end

local SAFE = {
  ipairs = ipairs, pairs = pairs, tostring = tostring, tonumber = tonumber, type = type, select = select, next = next,
  math = { floor = math.floor, ceil = math.ceil, min = math.min, max = math.max, abs = math.abs },
  string = { format = string.format, sub = string.sub, upper = string.upper, lower = string.lower, len = string.len,
             rep = string.rep, find = string.find, match = string.match, gsub = string.gsub, gmatch = string.gmatch },
  table = { concat = table.concat },
  os = { date = os.date, time = os.time },
}

-- Render a theme template with vars. Returns html.
function engine.render(req, theme, name, vars)
  local fn = compile(theme, name)
  if not fn then
    if theme.id ~= engine.DEFAULT then
      local fallback = engine.load(req.site, engine.DEFAULT)
      return engine.render(req, fallback, name, vars)
    end
    error("theme template missing: " .. name, 0)
  end
  local helpers = setmetatable({
    h = html.escape,
    url = function(p) return req:url_for(p) end,
    asset = function(p) return req:url_for("/_wc/theme/" .. theme.id .. "/" .. p) .. "?v=" .. (theme.meta.version or "1") end,
    core_asset = function(p) return req:url_for("/_wc/assets/" .. p) .. "?v=" .. (WORDCORE_VERSION or "dev"):gsub("[^%w%.%-]", "-") end,
    partial = function(pname, pvars)
      return engine.render(req, theme, "partials/" .. pname, setmetatable(pvars or {}, { __index = vars }))
    end,
  }, { __index = SAFE })
  return fn(setmetatable(vars, { __index = helpers }))
end

-- Common variables every template gets.
function engine.base_vars(req, theme, extra)
  local menus = require("wc.content.menus")
  local users = require("wc.people.users")
  local current = extra and extra.current_path
  local v = {
    site = {
      name = settings.get(req.db, "site.name"), tagline = settings.get(req.db, "site.tagline"),
      language = settings.get(req.db, "site.language"), url = req:url_for("/"),
    },
    menus = { main = menus.for_theme(req.db, "main", req, current), footer = menus.for_theme(req.db, "footer", req, current) },
    theme = engine.settings(req.db, theme),
    user = req.user and {
      name = req.user.display_name ~= "" and req.user.display_name or req.user.username,
      is_staff = users.can(req.user, "admin.access"),
    } or nil,
    account_url = req:url_for("/account"),
    year = os.date("%Y"),
    body_class = "",
    head_extra = "",
  }
  for k, val in pairs(extra or {}) do v[k] = val end
  return v
end

-- Render a full page: inner template wrapped in the layout.
-- opts: { template = "page", title, vars = {...}, status, current_path, layout }
function engine.page(req, opts)
  local theme = engine.active(req)
  local vars = engine.base_vars(req, theme, opts.vars or {})
  vars.title = opts.title
  vars.current_path = opts.current_path
  vars.layout = opts.layout or "default"
  vars.body_class = "layout-" .. vars.layout .. (vars.body_class ~= "" and (" " .. vars.body_class) or "")
  vars.content = engine.render(req, theme, opts.template or "page", vars)
  local res = http.new_response(opts.status or 200)
  res:html(engine.render(req, theme, "layout", vars))
  return res
end

-- Simple themed page around core-built HTML (forms, notices).
function engine.message(req, title, body_html, status)
  return engine.page(req, { template = "message", title = title, status = status, vars = { body = body_html } })
end

-- GET /_wc/theme/<id>/<path>
function engine.serve_asset(req, id, rel)
  local theme = engine.load(req.site, id)
  if not theme or not rel or rel:find("%.%.") or not rel:match("^assets/[%w%-_/%.]+$") then
    return http.error_page(404, "No such file.")
  end
  local data = theme.read(rel)
  if not data then return http.error_page(404, "No such file.") end
  local types = { css = "text/css; charset=utf-8", js = "text/javascript; charset=utf-8", woff2 = "font/woff2",
                  png = "image/png", jpg = "image/jpeg", svg = "image/svg+xml", webp = "image/webp", ico = "image/x-icon" }
  local res = http.new_response(200)
  res:set_header("Content-Type", types[rel:match("%.(%w+)$") or ""] or "application/octet-stream")
  res:set_header("Cache-Control", files.dev and "no-cache" or "public, max-age=86400")
  res.body = data
  return res
end

return engine
