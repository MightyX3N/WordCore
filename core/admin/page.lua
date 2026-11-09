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
ICONS.pages = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M4 1.5h5.5L13 5v9.5H4z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M9 1.5V5.5h4M6.5 8.5h4M6.5 11h4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>'
ICONS.media = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="1.5" stroke="currentColor" stroke-width="1.3"/><circle cx="5.5" cy="6" r="1.3" stroke="currentColor" stroke-width="1.2"/><path d="M2 12l4-3.5 3 2.5 2-1.5 3 2.5" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>'
ICONS.menus = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M2.5 4h11M2.5 8h11M5.5 12h8" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>'
ICONS.themes = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M8 1.5a6.5 6.5 0 100 13c1 0 1.4-.7 1.1-1.5-.4-.9.1-2 1.2-2H12a2.5 2.5 0 002.5-2.5A6.9 6.9 0 008 1.5z" stroke="currentColor" stroke-width="1.3"/><circle cx="5" cy="7" r="1" fill="currentColor"/><circle cx="8" cy="4.6" r="1" fill="currentColor"/><circle cx="11" cy="6.5" r="1" fill="currentColor"/></svg>'
ICONS.users = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><circle cx="6" cy="5.5" r="2.5" stroke="currentColor" stroke-width="1.3"/><path d="M1.5 14c.4-2.6 2.2-4 4.5-4s4.1 1.4 4.5 4M10.5 3.2a2.5 2.5 0 010 4.6M12 10.3c1.4.5 2.3 1.8 2.5 3.7" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>'
page.ICONS = ICONS

-- The admin menu. Addons will add items here (with a capability to check).
page.nav = {
  { id = "dashboard", label = "Dashboard", path = "/admin", icon = ICONS.dashboard, cap = "admin.access" },
  { id = "pages", label = "Pages", path = "/admin/pages", icon = ICONS.pages, cap = "content.edit_own", section = "Content" },
  { id = "media", label = "Media", path = "/admin/media", icon = ICONS.media, cap = "media.upload", section = "Content" },
  { id = "menus", label = "Menus", path = "/admin/menus", icon = ICONS.menus, cap = "menus.manage", section = "Content" },
  { id = "themes", label = "Themes", path = "/admin/themes", icon = ICONS.themes, cap = "themes.manage", section = "Site" },
  { id = "users", label = "People", path = "/admin/users", icon = ICONS.users, cap = "users.manage", section = "Site" },
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
    actions_html = p.actions_html, narrow = p.narrow, wide = p.wide,
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
