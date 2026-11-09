-- WordCore — render admin and sign-in/setup pages inside their layouts.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local view = require("wc.platform.view")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local users = require("wc.people.users")
local http = require("wc.platform.http")
local ui = require("wc.admin.ui")

local page = {}

local ICONS = {
  dashboard = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><rect x="2" y="2" width="5" height="5" rx="1.2" stroke="currentColor" stroke-width="1.3"/><rect x="9" y="2" width="5" height="5" rx="1.2" stroke="currentColor" stroke-width="1.3"/><rect x="2" y="9" width="5" height="5" rx="1.2" stroke="currentColor" stroke-width="1.3"/><rect x="9" y="9" width="5" height="5" rx="1.2" stroke="currentColor" stroke-width="1.3"/></svg>',
  settings = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><circle cx="8" cy="8" r="2.2" stroke="currentColor" stroke-width="1.3"/><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>',
}
page.ICONS = ICONS

-- The admin menu. Addons will add items here (with a capability to check).
page.nav = {
  { id = "dashboard", label = "Dashboard", path = "/admin", icon = ICONS.dashboard, cap = "admin.access" },
  { id = "settings", label = "Settings", path = "/admin/settings", icon = ICONS.settings, cap = "settings.manage", section = "Site" },
}

-- page.admin(req, { title, subtitle, active, body, actions_html, narrow, status })
function page.admin(req, p)
  local nav = {}
  for _, item in ipairs(page.nav) do
    if users.can(req.user, item.cap) then nav[#nav + 1] = item end
  end
  local res = http.new_response(p.status or 200)
  res:html(view.render("admin/layout", {
    title = p.title, subtitle = p.subtitle, active = p.active, body = p.body,
    actions_html = p.actions_html, narrow = p.narrow,
    nav = nav, user = req.user, role_label = users.role_label(req.user.role),
    site_name = settings.get(req.db, "site.name"),
    flash_html = ui.flash(session.take_flash(req)),
    version = WORDCORE_VERSION or "dev",
  }, req))
  return res
end

-- page.auth(req, { title, body, steps, step, side_kicker, side_lead, side_foot, small })
function page.auth(req, p)
  local res = http.new_response(p.status or 200)
  res:html(view.render("auth/layout", {
    title = p.title, body = p.body, steps = p.steps, step = p.step or 1,
    side_kicker = p.side_kicker or "", side_lead = p.side_lead or "", side_foot = p.side_foot,
    small = p.small, flash_html = ui.flash(session.take_flash(req)),
  }, req))
  return res
end

return page
