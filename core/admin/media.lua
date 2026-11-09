-- WordCore — admin: media library.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local media = require("wc.content.media")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local admin_media = {}

local KIND_LABEL = { ["application/pdf"] = "PDF", ["application/zip"] = "ZIP" }
local function kind_label(item)
  if media.is_image(item) then return (item.mime:match("/(%w+)") or "image"):upper() end
  return KIND_LABEL[item.mime] or (item.mime:match("^(%w+)/") or "file"):gsub("^%l", string.upper)
end

local function thumb(req, item)
  if media.is_image(item) then
    return ('<img src="%s" alt="%s" loading="lazy" width="%d" height="%d">'):format(
      esc(media.url(req, item)), esc(item.alt), item.width or 160, item.height or 160)
  end
  return ('<span class="file-kind" aria-hidden="true">%s</span>'):format(esc(kind_label(item)))
end

local function upload_form(req)
  return ('<form method="post" action="%s" enctype="multipart/form-data" class="card upload" data-upload>%s'
    .. '<div class="card-body"><label class="dropzone" for="f-files"><strong>Choose files to upload</strong><span class="muted small">or drop them here · images, PDF, video, audio, ZIP · up to 32 MB each</span></label>'
    .. '<input id="f-files" name="files" type="file" multiple accept="image/png,image/jpeg,image/gif,image/webp,image/avif,application/pdf,video/mp4,video/webm,audio/mpeg,audio/ogg,application/zip,.mp3,.ogg,.zip">'
    .. '<div class="actions"><button type="submit" class="btn btn-primary">Upload</button></div></div></form>'):format(
      esc(req:url_for("/admin/media/upload")), ui.csrf(req.session.csrf))
end

local function list(req)
  local filter = req.query.show == "image" and "image" or req.query.show == "other" and "other" or "all"
  local items = media.list(req.db)
  local n, bytes = media.stats(req.db)
  local cards = {}
  local images = 0
  for _, it in ipairs(items) do
    local img = media.is_image(it)
    if img then images = images + 1 end
    if filter == "all" or (filter == "image") == img then
      cards[#cards + 1] = ('<li><a class="media-card" href="%s">%s<span class="media-name">%s</span><span class="media-meta">%s · %s</span></a></li>'):format(
        esc(req:url_for("/admin/media/" .. it.id)), thumb(req, it), esc(it.path:match("[^/]+$")),
        esc(kind_label(it)), esc(ui.bytes(it.size)))
    end
  end
  local tabs = ('<nav class="tabs" aria-label="Filter media"><a class="tab" href="%s"%s>All <span class="muted">%d</span></a><a class="tab" href="%s"%s>Images <span class="muted">%d</span></a><a class="tab" href="%s"%s>Other files <span class="muted">%d</span></a></nav>'):format(
    esc(req:url_for("/admin/media")), filter == "all" and ' aria-current="page"' or "", n,
    esc(req:url_for("/admin/media?show=image")), filter == "image" and ' aria-current="page"' or "", images,
    esc(req:url_for("/admin/media?show=other")), filter == "other" and ' aria-current="page"' or "", n - images)
  local grid = #cards > 0 and ('<ul class="media-grid">' .. table.concat(cards) .. "</ul>")
    or '<section class="card"><p class="empty">Nothing here yet.</p></section>'
  return page.admin(req, { title = "Media", subtitle = ("%d file%s · %s"):format(n, n == 1 and "" or "s", ui.bytes(bytes)),
    active = "media", body = upload_form(req) .. tabs .. grid })
end

local function upload(req)
  req:form()
  if req.form_error then
    session.flash(req, "bad", "The upload didn't arrive in one piece. Try again.")
    return http.new_response():redirect(req:url_for("/admin/media"))
  end
  local saved, problems = {}, {}
  for _, f in ipairs(req.files or {}) do
    if f.field == "files" and f.filename ~= "" then
      local id, err = media.save(req.site, req.db, f, req.user.id)
      if id then saved[#saved + 1] = id else problems[#problems + 1] = err end
    end
  end
  for _, p in ipairs(problems) do session.flash(req, "bad", p) end
  if #saved > 0 then
    log.add(req.db, req, "media.uploaded", ("%d file%s"):format(#saved, #saved == 1 and "" or "s"))
    session.flash(req, "ok", ("Uploaded %d file%s."):format(#saved, #saved == 1 and "" or "s"))
  elseif #problems == 0 then
    session.flash(req, "warn", "Choose at least one file first.")
  end
  if req.headers["accept"] and req.headers["accept"]:find("application/json", 1, true) then
    local out = {}
    for _, id in ipairs(saved) do
      local it = media.get(req.db, id)
      out[#out + 1] = { id = it.id, url = media.url(req, it), alt = it.alt, image = media.is_image(it) }
    end
    return http.new_response():json({ saved = out, errors = problems }, #saved > 0 and 200 or 422)
  end
  if #saved == 1 then return http.new_response():redirect(req:url_for("/admin/media/" .. saved[1])) end
  return http.new_response():redirect(req:url_for("/admin/media"))
end

local function can_change(req, item)
  return users.can(req.user, "content.edit_any") or item.user_id == req.user.id
end

local function show(req, params, errors, status)
  local item = media.get(req.db, tonumber(params.id))
  if not item then return http.error_page(404, "That file doesn't exist.") end
  local url = media.url(req, item)
  local used = media.used_in(req.db, item)
  local used_html
  if #used == 0 then
    used_html = '<p class="muted small">Not used on any page.</p>'
  else
    local li = {}
    for _, p in ipairs(used) do li[#li + 1] = ('<li><a href="%s">%s</a></li>'):format(esc(req:url_for("/admin/pages/" .. p.id)), esc(p.title)) end
    used_html = '<ul class="plain">' .. table.concat(li) .. "</ul>"
  end
  local snippet = media.is_image(item) and ("![" .. item.alt .. "](" .. "/media/" .. item.path .. ")") or ("[" .. item.original_name .. "](" .. "/media/" .. item.path .. ")")
  local preview = media.is_image(item)
    and ('<img class="media-full" src="%s" alt="%s" width="%d" height="%d">'):format(esc(url), esc(item.alt), item.width or 0, item.height or 0)
    or ('<p><a class="btn" href="%s">Open the file</a></p>'):format(esc(url))
  local details = table.concat({
    '<dl class="facts">',
    ("<dt>File</dt><dd class=\"mono small\">%s</dd>"):format(esc(item.path)),
    ("<dt>Uploaded as</dt><dd>%s</dd>"):format(esc(item.original_name)),
    ("<dt>Type</dt><dd>%s · %s</dd>"):format(esc(item.mime), esc(ui.bytes(item.size))),
    item.width and ("<dt>Size</dt><dd>%d × %d px</dd>"):format(item.width, item.height) or "",
    ("<dt>Uploaded</dt><dd>%s</dd>"):format(esc(ui.ago(item.created_at))),
    "</dl>",
  })
  local edit = can_change(req, item) and ui.form({ action = req:url_for("/admin/media/" .. item.id), csrf = req.session.csrf, submit = "Save", fields = {
    media.is_image(item) and { name = "alt", label = "Alt text", value = (errors and errors.value) or item.alt, max = 200, error = errors and errors.alt,
      hint = "Describes the image for people who can't see it. Leave empty only for decoration." } or
      { name = "alt", label = "Link text", value = (errors and errors.value) or item.alt, max = 200, error = errors and errors.alt },
  }}) or ""
  local body = ('<div class="media-detail"><section class="card"><div class="card-body media-preview">%s</div></section><div>'):format(preview)
    .. ui.card("Details", '<div class="card-body">' .. details .. "</div>")
    .. ui.card("Use it", ('<div class="card-body"><div class="field"><label for="f-snippet">Markdown</label><div class="copy-row"><input id="f-snippet" class="input mono" readonly value="%s"><button type="button" class="btn" data-copy="%s">Copy</button></div></div><div class="field"><label for="f-url">Address</label><div class="copy-row"><input id="f-url" class="input mono" readonly value="%s"><button type="button" class="btn" data-copy="%s">Copy</button></div></div></div>'):format(
        esc(snippet), esc(snippet), esc(req.public_url and (req.public_url:gsub("/+$", "") .. "/media/" .. item.path) or url), esc(req.public_url and (req.public_url:gsub("/+$", "") .. "/media/" .. item.path) or url)))
    .. (edit ~= "" and ('<section class="card"><div class="card-body">' .. edit .. "</div></section>") or "")
    .. ui.card("Used on", '<div class="card-body">' .. used_html .. "</div>")
    .. (can_change(req, item) and ('<form method="post" action="%s" data-confirm="Delete this file?%s It can\'t be undone.">%s<button type="submit" class="btn btn-danger btn-sm">Delete file</button></form>'):format(
      esc(req:url_for("/admin/media/" .. item.id .. "/delete")), #used > 0 and (" It's still used on " .. #used .. " page" .. (#used == 1 and "" or "s") .. ", which will show a broken link.") or "", ui.csrf(req.session.csrf)) or "")
    .. "</div></div>"
  local res = page.admin(req, { title = item.path:match("[^/]+$"), active = "media", body = body, wide = true,
    actions_html = ('<a class="btn" href="%s">All media</a>'):format(esc(req:url_for("/admin/media"))) })
  if status then res.status = status end
  return res
end

local function save(req, params)
  local item = media.get(req.db, tonumber(params.id))
  if not item then return http.error_page(404, "That file doesn't exist.") end
  if not can_change(req, item) then return http.error_page(403, "You can only change your own uploads.") end
  local alt = (req:form().alt or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]+", " ")
  if #alt > 200 then return show(req, params, { alt = "Use at most 200 characters.", value = alt }, 422) end
  req.db:run("UPDATE wc_media SET alt = ? WHERE id = ?", alt, item.id)
  session.flash(req, "ok", "Saved.")
  return http.new_response():redirect(req:url_for("/admin/media/" .. item.id))
end

local function delete(req, params)
  local item = media.get(req.db, tonumber(params.id))
  if not item then return http.error_page(404, "That file doesn't exist.") end
  if not can_change(req, item) then return http.error_page(403, "You can only delete your own uploads.") end
  media.delete(req.site, req.db, item.id)
  log.add(req.db, req, "media.deleted", item.path)
  session.flash(req, "ok", "File deleted.")
  return http.new_response():redirect(req:url_for("/admin/media"))
end

-- For the editor's "insert image" dialog.
local function json_list(req)
  local out = {}
  for _, it in ipairs(media.list(req.db, req.query.show == "all" and nil or "image")) do
    out[#out + 1] = { id = it.id, name = it.path:match("[^/]+$"), path = "/media/" .. it.path, url = media.url(req, it), alt = it.alt,
      image = media.is_image(it), width = it.width, height = it.height }
  end
  local res = http.new_response():json({ items = out })
  res:set_header("Cache-Control", "no-store")
  return res
end

function admin_media.register(r)
  r:get("/admin/media", list, { name = "media", auth = "media.upload" })
  r:get("/admin/media.json", json_list, { auth = "media.upload" })
  r:post("/admin/media/upload", upload, { auth = "media.upload" })
  r:get("/admin/media/:id", show, { auth = "media.upload" })
  r:post("/admin/media/:id", save, { auth = "media.upload" })
  r:post("/admin/media/:id/delete", delete, { auth = "media.upload" })
end

return admin_media
