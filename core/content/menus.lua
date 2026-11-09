-- WordCore — menus (main and footer), with one level of sub-items.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local pages = require("wc.content.pages")

local menus = {}

menus.MENUS = { { id = "main", label = "Main menu" }, { id = "footer", label = "Footer menu" } }

function menus.valid(id)
  for _, m in ipairs(menus.MENUS) do if m.id == id then return true end end
  return false
end

function menus.migrate(db)
  db:migrate("content.menus", {
    [[CREATE TABLE wc_menu_items (
        id INTEGER PRIMARY KEY,
        menu TEXT NOT NULL,
        parent_id INTEGER NOT NULL DEFAULT 0,
        label TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL,
        page_id INTEGER,
        url TEXT,
        position INTEGER NOT NULL DEFAULT 0)]],
    "CREATE INDEX wc_menu_items_menu ON wc_menu_items (menu, parent_id, position)",
  })
end

function menus.items(db, menu)
  return db:query([[SELECT m.*, p.title AS page_title, p.status AS page_status, p.publish_at AS page_publish_at
                    FROM wc_menu_items m LEFT JOIN wc_pages p ON p.id = m.page_id
                    WHERE m.menu = ? ORDER BY m.parent_id <> 0, m.position, m.id]], menu)
end

-- Ordered flat list for the admin: top items each followed by their children.
function menus.ordered(db, menu)
  local items = menus.items(db, menu)
  local top, kids = {}, {}
  for _, it in ipairs(items) do
    if it.parent_id == 0 then top[#top + 1] = it else
      kids[it.parent_id] = kids[it.parent_id] or {}
      table.insert(kids[it.parent_id], it)
    end
  end
  local out = {}
  for _, t in ipairs(top) do
    t.depth = 0
    out[#out + 1] = t
    for _, k in ipairs(kids[t.id] or {}) do k.depth = 1 out[#out + 1] = k end
  end
  return out
end

local function next_position(db, menu, parent)
  local r = db:first("SELECT COALESCE(MAX(position), 0) + 1 AS p FROM wc_menu_items WHERE menu = ? AND parent_id = ?", menu, parent)
  return r.p
end

function menus.add_page(db, menu, page_id, label)
  local _, id = db:run("INSERT INTO wc_menu_items (menu, kind, page_id, label, position) VALUES (?, 'page', ?, ?, ?)",
    menu, page_id, label or "", next_position(db, menu, 0))
  return id
end

function menus.add_link(db, menu, label, url)
  local _, id = db:run("INSERT INTO wc_menu_items (menu, kind, url, label, position) VALUES (?, 'url', ?, ?, ?)",
    menu, url, label, next_position(db, menu, 0))
  return id
end

function menus.get(db, id) return db:first("SELECT * FROM wc_menu_items WHERE id = ?", id) end

function menus.remove(db, id)
  local it = menus.get(db, id)
  if not it then return end
  db:transaction(function()
    db:run("UPDATE wc_menu_items SET parent_id = 0, position = position + 1000 WHERE parent_id = ?", id)
    db:run("DELETE FROM wc_menu_items WHERE id = ?", id)
  end)
end

function menus.rename(db, id, label) db:run("UPDATE wc_menu_items SET label = ? WHERE id = ?", label, id) end

-- Move an item up/down among its siblings.
function menus.move(db, id, dir)
  local it = menus.get(db, id)
  if not it then return end
  local siblings = db:query("SELECT id, position FROM wc_menu_items WHERE menu = ? AND parent_id = ? ORDER BY position, id", it.menu, it.parent_id)
  local idx
  for i, s in ipairs(siblings) do if s.id == id then idx = i end end
  local other = siblings[idx + (dir == "up" and -1 or 1)]
  if not other then return end
  db:transaction(function()
    for i, s in ipairs(siblings) do db:run("UPDATE wc_menu_items SET position = ? WHERE id = ?", i, s.id) end
    local a, b = idx, idx + (dir == "up" and -1 or 1)
    db:run("UPDATE wc_menu_items SET position = ? WHERE id = ?", b, siblings[a].id)
    db:run("UPDATE wc_menu_items SET position = ? WHERE id = ?", a, siblings[b].id)
  end)
end

-- Indent under the previous top-level item, or move back out.
function menus.indent(db, id, inward)
  local it = menus.get(db, id)
  if not it then return false end
  if inward then
    if it.parent_id ~= 0 then return false end
    if db:first("SELECT 1 AS x FROM wc_menu_items WHERE parent_id = ?", id) then return false end
    local prev = db:first([[SELECT id FROM wc_menu_items WHERE menu = ? AND parent_id = 0 AND
                            (position < ? OR (position = ? AND id < ?)) ORDER BY position DESC, id DESC LIMIT 1]],
      it.menu, it.position, it.position, it.id)
    if not prev then return false end
    db:run("UPDATE wc_menu_items SET parent_id = ?, position = ? WHERE id = ?", prev.id, next_position(db, it.menu, prev.id), id)
  else
    if it.parent_id == 0 then return false end
    local parent = menus.get(db, it.parent_id)
    db:run("UPDATE wc_menu_items SET parent_id = 0, position = ? WHERE id = ?", (parent and parent.position or 0), id)
  end
  return true
end

function menus.page_in(db, menu, page_id)
  return db:first("SELECT id FROM wc_menu_items WHERE menu = ? AND kind = 'page' AND page_id = ?", menu, page_id) ~= nil
end

function menus.remove_page(db, menu, page_id)
  for _, r in ipairs(db:query("SELECT id FROM wc_menu_items WHERE menu = ? AND kind = 'page' AND page_id = ?", menu, page_id)) do
    menus.remove(db, r.id)
  end
end

-- Menu tree for themes: { {label, url, current, children = {...}} } (only live pages).
function menus.for_theme(db, menu, req, current_path)
  local tree, by_id = {}, {}
  local cache = {}
  for _, p in ipairs(pages.all(db)) do cache[p.id] = p end
  local home = pages.home_id(db)
  for _, it in ipairs(menus.items(db, menu)) do
    local entry
    if it.kind == "page" then
      local p = cache[it.page_id]
      if p and pages.is_live(p) then
        local path = p.id == home and "/" or pages.path(db, p, cache)
        entry = { label = it.label ~= "" and it.label or p.title, url = req:url_for(path), path = path }
      end
    else
      local url = it.url or "#"
      entry = { label = it.label, url = url:sub(1, 1) == "/" and req:url_for(url) or url, path = url, external = url:match("^https?://") ~= nil }
    end
    if entry then
      entry.current = current_path ~= nil and entry.path == current_path
      entry.children = {}
      by_id[it.id] = entry
      if it.parent_id == 0 then
        tree[#tree + 1] = entry
      elseif by_id[it.parent_id] then
        table.insert(by_id[it.parent_id].children, entry)
        if entry.current then by_id[it.parent_id].current_parent = true end
      end
    end
  end
  return tree
end

return menus
