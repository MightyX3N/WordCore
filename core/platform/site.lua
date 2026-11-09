-- WordCore — the site folder: where it is, its config, its database.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local native = require("wc.native")
local path = require("wc.lib.path")
local json = require("wc.lib.json")
local db = require("wc.platform.db")

local site = {}

-- Folder that holds the program.
function site.program_dir()
  local exe = native.exe_path()
  if exe then return path.dirname(exe) end
  return "."
end

-- Find the site folder: explicit option, WORDCORE_SITE, or "site" next to the program.
function site.locate(explicit)
  local dir = explicit
  if not dir or dir == "" then dir = os.getenv("WORDCORE_SITE") end
  if not dir or dir == "" then dir = path.join(site.program_dir(), "site") end
  return dir
end

-- Open (and create if needed) the site folder. Returns a site object:
--   { dir, config, db, db_path }
function site.open(explicit_dir)
  local dir = site.locate(explicit_dir)
  local ok, err = path.mkdirs(dir)
  if not ok then return nil, "cannot create site folder " .. dir .. ": " .. tostring(err) end

  local config = {}
  local raw = path.read(path.join(dir, "config.json"))
  if raw then
    local parsed, perr = json.decode(raw)
    if not parsed then return nil, "site/config.json: " .. perr end
    config = parsed
  end

  local db_path = path.join(dir, "site.db")
  local conn, derr = db.open(db_path)
  if not conn then return nil, "cannot open " .. db_path .. ": " .. tostring(derr) end

  return setmetatable({ dir = dir, config = config, db = conn, db_path = db_path }, { __index = site })
end

function site:close()
  if self.db then self.db:close() self.db = nil end
end

return site
