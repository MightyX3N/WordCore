-- WordCore — declarative settings screens (part of the admin UI kit).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Describe the fields; get a page that loads, validates and saves them:
--
--   settings_page.register(router, {
--     path = "/admin/settings", id = "settings", title = "Settings", cap = "settings.manage",
--     sections = { { title = "Site", fields = {
--       { key = "site.name", label = "Site name", type = "text", required = true, max = 80 },
--       { key = "site.language", label = "Language", type = "select", options = {...} },
--       { key = "proxy.trust", label = "Trust proxy headers", type = "checkbox" },
--       { key = "repo.urls", label = "Repositories", type = "url_list" },
--     }}},
--     validate = function(values, errors) ... end,   -- optional extra checks
--   })

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local log = require("wc.platform.log")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local settings_page = {}

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function valid_https(u) return u:match("^https://[%w%.%-]+[%w]") ~= nil and not u:find("[%s<>\"']") and #u <= 300 end

-- Turn submitted form text into a typed value, or return an error message.
local function options_of(field, req)
  if type(field.options) == "function" then return field.options(req) end
  return field.options
end

local function parse(field, raw, req)
  local t = field.type or "text"
  if t == "checkbox" then return raw == "1" end
  raw = trim(raw)
  if t == "url_list" then
    local list = {}
    for raw_line in raw:gmatch("[^\r\n]+") do
      local line = trim(raw_line)
      if line ~= "" then
        if not valid_https(line) then return nil, "Each line must be an https:// address." end
        list[#list + 1] = line
      end
    end
    if field.required and #list == 0 then return nil, "Add at least one." end
    return list
  end
  if field.required and raw == "" then return nil, field.required_text or "This can't be empty." end
  if field.max and #raw > field.max then return nil, ("Use at most %d characters."):format(field.max) end
  if t == "select" then
    for _, o in ipairs(options_of(field, req)) do
      if tostring(o[1]) == raw then return field.number and tonumber(raw) or raw end
    end
    return nil, "Choose an option from the list."
  end
  if t == "url" and raw ~= "" and not valid_https(raw) then return nil, "Enter an https:// address." end
  return raw
end

local function to_form_value(field, v)
  if field.type == "url_list" then return table.concat(type(v) == "table" and v or {}, "\n") end
  return v
end

local function render(req, spec, values, errors)
  local sections = {}
  for _, sec in ipairs(spec.sections) do
    local fields = {}
    for _, f in ipairs(sec.fields) do
      fields[#fields + 1] = {
        name = f.key, label = f.label, hint = f.hint, required = f.required, max = f.max, mono = f.mono or f.type == "url_list",
        type = f.type == "url_list" and "textarea" or f.type, options = options_of(f, req), rows = f.rows,
        value = to_form_value(f, values[f.key]), error = errors[f.key], optional = f.optional,
      }
    end
    sections[#sections + 1] = { title = sec.title, intro = sec.intro, fields = fields, id = sec.id }
  end
  local body = ui.form({ action = req:url_for(spec.path), csrf = req.session.csrf, sections = sections, submit = spec.submit or "Save changes" })
  local res = page.admin(req, { title = spec.title, subtitle = spec.subtitle, active = spec.id, body = body, narrow = true })
  if next(errors) then res.status = 422 end
  return res
end

function settings_page.register(r, spec)
  local function all_fields()
    local list = {}
    for _, sec in ipairs(spec.sections) do for _, f in ipairs(sec.fields) do list[#list + 1] = f end end
    return list
  end

  r:get(spec.path, function(req)
    local values = {}
    for _, f in ipairs(all_fields()) do values[f.key] = settings.get(req.db, f.key) end
    return render(req, spec, values, {})
  end, { name = spec.id, auth = spec.cap })

  r:post(spec.path, function(req)
    local form = req:form()
    local values, errors = {}, {}
    for _, f in ipairs(all_fields()) do
      local v, err
      if form[f.key] == nil and f.type ~= "checkbox" then
        v = settings.get(req.db, f.key)   -- not part of this submit: keep it
      else
        v, err = parse(f, form[f.key], req)
      end
      if err then errors[f.key] = err; values[f.key] = form[f.key] else values[f.key] = v end
    end
    if spec.validate then spec.validate(values, errors, req) end
    if next(errors) then
      -- show what was typed, not the parsed values
      for _, f in ipairs(all_fields()) do
        if f.type == "url_list" and errors[f.key] then values[f.key] = nil end
      end
      return render(req, spec, values, errors)
    end
    local changed = {}
    for _, f in ipairs(all_fields()) do
      local old = settings.get(req.db, f.key)
      local new = values[f.key]
      local same = type(old) == "table" and type(new) == "table" and table.concat(old, "\n") == table.concat(new, "\n") or old == new
      if not same then changed[#changed + 1] = f.label end
    end
    local save = {}
    for _, f in ipairs(all_fields()) do save[f.key] = values[f.key] end
    settings.set_many(req.db, save)
    if #changed > 0 then
      log.add(req.db, req, "settings.saved", table.concat(changed, ", "))
      session.flash(req, "ok", "Saved.")
    else
      session.flash(req, "info", "Nothing changed.")
    end
    return http.new_response():redirect(req:url_for(spec.path))
  end, { auth = spec.cap })
end

return settings_page
