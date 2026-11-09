-- WordCore — the public site: pages, media files, theme assets.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")
local settings = require("wc.platform.settings")
local users = require("wc.people.users")
local pages = require("wc.content.pages")
local media = require("wc.content.media")
local render = require("wc.content.render")
local engine = require("wc.themes.engine")

local front = {}

function front.can_edit(user, page)
  if not user then return false end
  if users.can(user, "content.edit_any") then return true end
  return users.can(user, "content.edit_own") and page and page.author_id == user.id
end

function front.not_found(req)
  local res = engine.page(req, { template = "404", title = "Page not found", status = 404, vars = { noindex = true } })
  res:set_header("Cache-Control", "no-store")
  return res
end

local function show_page(req, page, path)
  local live = pages.is_live(page)
  local editor = front.can_edit(req.user, page)
  if not live and not editor then return front.not_found(req) end
  if page.access == "members" and not req.user then
    return http.new_response():redirect(req:url_for("/account/login?next=" .. http.url_encode(path)))
  end
  local body_html = render.html(page.body, { req = req, page = page })
  local notice
  if not live then
    notice = pages.state(page) == "scheduled"
      and ("Scheduled — visitors will see this page from " .. os.date("!%Y-%m-%d %H:%M UTC", page.publish_at) .. ".")
      or "Draft — only people who can edit pages see this."
  end
  local is_home = page.id == pages.home_id(req.db)
  local res = engine.page(req, {
    template = "page", title = is_home and settings.get(req.db, "site.name") or page.title,
    layout = page.layout, current_path = is_home and "/" or path,
    vars = {
      page = { id = page.id, title = page.title, html = body_html, path = path, is_home = is_home, updated_at = page.updated_at },
      description = render.excerpt(page.body, 160),
      preview_notice = notice,
      edit_url = editor and req:url_for("/admin/pages/" .. page.id) or nil,
      noindex = not live or page.access ~= "public",
    },
  })
  if page.access ~= "public" or not live or req.user then res:set_header("Cache-Control", "no-store") end
  return res
end

local function home(req)
  local id = pages.home_id(req.db)
  local page = id ~= 0 and pages.get(req.db, id) or nil
  if page then return show_page(req, page, pages.path(req.db, page)) end
  local site_name = settings.get(req.db, "site.name")
  local hint = req.user and users.can(req.user, "content.edit_any")
    and ('<p><a class="wc-button" href="%s">Create a home page</a></p>'):format(req:url_for("/admin/pages/new?home=1")) or ""
  return engine.page(req, { template = "message", title = site_name, layout = "home",
    vars = { body = "<p>This site is being built with WordCore.</p>" .. hint } })
end

local function by_path(req, params)
  local path = "/" .. (params.path or "")
  path = path:gsub("/+$", "")
  if path == "" then return home(req) end
  local page = pages.find_by_path(req.db, path)
  if not page then return front.not_found(req) end
  if page.id == pages.home_id(req.db) then
    return http.new_response():redirect(req:url_for("/"), 301)
  end
  return show_page(req, page, path)
end

function front.register(r)
  r:get("/media/*rest", function(req, params) return media.serve(req, params.rest) end)
  r:get("/_wc/theme/:id/*rest", function(req, params) return engine.serve_asset(req, params.id, params.rest) end)
end

-- The catch-all page route must be registered last.
function front.register_pages(r)
  r:get("/", home, { name = "home" })
  r:get("/*path", by_path, { catch_all = true })
end

return front
