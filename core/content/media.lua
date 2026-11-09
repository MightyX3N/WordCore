-- WordCore — media library: uploads stored in site/media, served by WordCore.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Files keep a readable name (site/media/2026/11/team-photo.jpg) and are
-- served at /media/2026/11/team-photo.jpg. The type is decided by the file's
-- content, never its name.

local native = require("wc.native")
local path = require("wc.lib.path")
local slug = require("wc.lib.slug")
local filetype = require("wc.lib.filetype")
local http = require("wc.platform.http")

local media = {}

media.MAX_BYTES = 32 * 1024 * 1024

function media.migrate(db)
  db:migrate("content.media", {
    [[CREATE TABLE wc_media (
        id INTEGER PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        original_name TEXT NOT NULL,
        mime TEXT NOT NULL,
        size INTEGER NOT NULL,
        width INTEGER,
        height INTEGER,
        alt TEXT NOT NULL DEFAULT '',
        user_id INTEGER,
        created_at INTEGER NOT NULL DEFAULT (unixepoch()))]],
  })
end

local function dir(site) return path.join(site.dir, "media") end

function media.url(req, item) return req:url_for("/media/" .. item.path) end

-- Save an uploaded file. Returns item id or nil + message.
function media.save(site, db, file, user_id)
  if #file.data == 0 then return nil, ("%s is empty."):format(file.filename) end
  if #file.data > media.MAX_BYTES then return nil, ("%s is larger than 32 MB."):format(file.filename) end
  local kind = filetype.detect(file.data)
  if not kind then
    return nil, ("%s isn't a supported file type (images, PDF, MP4/WebM video, MP3/OGG audio, ZIP)."):format(file.filename)
  end
  local base = slug.make((file.filename:gsub("%.[^.]*$", "")), 60)
  if base == "" then base = "file" end
  local sub = os.date("!%Y/%m")
  local folder = path.join(dir(site), sub)
  local ok, err = path.mkdirs(folder)
  if not ok then return nil, "Can't create the media folder: " .. tostring(err) end
  local name = base .. "." .. kind.ext
  local n = 2
  while path.exists(path.join(folder, name)) or db:first("SELECT 1 AS x FROM wc_media WHERE path = ?", sub .. "/" .. name) do
    name = ("%s-%d.%s"):format(base, n, kind.ext)
    n = n + 1
  end
  local wok, werr = path.write(path.join(folder, name), file.data)
  if not wok then return nil, "Couldn't save the file: " .. tostring(werr) end
  local w, h
  if kind.image then w, h = filetype.image_size(file.data, kind.ext) end
  local alt = (file.filename:gsub("%.[^.]*$", ""):gsub("[_%-]+", " "))
  local _, id = db:run([[INSERT INTO wc_media (path, original_name, mime, size, width, height, alt, user_id)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
    sub .. "/" .. name, file.filename:sub(1, 200), kind.mime, #file.data, w, h, alt:sub(1, 200), user_id)
  return id
end

function media.get(db, id) return db:first("SELECT * FROM wc_media WHERE id = ?", id) end

function media.list(db, filter)
  if filter == "image" then
    return db:query("SELECT * FROM wc_media WHERE mime LIKE 'image/%' ORDER BY id DESC")
  end
  return db:query("SELECT * FROM wc_media ORDER BY id DESC")
end

function media.stats(db)
  local r = db:first("SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes FROM wc_media")
  return r.n, r.bytes
end

-- Pages that mention the file.
function media.used_in(db, item)
  return db:query("SELECT id, title FROM wc_pages WHERE instr(body, ?) > 0 ORDER BY title", "/media/" .. item.path)
end

function media.delete(site, db, id)
  local item = media.get(db, id)
  if not item then return end
  os.remove(path.join(dir(site), item.path))
  db:run("DELETE FROM wc_media WHERE id = ?", id)
end

function media.is_image(item) return item.mime:sub(1, 6) == "image/" end

-- GET /media/<path>
function media.serve(req, rest)
  if not rest or rest:find("%.%.") or not rest:match("^[%w/%._%-]+$") then return http.error_page(404, "No such file.") end
  local item = req.db:first("SELECT * FROM wc_media WHERE path = ?", rest)
  if not item then return http.error_page(404, "No such file.") end
  local data = path.read(path.join(dir(req.site), item.path))
  if not data then return http.error_page(404, "The file is missing from the media folder.") end
  local res = http.new_response(200)
  res:set_header("Content-Type", item.mime)
  res:set_header("Cache-Control", "public, max-age=31536000, immutable")
  local etag = '"m' .. item.id .. "-" .. item.size .. '"'
  res:set_header("ETag", etag)
  if not (media.is_image(item) or item.mime:find("^video/") or item.mime:find("^audio/") or item.mime == "application/pdf") then
    res:set_header("Content-Disposition", ('attachment; filename="%s"'):format(item.path:match("[^/]+$")))
  end
  res:set_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox")
  if req.headers["if-none-match"] == etag then
    res.status = 304
    return res
  end
  res.body = data
  return res
end

media.native = native
return media
