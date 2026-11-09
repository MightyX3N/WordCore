-- WordCore — admin: themes (choose one, adjust its settings).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local log = require("wc.platform.log")
local engine = require("wc.themes.engine")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local admin_themes = {}

local function swatch(theme, values)
  local accent = values.accent or "#2456D6"
  return ('<span class="theme-swatch" aria-hidden="true"><span class="sw-bar"></span><span class="sw-line"></span><span class="sw-line short"></span><span class="sw-dot" data-accent="%s"></span></span>'):format(esc(accent))
end

local function list(req)
  local active = engine.active(req)
  local cards = {}
  for _, t in ipairs(engine.list(req.site)) do
    local is_active = t.id == active.id
    local values = engine.settings(req.db, t)
    cards[#cards + 1] = ('<li class="card theme-card%s">%s<div class="card-body"><h2>%s %s</h2><p class="small muted">%s · version %s%s</p><p>%s</p><div class="actions">%s%s</div></div></li>'):format(
      is_active and " is-active" or "", swatch(t, values), esc(t.meta.name or t.id),
      is_active and ui.badge("Active", "ok") or "",
      t.source == "built-in" and "Built in" or "Installed", esc(t.meta.version or "?"),
      t.meta.author and (" · by " .. esc(t.meta.author)) or "",
      esc(t.meta.description or ""),
      is_active and "" or ('<form method="post" action="%s">%s<button type="submit" class="btn btn-primary">Use this theme</button></form>'):format(
        esc(req:url_for("/admin/themes/" .. t.id .. "/activate")), ui.csrf(req.session.csrf)),
      (t.meta.settings and #t.meta.settings > 0) and ('<a class="btn" href="%s">Customise</a>'):format(esc(req:url_for("/admin/themes/" .. t.id))) or "")
  end
  local body = '<ul class="theme-grid">' .. table.concat(cards) .. "</ul>"
    .. '<p class="small muted">More themes will come from the addon repository. A theme styles every page, the menus and the sign-in forms visitors see.</p>'
  return page.admin(req, { title = "Themes", subtitle = "How your site looks to visitors.", active = "themes", body = body })
end

local function activate(req, params)
  local t = engine.load(req.site, params.id)
  if not t then return http.error_page(404, "That theme isn't installed.") end
  settings.set(req.db, "theme.active", t.id)
  engine.clear_cache()
  log.add(req.db, req, "themes.activated", t.meta.name or t.id)
  session.flash(req, "ok", ("%s is now your theme."):format(t.meta.name or t.id))
  return http.new_response():redirect(req:url_for("/admin/themes"))
end

local function settings_view(req, t, values, errors, status)
  local fields = {}
  for _, s in ipairs(t.meta.settings or {}) do
    local f = { name = "s." .. s.key, label = s.label, hint = s.hint, error = errors[s.key] }
    if s.type == "color" then f.type = "color" f.value = values[s.key] f.class = "color-input"
    elseif s.type == "select" then f.type = "select" f.options = s.options f.value = values[s.key]
    elseif s.type == "checkbox" then f.type = "checkbox" f.value = values[s.key] == true
    else f.type = "text" f.value = values[s.key] f.max = s.max or 200 end
    fields[#fields + 1] = f
  end
  local body = ui.form({ action = req:url_for("/admin/themes/" .. t.id), csrf = req.session.csrf, submit = "Save", sections = {
    { title = t.meta.name or t.id, intro = t.id == engine.active(req).id and "Changes show on your site straight away." or "This theme isn't active. Your choices are kept for when you switch to it.", fields = fields },
  }}) .. ('<form method="post" action="%s" data-confirm="Put every setting of this theme back to its default?">%s<button type="submit" class="btn btn-sm">Reset to defaults</button></form>'):format(
    esc(req:url_for("/admin/themes/" .. t.id .. "/reset")), ui.csrf(req.session.csrf))
  local res = page.admin(req, { title = "Customise " .. (t.meta.name or t.id), active = "themes", narrow = true, body = body,
    actions_html = ('<a class="btn" href="%s" target="_blank" rel="noopener">View site</a><a class="btn" href="%s">All themes</a>'):format(esc(req:url_for("/")), esc(req:url_for("/admin/themes"))) })
  if status then res.status = status end
  return res
end

local function get_settings(req, params)
  local t = engine.load(req.site, params.id)
  if not t then return http.error_page(404, "That theme isn't installed.") end
  return settings_view(req, t, engine.settings(req.db, t), {})
end

local function post_settings(req, params)
  local t = engine.load(req.site, params.id)
  if not t then return http.error_page(404, "That theme isn't installed.") end
  local f = req:form()
  local values, errors = {}, {}
  for _, s in ipairs(t.meta.settings or {}) do
    local raw = f["s." .. s.key]
    if s.type == "checkbox" then values[s.key] = raw == "1"
    elseif s.type == "color" then
      raw = (raw or ""):lower()
      if raw:match("^#%x%x%x%x%x%x$") then values[s.key] = raw else errors[s.key] = "Choose a colour." values[s.key] = s.default end
    elseif s.type == "select" then
      local ok = false
      for _, o in ipairs(s.options or {}) do if o[1] == raw then ok = true end end
      if ok then values[s.key] = raw else errors[s.key] = "Choose an option from the list." values[s.key] = s.default end
    else
      raw = (raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if #raw > (s.max or 200) then errors[s.key] = ("Use at most %d characters."):format(s.max or 200) end
      values[s.key] = raw
    end
  end
  if next(errors) then return settings_view(req, t, values, errors, 422) end
  settings.set(req.db, "theme." .. t.id, values)
  log.add(req.db, req, "themes.customised", t.meta.name or t.id)
  session.flash(req, "ok", "Saved.")
  return http.new_response():redirect(req:url_for("/admin/themes/" .. t.id))
end

local function reset(req, params)
  local t = engine.load(req.site, params.id)
  if not t then return http.error_page(404, "That theme isn't installed.") end
  settings.set(req.db, "theme." .. t.id, {})
  session.flash(req, "ok", "Back to the defaults.")
  return http.new_response():redirect(req:url_for("/admin/themes/" .. t.id))
end

function admin_themes.register(r)
  r:get("/admin/themes", list, { name = "themes", auth = "themes.manage" })
  r:get("/admin/themes/:id", get_settings, { auth = "themes.manage" })
  r:post("/admin/themes/:id", post_settings, { auth = "themes.manage" })
  r:post("/admin/themes/:id/activate", activate, { auth = "themes.manage" })
  r:post("/admin/themes/:id/reset", reset, { auth = "themes.manage" })
end

return admin_themes
