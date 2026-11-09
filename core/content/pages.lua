-- WordCore — pages: nested, with drafts, scheduling, access and revisions.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local slug = require("wc.lib.slug")
local settings = require("wc.platform.settings")

local pages = {}

-- First URL segments the core (and later addons) own.
pages.RESERVED = { admin = true, setup = true, _wc = true, media = true, account = true }

function pages.reserve(segment) pages.RESERVED[segment] = true end

function pages.migrate(db)
  db:migrate("content.pages", {
    [[CREATE TABLE wc_pages (
        id INTEGER PRIMARY KEY,
        parent_id INTEGER NOT NULL DEFAULT 0,
        slug TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'draft',
        publish_at INTEGER,
        access TEXT NOT NULL DEFAULT 'public',
        layout TEXT NOT NULL DEFAULT 'default',
        sort INTEGER NOT NULL DEFAULT 0,
        author_id INTEGER,
        updated_by INTEGER,
        created_at INTEGER NOT NULL DEFAULT (unixepoch()),
        updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
        UNIQUE (parent_id, slug))]],
    [[CREATE TABLE wc_page_revisions (
        id INTEGER PRIMARY KEY,
        page_id INTEGER NOT NULL REFERENCES wc_pages(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        user_id INTEGER,
        created_at INTEGER NOT NULL DEFAULT (unixepoch()))]],
    "CREATE INDEX wc_page_revisions_page ON wc_page_revisions (page_id, id)",
  })
end

---------------------------------------------------------------- reading

function pages.get(db, id)
  return db:first("SELECT * FROM wc_pages WHERE id = ?", id)
end

function pages.all(db)
  return db:query("SELECT id, parent_id, slug, title, status, publish_at, access, layout, sort, updated_at, updated_by FROM wc_pages ORDER BY sort, title COLLATE NOCASE")
end

function pages.count(db)
  local r = db:first([[SELECT COUNT(*) AS n,
    SUM(CASE WHEN status = 'draft' THEN 1 ELSE 0 END) AS drafts FROM wc_pages]])
  return r.n, r.drafts or 0
end

function pages.is_live(p, now)
  return p.status == "published" and (not p.publish_at or p.publish_at <= (now or os.time()))
end

function pages.state(p, now)
  if p.status ~= "published" then return "draft" end
  if p.publish_at and p.publish_at > (now or os.time()) then return "scheduled" end
  return "published"
end

-- Full path of a page ("/about/team").
function pages.path(db, page, cache)
  local parts = {}
  local seen = {}
  local p = page
  while p do
    if seen[p.id] then break end
    seen[p.id] = true
    table.insert(parts, 1, p.slug)
    if p.parent_id == 0 then break end
    p = cache and cache[p.parent_id] or pages.get(db, p.parent_id)
  end
  return "/" .. table.concat(parts, "/")
end

-- Tree as an ordered list with depth and path: { {page, depth, path}, ... }
function pages.tree(db)
  local list = pages.all(db)
  local by_id, children = {}, {}
  for _, p in ipairs(list) do
    by_id[p.id] = p
    children[p.parent_id] = children[p.parent_id] or {}
    table.insert(children[p.parent_id], p)
  end
  local out = {}
  local function walk(parent, depth, prefix)
    for _, p in ipairs(children[parent] or {}) do
      local path = prefix .. "/" .. p.slug
      out[#out + 1] = { page = p, depth = depth, path = path }
      walk(p.id, depth + 1, path)
    end
  end
  walk(0, 0, "")
  -- pages whose parent vanished still show up, at the top level
  local listed = {}
  for _, e in ipairs(out) do listed[e.page.id] = true end
  for _, p in ipairs(list) do
    if not listed[p.id] then out[#out + 1] = { page = p, depth = 0, path = "/" .. p.slug } end
  end
  return out, by_id
end

-- Find the page for a URL path like "/about/team". Returns page or nil.
function pages.find_by_path(db, path)
  local parent = 0
  local page
  for seg in path:gmatch("[^/]+") do
    page = db:first("SELECT * FROM wc_pages WHERE parent_id = ? AND slug = ?", parent, seg)
    if not page then return nil end
    parent = page.id
  end
  return page
end

function pages.home_id(db)
  return settings.get(db, "content.home_page", 0)
end

---------------------------------------------------------------- validation + saving

function pages.validate(db, fields, id)
  local errors = {}
  local title = fields.title or ""
  if title == "" then errors.title = "Give the page a title." elseif #title > 200 then errors.title = "Use at most 200 characters." end
  local s = fields.slug or ""
  if s == "" then s = slug.make(title) end
  if not slug.valid(s) then
    errors.slug = "Use lowercase letters, numbers and single dashes."
  elseif (fields.parent_id or 0) == 0 and pages.RESERVED[s] then
    errors.slug = ("“%s” is used by WordCore itself. Choose another address."):format(s)
  else
    local clash = db:first("SELECT id FROM wc_pages WHERE parent_id = ? AND slug = ? AND id <> ?", fields.parent_id or 0, s, id or 0)
    if clash then errors.slug = "Another page already uses this address." end
  end
  fields.slug = s
  if fields.parent_id and fields.parent_id ~= 0 then
    if id and fields.parent_id == id then errors.parent_id = "A page can't be inside itself." end
    local p = pages.get(db, fields.parent_id)
    local guard = 0
    while p and not errors.parent_id do
      if p.id == id then errors.parent_id = "A page can't be inside one of its own subpages." end
      if p.parent_id == 0 then break end
      p = pages.get(db, p.parent_id)
      guard = guard + 1
      if guard > 100 then break end
    end
    if not pages.get(db, fields.parent_id) then errors.parent_id = "That parent page doesn't exist." end
  end
  if fields.status ~= "draft" and fields.status ~= "published" then errors.status = "Choose a status." end
  if fields.access ~= "public" and fields.access ~= "members" then errors.access = "Choose who can view the page." end
  if #(fields.body or "") > 2 * 1024 * 1024 then errors.body = "The page is too long (2 MB max)." end
  return errors
end

function pages.add_revision(db, page_id, title, body, user_id)
  db:run("INSERT INTO wc_page_revisions (page_id, title, body, user_id) VALUES (?, ?, ?, ?)", page_id, title, body, user_id)
  db:run([[DELETE FROM wc_page_revisions WHERE page_id = ? AND id NOT IN
           (SELECT id FROM wc_page_revisions WHERE page_id = ? ORDER BY id DESC LIMIT 50)]], page_id, page_id)
end

function pages.create(db, f, user_id)
  local _, id = db:run([[INSERT INTO wc_pages (parent_id, slug, title, body, status, publish_at, access, layout, author_id, updated_by)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    f.parent_id or 0, f.slug, f.title, f.body or "", f.status or "draft", f.publish_at, f.access or "public",
    f.layout or "default", user_id, user_id)
  pages.add_revision(db, id, f.title, f.body or "", user_id)
  return id
end

function pages.update(db, id, f, user_id)
  local old = pages.get(db, id)
  db:run([[UPDATE wc_pages SET parent_id = ?, slug = ?, title = ?, body = ?, status = ?, publish_at = ?, access = ?,
           layout = ?, updated_by = ?, updated_at = unixepoch() WHERE id = ?]],
    f.parent_id or 0, f.slug, f.title, f.body or "", f.status, f.publish_at, f.access, f.layout or "default", user_id, id)
  if old and (old.body ~= (f.body or "") or old.title ~= f.title) then
    pages.add_revision(db, id, f.title, f.body or "", user_id)
  end
end

-- Delete a page; its subpages move up to its parent.
function pages.delete(db, id)
  local p = pages.get(db, id)
  if not p then return end
  db:transaction(function()
    for _, child in ipairs(db:query("SELECT id, slug FROM wc_pages WHERE parent_id = ?", id)) do
      local s = child.slug
      local n = 2
      while db:first("SELECT 1 AS x FROM wc_pages WHERE parent_id = ? AND slug = ?", p.parent_id, s) do
        s = child.slug .. "-" .. n
        n = n + 1
      end
      db:run("UPDATE wc_pages SET parent_id = ?, slug = ? WHERE id = ?", p.parent_id, s, child.id)
    end
    db:run("DELETE FROM wc_pages WHERE id = ?", id)
    db:run("DELETE FROM wc_menu_items WHERE kind = 'page' AND page_id = ?", id)
    if pages.home_id(db) == id then settings.set(db, "content.home_page", 0) end
  end)
end

function pages.revisions(db, page_id)
  return db:query([[SELECT r.id, r.title, r.created_at, length(r.body) AS size, u.username
                    FROM wc_page_revisions r LEFT JOIN wc_users u ON u.id = r.user_id
                    WHERE r.page_id = ? ORDER BY r.id DESC]], page_id)
end

function pages.revision(db, page_id, rev_id)
  return db:first("SELECT * FROM wc_page_revisions WHERE page_id = ? AND id = ?", page_id, rev_id)
end

return pages
