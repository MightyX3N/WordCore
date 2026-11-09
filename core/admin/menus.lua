-- WordCore — admin: menus (main and footer).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Plain forms with up/down/indent buttons: works without JavaScript and with
-- a keyboard. (Drag and drop can come later as an enhancement.)

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local log = require("wc.platform.log")
local pages = require("wc.content.pages")
local menus = require("wc.content.menus")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local admin_menus = {}

local function menu_label(id)
  for _, m in ipairs(menus.MENUS) do if m.id == id then return m.label end end
end

local function btn(req, item, action, label, text, disabled)
  return ('<button type="submit" class="btn btn-sm icon-btn" name="do" value="%s" aria-label="%s" title="%s"%s>%s</button>'):format(
    action, esc(label), esc(label), disabled and " disabled" or "", text)
end

local function view(req, menu, status, errors, values)
  errors, values = errors or {}, values or {}
  local items = menus.ordered(req.db, menu)
  local rows = {}
  for i, it in ipairs(items) do
    local name, sub
    if it.kind == "page" then
      name = it.label ~= "" and it.label or (it.page_title or "Missing page")
      local live = it.page_status and pages.is_live({ status = it.page_status, publish_at = it.page_publish_at })
      sub = it.page_title and ("Page: " .. it.page_title .. (live and "" or " (not published — hidden)")) or "The page was deleted"
    else
      name, sub = it.label, it.url
    end
    local prev_sibling, next_sibling = false, false
    for j = i - 1, 1, -1 do
      if items[j].depth < it.depth then break end
      if items[j].depth == it.depth and items[j].parent_id == it.parent_id then prev_sibling = true break end
    end
    for j = i + 1, #items do
      if items[j].depth < it.depth then break end
      if items[j].depth == it.depth and items[j].parent_id == it.parent_id then next_sibling = true break end
    end
    local has_kids = items[i + 1] and items[i + 1].depth > it.depth
    local form = ('<form method="post" action="%s" class="menu-tools">%s%s%s%s%s%s</form>'):format(
      esc(req:url_for("/admin/menus/" .. menu .. "/item/" .. it.id)), ui.csrf(req.session.csrf),
      btn(req, it, "up", "Move “" .. name .. "” up", "↑", not prev_sibling),
      btn(req, it, "down", "Move “" .. name .. "” down", "↓", not next_sibling),
      it.depth == 0 and btn(req, it, "in", "Put “" .. name .. "” under the item above", "→", not prev_sibling or has_kids)
        or btn(req, it, "out", "Move “" .. name .. "” back to the top level", "←", false),
      btn(req, it, "remove", "Remove “" .. name .. "” from the menu", "×", false),
      "")
    rows[#rows + 1] = ('<li class="menu-row depth-%d"><details class="grow"><summary><strong>%s</strong> <span class="muted small">%s</span></summary><form method="post" action="%s" class="inline-form">%s<input type="hidden" name="do" value="rename"><label class="sr-only" for="lbl-%d">Label</label><input id="lbl-%d" class="input" name="label" value="%s" maxlength="80" placeholder="%s"><button type="submit" class="btn btn-sm">Rename</button></form></details>%s</li>'):format(
      it.depth, esc(name), esc(sub or ""), esc(req:url_for("/admin/menus/" .. menu .. "/item/" .. it.id)), ui.csrf(req.session.csrf),
      it.id, it.id, esc(it.label), esc(it.kind == "page" and (it.page_title or "") or "Label"), form)
  end
  local list = #rows > 0 and ('<ul class="list menu-list">' .. table.concat(rows) .. "</ul>")
    or '<p class="empty">This menu is empty. Add pages or links below.</p>'

  -- add page
  local in_menu = {}
  for _, it in ipairs(items) do if it.kind == "page" then in_menu[it.page_id] = true end end
  local opts = {}
  for _, e in ipairs(pages.tree(req.db)) do
    if not in_menu[e.page.id] then opts[#opts + 1] = { tostring(e.page.id), string.rep("— ", e.depth) .. e.page.title } end
  end
  local add_page = #opts > 0 and ui.form({ action = req:url_for("/admin/menus/" .. menu .. "/add"), csrf = req.session.csrf, submit = "Add page", fields = {
    { type = "hidden", name = "kind", value = "page" },
    { name = "page_id", label = "Page", type = "select", options = opts },
  }}) or '<p class="muted small">Every page is already in this menu.</p>'
  local add_link = ui.form({ action = req:url_for("/admin/menus/" .. menu .. "/add"), csrf = req.session.csrf, submit = "Add link", fields = {
    { type = "hidden", name = "kind", value = "url" },
    { name = "label", label = "Label", max = 80, value = values.label, error = errors.label },
    { name = "url", label = "Address", max = 500, value = values.url, error = errors.url, mono = true, placeholder = "https://… or /path",
      hint = "A full https:// address, or a path on this site like /contact." },
  }})

  local tabs = {}
  for _, m in ipairs(menus.MENUS) do
    tabs[#tabs + 1] = ('<a class="tab" href="%s"%s>%s</a>'):format(esc(req:url_for("/admin/menus/" .. m.id)), m.id == menu and ' aria-current="page"' or "", esc(m.label))
  end
  local body = '<nav class="tabs" aria-label="Menus">' .. table.concat(tabs) .. "</nav>"
    .. ui.card(menu_label(menu), list, { aside = '<span class="muted small">One level of sub-items. Unpublished pages are hidden from visitors.</span>' })
    .. '<div class="grid-2">' .. ui.card("Add a page", '<div class="card-body">' .. add_page .. "</div>")
    .. ui.card("Add a link", '<div class="card-body">' .. add_link .. "</div>") .. "</div>"
  local res = page.admin(req, { title = "Menus", subtitle = "Where visitors find your pages. Your theme decides how they look.", active = "menus", body = body })
  if status then res.status = status end
  return res
end

local function get(req, params)
  local menu = params.menu or "main"
  if not menus.valid(menu) then return http.error_page(404, "There's no menu called that.") end
  return view(req, menu)
end

local function valid_url(u)
  if u:find("[%s<>\"'`]") or #u > 500 then return false end
  if u:match("^https?://[%w%.%-]+") then return true end
  if u:match("^/[^/]") or u == "/" then return true end
  if u:match("^mailto:[^@]+@[^@]+$") then return true end
  if u:match("^#[%w%-_]+$") then return true end
  return false
end

local function add(req, params)
  local menu = params.menu
  if not menus.valid(menu) then return http.error_page(404, "There's no menu called that.") end
  local f = req:form()
  if f.kind == "page" then
    local p = pages.get(req.db, tonumber(f.page_id or ""))
    if not p then return view(req, menu, 422) end
    if not menus.page_in(req.db, menu, p.id) then menus.add_page(req.db, menu, p.id, "") end
    session.flash(req, "ok", ("Added “%s”."):format(p.title))
  else
    local label = (f.label or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local url = (f.url or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local errors = {}
    if label == "" then errors.label = "Give the link a label." elseif #label > 80 then errors.label = "Use at most 80 characters." end
    if not valid_url(url) then errors.url = "Use an https:// address, a path starting with /, or mailto:." end
    if next(errors) then return view(req, menu, 422, errors, { label = label, url = url }) end
    menus.add_link(req.db, menu, label, url)
    session.flash(req, "ok", ("Added “%s”."):format(label))
  end
  log.add(req.db, req, "menus.changed", menu_label(menu))
  return http.new_response():redirect(req:url_for("/admin/menus/" .. menu))
end

local function item(req, params)
  local menu = params.menu
  local it = menus.get(req.db, tonumber(params.id))
  if not menus.valid(menu) or not it or it.menu ~= menu then return http.error_page(404, "That menu item doesn't exist.") end
  local f = req:form()
  local action = f["do"]
  if action == "up" or action == "down" then menus.move(req.db, it.id, action)
  elseif action == "in" then menus.indent(req.db, it.id, true)
  elseif action == "out" then menus.indent(req.db, it.id, false)
  elseif action == "remove" then
    menus.remove(req.db, it.id)
    session.flash(req, "ok", "Removed from the menu.")
  elseif action == "rename" then
    local label = (f.label or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if it.kind == "url" and label == "" then
      session.flash(req, "bad", "A link needs a label.")
    else
      menus.rename(req.db, it.id, label:sub(1, 80))
      session.flash(req, "ok", "Renamed.")
    end
  else
    return http.error_page(400, "Unknown action.")
  end
  log.add(req.db, req, "menus.changed", menu_label(menu))
  return http.new_response():redirect(req:url_for("/admin/menus/" .. menu))
end

function admin_menus.register(r)
  r:get("/admin/menus", get, { name = "menus", auth = "menus.manage" })
  r:get("/admin/menus/:menu", get, { auth = "menus.manage" })
  r:post("/admin/menus/:menu/add", add, { auth = "menus.manage" })
  r:post("/admin/menus/:menu/item/:id", item, { auth = "menus.manage" })
end

return admin_menus
