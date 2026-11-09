-- WordCore — admin: pages list, editor, history.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local pages = require("wc.content.pages")
local menus = require("wc.content.menus")
local render = require("wc.content.render")
local editors = require("wc.content.editors")
local engine = require("wc.themes.engine")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local admin_pages = {}

local function can_edit(req, p)
  if users.can(req.user, "content.edit_any") then return true end
  return users.can(req.user, "content.edit_own") and (p == nil or p.author_id == req.user.id)
end

local STATE_BADGE = { published = { "Published", "ok" }, draft = { "Draft", "warn" }, scheduled = { "Scheduled", "accent" } }

---------------------------------------------------------------- list

local function list(req)
  local filter = req.query.show or "all"
  local tree = pages.tree(req.db)
  local home = pages.home_id(req.db)
  local rows = {}
  local counts = { all = 0, published = 0, draft = 0, scheduled = 0 }
  for _, e in ipairs(tree) do
    local st = pages.state(e.page)
    counts.all = counts.all + 1
    counts[st] = counts[st] + 1
    if filter == "all" or filter == st then
      local b = STATE_BADGE[st]
      rows[#rows + 1] = ('<li class="page-row depth-%d"><span class="grow"><a class="row-title" href="%s">%s</a>%s<span class="mono small muted page-path">%s</span></span>%s%s<span class="when">%s</span></li>'):format(
        math.min(e.depth, 4), esc(req:url_for("/admin/pages/" .. e.page.id)), esc(e.page.title),
        e.page.id == home and ' <span class="badge">Home page</span>' or "",
        esc(e.page.id == home and "/" or e.path),
        e.page.access == "members" and ' <span class="badge">Members only</span>' or "",
        ui.badge(b[1], b[2]), esc(ui.ago(e.page.updated_at)))
    end
  end
  local tabs = {}
  for _, t in ipairs({ { "all", "All" }, { "published", "Published" }, { "draft", "Drafts" }, { "scheduled", "Scheduled" } }) do
    if t[1] == "all" or counts[t[1]] > 0 then
      tabs[#tabs + 1] = ('<a class="tab" href="%s"%s>%s <span class="muted">%d</span></a>'):format(
        esc(req:url_for("/admin/pages" .. (t[1] == "all" and "" or ("?show=" .. t[1])))), filter == t[1] and ' aria-current="page"' or "", t[2], counts[t[1]])
    end
  end
  local body = '<nav class="tabs" aria-label="Filter pages">' .. table.concat(tabs) .. "</nav>"
  if #rows == 0 then
    body = body .. ('<section class="card"><p class="empty">%s</p></section>'):format(
      counts.all == 0 and "No pages yet. Create your first one." or "No pages here.")
  else
    body = body .. '<section class="card"><ul class="list">' .. table.concat(rows) .. "</ul></section>"
  end
  local actions = users.can(req.user, "content.edit_own")
    and ('<a class="btn btn-primary" href="%s">New page</a>'):format(esc(req:url_for("/admin/pages/new"))) or nil
  return page.admin(req, { title = "Pages", subtitle = "Everything on your site that isn't a blog post.", active = "pages", body = body, actions_html = actions })
end

---------------------------------------------------------------- editor

local function parent_options(req, current_id)
  local opts = { { "0", "— None (top level) —" } }
  local tree = pages.tree(req.db)
  local skip = {}
  if current_id then skip[current_id] = true end
  for _, e in ipairs(tree) do
    if skip[e.page.parent_id] then skip[e.page.id] = true end
    if not skip[e.page.id] then
      opts[#opts + 1] = { tostring(e.page.id), string.rep("— ", e.depth) .. e.page.title }
    end
  end
  return opts
end

local function layout_options(req)
  local theme = engine.active(req)
  local opts = {}
  for _, l in ipairs(theme.meta.layouts or { { id = "default", label = "Default" } }) do opts[#opts + 1] = { l.id, l.label } end
  return opts
end

local function editor_view(req, p, v, errors, status, notice)
  errors = errors or {}
  local is_new = p == nil
  local action = is_new and "/admin/pages/new" or ("/admin/pages/" .. p.id)
  local editor = editors.active(req.db)
  local can_publish = users.can(req.user, "content.publish")
  local home = pages.home_id(req.db)
  local path_prefix = ""
  if v.parent_id and v.parent_id ~= 0 then
    local parent = pages.get(req.db, v.parent_id)
    if parent then path_prefix = pages.path(req.db, parent) end
  end
  local st_value = v.status == "published" and (v.publish_at and v.publish_at > os.time() and "scheduled" or "published") or "draft"
  local status_opts = { { "draft", "Draft" } }
  if can_publish then
    status_opts[#status_opts + 1] = { "published", "Published" }
  end

  local main = table.concat({
    notice and ('<div class="flash warn" role="alert">%s</div>'):format(esc(notice)) or "",
    errors.body and ('<div class="flash bad" role="alert">%s</div>'):format(esc(errors.body)) or "",
    '<div class="field title-field' .. (errors.title and " has-error" or "") .. '">',
    '<label class="sr-only" for="f-title">Title</label>',
    ('<input id="f-title" name="title" class="title-input" placeholder="Page title" maxlength="200" value="%s"%s data-slug-source>'):format(esc(v.title or ""), is_new and " autofocus" or ""),
    errors.title and ('<p class="error-text">%s</p>'):format(esc(errors.title)) or "",
    "</div>",
    editor.render(req, { name = "body", id = "f-body", value = v.body or "",
      preview_url = req:url_for("/admin/pages/preview"), media_url = req:url_for("/admin/media.json") }),
  })

  local publish_card = table.concat({
    '<section class="card"><div class="card-head"><h2>Publish</h2>',
    not is_new and ui.badge(STATE_BADGE[pages.state(p)][1], STATE_BADGE[pages.state(p)][2]) or "",
    '</div><div class="card-body">',
    ui.field({ name = "status", label = "Status", type = "select", options = status_opts, value = v.status or "draft", error = errors.status,
      hint = not can_publish and "An editor or administrator publishes your pages." or nil }),
    can_publish and ('<div class="field"><label for="f-publish_at_local">Publish at <span class="optional">(optional)</span></label><input id="f-publish_at_local" name="publish_at_local" type="datetime-local" class="input" data-epoch-target="f-publish_at"%s><input type="hidden" id="f-publish_at" name="publish_at" value="%s"><p class="hint">Leave empty to publish straight away. Uses your computer\'s time zone.</p></div>'):format(
      v.publish_at and (' data-epoch="' .. v.publish_at .. '"') or "", v.publish_at and tostring(v.publish_at) or "") or "",
    '<div class="actions">',
    ('<button type="submit" class="btn btn-primary">%s</button>'):format(is_new and "Create page" or "Save"),
    not is_new and ('<a class="btn" href="%s" target="_blank" rel="noopener">View</a>'):format(esc(req:url_for(p.id == home and "/" or pages.path(req.db, p)))) or "",
    "</div></div></section>",
  })

  local slug_field = ('<div class="field%s"><label for="f-slug">Address</label><div class="slug-row"><span class="mono small muted" data-slug-prefix>%s/</span><input id="f-slug" name="slug" class="input mono" value="%s" maxlength="80" spellcheck="false" data-slug%s></div>%s<p class="hint">Lowercase letters, numbers and dashes.</p></div>'):format(
    errors.slug and " has-error" or "", esc(path_prefix), esc(v.slug or ""), is_new and " data-slug-auto" or "",
    errors.slug and ('<p class="error-text">%s</p>'):format(esc(errors.slug)) or "")

  local page_card = table.concat({
    '<section class="card"><div class="card-head"><h2>Page</h2></div><div class="card-body">',
    slug_field,
    ui.field({ name = "parent_id", label = "Inside", type = "select", options = parent_options(req, p and p.id), value = tostring(v.parent_id or 0), error = errors.parent_id }),
    ui.field({ name = "layout", label = "Layout", type = "select", options = layout_options(req), value = v.layout or "default",
      hint = "Layouts come from the active theme." }),
    ui.field({ name = "access", label = "Who can view", type = "select", options = { { "public", "Everyone" }, { "members", "Signed-in members" } }, value = v.access or "public", error = errors.access }),
    users.can(req.user, "menus.manage") and ui.field({ name = "in_menu", label = "Show in the main menu", type = "checkbox", value = v.in_menu == true }) or "",
    users.can(req.user, "content.publish") and ui.field({ name = "is_home", label = "Use as the home page", type = "checkbox", value = v.is_home == true }) or "",
    "</div></section>",
  })

  local side = publish_card .. page_card
  if not is_new then
    side = side .. ('<p class="small"><a href="%s">Page history</a></p>'):format(esc(req:url_for("/admin/pages/" .. p.id .. "/history")))
  end

  local body = ('<form method="post" action="%s" class="editor-form" id="page-form" data-warn-unsaved>%s<input type="hidden" name="loaded_at" value="%d"><div class="editor-layout"><div class="editor-main">%s</div><aside class="editor-side" aria-label="Page settings">%s</aside></div></form>'):format(
    esc(req:url_for(action)), ui.csrf(req.session.csrf), v.loaded_at or os.time(), main, side)

  if not is_new and can_edit(req, p) then
    body = body .. ('<form method="post" action="%s" class="delete-form" data-confirm="Delete “%s”? Its subpages move up a level. This can\'t be undone.">%s<button type="submit" class="btn btn-danger btn-sm">Delete page</button></form>'):format(
      esc(req:url_for("/admin/pages/" .. p.id .. "/delete")), esc(p.title), ui.csrf(req.session.csrf))
  end

  local res = page.admin(req, { title = is_new and "New page" or ("Edit: " .. p.title), active = "pages", body = body, wide = true,
    actions_html = ('<a class="btn" href="%s">All pages</a>'):format(esc(req:url_for("/admin/pages"))) })
  if status then res.status = status end
  return res
end

local function values_from_page(req, p)
  return {
    title = p.title, slug = p.slug, body = p.body, parent_id = p.parent_id, status = p.status, publish_at = p.publish_at,
    access = p.access, layout = p.layout, is_home = pages.home_id(req.db) == p.id,
    in_menu = menus.page_in(req.db, "main", p.id), loaded_at = os.time(),
  }
end

local function values_from_form(req)
  local f = req:form()
  local v = {
    title = (f.title or ""):gsub("^%s+", ""):gsub("%s+$", ""),
    slug = (f.slug or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower(),
    body = (f.body or ""):gsub("\r\n", "\n"),
    parent_id = tonumber(f.parent_id or "0") or 0,
    status = f.status or "draft",
    publish_at = tonumber(f.publish_at or ""),
    access = f.access or "public",
    layout = f.layout or "default",
    is_home = f.is_home == "1",
    in_menu = f.in_menu == "1",
    loaded_at = tonumber(f.loaded_at or "") or 0,
  }
  if v.publish_at and v.publish_at <= os.time() + 30 then v.publish_at = nil end
  return v
end

local function get_new(req)
  if not users.can(req.user, "content.edit_own") then return http.error_page(403, "You can't create pages.") end
  return editor_view(req, nil, { status = "draft", access = "public", layout = "default", parent_id = tonumber(req.query.parent or "0") or 0,
    is_home = req.query.home == "1", in_menu = false })
end

local function save_extras(req, id, v)
  if users.can(req.user, "menus.manage") then
    local inmenu = menus.page_in(req.db, "main", id)
    if v.in_menu and not inmenu then menus.add_page(req.db, "main", id, "") end
    if not v.in_menu and inmenu then menus.remove_page(req.db, "main", id) end
  end
  if users.can(req.user, "content.publish") then
    local home = pages.home_id(req.db)
    if v.is_home and home ~= id then settings.set(req.db, "content.home_page", id) end
    if not v.is_home and home == id then settings.set(req.db, "content.home_page", 0) end
  end
end

local function post_new(req)
  if not users.can(req.user, "content.edit_own") then return http.error_page(403, "You can't create pages.") end
  local v = values_from_form(req)
  if not users.can(req.user, "content.publish") then v.status = "draft" v.publish_at = nil end
  local errors = pages.validate(req.db, v, nil)
  local layouts = {}
  for _, o in ipairs(layout_options(req)) do layouts[o[1]] = true end
  if not layouts[v.layout] then v.layout = "default" end
  if next(errors) then return editor_view(req, nil, v, errors, 422) end
  local id
  req.db:transaction(function()
    id = pages.create(req.db, v, req.user.id)
    save_extras(req, id, v)
  end)
  log.add(req.db, req, "page.created", v.title)
  session.flash(req, "ok", v.status == "published" and "Page published." or "Draft saved.")
  return http.new_response():redirect(req:url_for("/admin/pages/" .. id))
end

local function load(req, params)
  local p = pages.get(req.db, tonumber(params.id))
  if not p then return nil, http.error_page(404, "That page doesn't exist.") end
  if not can_edit(req, p) then return nil, http.error_page(403, "You can only edit your own pages.") end
  return p
end

local function get_edit(req, params)
  local p, err = load(req, params)
  if not p then return err end
  return editor_view(req, p, values_from_page(req, p))
end

local function post_edit(req, params)
  local p, err = load(req, params)
  if not p then return err end
  local v = values_from_form(req)
  if not users.can(req.user, "content.publish") then
    -- authors can't publish or unpublish
    v.status, v.publish_at, v.is_home = p.status, p.publish_at, pages.home_id(req.db) == p.id
  end
  local layouts = {}
  for _, o in ipairs(layout_options(req)) do layouts[o[1]] = true end
  if not layouts[v.layout] then v.layout = p.layout end
  local errors = pages.validate(req.db, v, p.id)
  if next(errors) then return editor_view(req, p, v, errors, 422) end
  -- someone else saved since this editor was opened?
  if p.updated_at > v.loaded_at and p.updated_by ~= req.user.id then
    local who = p.updated_by and users.get(req.db, p.updated_by)
    v.loaded_at = os.time()
    return editor_view(req, p, v, {}, 409, ("%s changed this page while you were editing. Your text is below — save again to replace their version (it stays in the page history)."):format(
      who and who.username or "Someone"))
  end
  req.db:transaction(function()
    pages.update(req.db, p.id, v, req.user.id)
    save_extras(req, p.id, v)
  end)
  log.add(req.db, req, "page.saved", v.title)
  local was_live, now_live = pages.is_live(p), v.status == "published" and not v.publish_at
  session.flash(req, "ok", (not was_live and now_live) and "Page published." or (was_live and v.status == "draft") and "Page unpublished — it's a draft again." or "Saved.")
  return http.new_response():redirect(req:url_for("/admin/pages/" .. p.id))
end

local function post_delete(req, params)
  local p, err = load(req, params)
  if not p then return err end
  pages.delete(req.db, p.id)
  log.add(req.db, req, "page.deleted", p.title)
  session.flash(req, "ok", ("Deleted “%s”."):format(p.title))
  return http.new_response():redirect(req:url_for("/admin/pages"))
end

local function post_preview(req)
  local body = (req:form().body or ""):gsub("\r\n", "\n")
  local res = http.new_response(200)
  res:set_header("Content-Type", "text/html; charset=utf-8")
  res.body = (render.html(body, { req = req, preview = true }))
  return res
end

---------------------------------------------------------------- history

local function history(req, params)
  local p, err = load(req, params)
  if not p then return err end
  local revs = pages.revisions(req.db, p.id)
  local rows = {}
  for i, r in ipairs(revs) do
    rows[#rows + 1] = ('<li><span class="grow"><a href="%s">%s</a>%s<br><span class="small muted">%s · %s</span></span><span class="when">%s</span></li>'):format(
      esc(req:url_for("/admin/pages/" .. p.id .. "/history/" .. r.id)), esc(r.title), i == 1 and ' <span class="badge ok">Current</span>' or "",
      esc(r.username or "unknown"), esc(ui.bytes(r.size)), esc(ui.ago(r.created_at)))
  end
  return page.admin(req, { title = "History: " .. p.title, subtitle = "The last 50 saved versions.", active = "pages", narrow = true,
    body = '<section class="card"><ul class="list">' .. table.concat(rows) .. "</ul></section>",
    actions_html = ('<a class="btn" href="%s">Back to the page</a>'):format(esc(req:url_for("/admin/pages/" .. p.id))) })
end

local function revision(req, params)
  local p, err = load(req, params)
  if not p then return err end
  local r = pages.revision(req.db, p.id, tonumber(params.rev))
  if not r then return http.error_page(404, "That version doesn't exist.") end
  local body = ('<section class="card"><div class="card-head"><h2>%s</h2><span class="small muted">%s</span></div><div class="card-body md-preview">%s</div></section>'):format(
    esc(r.title), esc(os.date("!%Y-%m-%d %H:%M UTC", r.created_at)), (render.html(r.body, { req = req, preview = true })))
    .. ('<form method="post" action="%s" data-confirm="Replace the current text with this version? The current version stays in the history.">%s<button type="submit" class="btn btn-primary">Restore this version</button></form>'):format(
      esc(req:url_for("/admin/pages/" .. p.id .. "/history/" .. r.id .. "/restore")), ui.csrf(req.session.csrf))
  return page.admin(req, { title = "Version from " .. ui.ago(r.created_at), active = "pages", narrow = true, body = body,
    actions_html = ('<a class="btn" href="%s">All versions</a>'):format(esc(req:url_for("/admin/pages/" .. p.id .. "/history"))) })
end

local function restore(req, params)
  local p, err = load(req, params)
  if not p then return err end
  local r = pages.revision(req.db, p.id, tonumber(params.rev))
  if not r then return http.error_page(404, "That version doesn't exist.") end
  local v = values_from_page(req, p)
  v.title, v.body = r.title, r.body
  pages.update(req.db, p.id, v, req.user.id)
  log.add(req.db, req, "page.restored", p.title)
  session.flash(req, "ok", "Older version restored.")
  return http.new_response():redirect(req:url_for("/admin/pages/" .. p.id))
end

function admin_pages.register(r)
  r:get("/admin/pages", list, { name = "pages", auth = "content.edit_own" })
  r:get("/admin/pages/new", get_new, { auth = "content.edit_own" })
  r:post("/admin/pages/new", post_new, { auth = "content.edit_own" })
  r:post("/admin/pages/preview", post_preview, { auth = "content.edit_own" })
  r:get("/admin/pages/:id", get_edit, { auth = "content.edit_own" })
  r:post("/admin/pages/:id", post_edit, { auth = "content.edit_own" })
  r:post("/admin/pages/:id/delete", post_delete, { auth = "content.edit_own" })
  r:get("/admin/pages/:id/history", history, { auth = "content.edit_own" })
  r:get("/admin/pages/:id/history/:rev", revision, { auth = "content.edit_own" })
  r:post("/admin/pages/:id/history/:rev/restore", restore, { auth = "content.edit_own" })
end

return admin_pages
