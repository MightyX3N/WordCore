-- WordCore — filesystem path helpers.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local native = require("wc.native")

local path = {}

path.sep = native.sep

-- Join path parts with "/" (accepted by Windows too).
function path.join(...)
  local parts = {}
  for i = 1, select("#", ...) do
    local p = select(i, ...)
    if p and p ~= "" then
      if #parts > 0 then p = p:gsub("^[/\\]+", "") end
      parts[#parts + 1] = (i < select("#", ...)) and p:gsub("[/\\]+$", "") or p
    end
  end
  return table.concat(parts, "/")
end

-- Directory part of a path ("/a/b/c" -> "/a/b", "c" -> ".").
function path.dirname(p)
  local d = p:match("^(.*)[/\\][^/\\]*$")
  if d == nil then return "." end
  if d == "" then return "/" end
  return d
end

function path.basename(p)
  return p:match("([^/\\]*)$")
end

function path.exists(p)
  return native.stat(p) ~= nil
end

function path.is_dir(p)
  return native.stat(p) == "dir"
end

-- Create a directory and any missing parents.
function path.mkdirs(p)
  if path.is_dir(p) then return true end
  local parent = path.dirname(p)
  if parent ~= p and parent ~= "." and parent ~= "/" and not parent:match("^%a:$") then
    local ok, err = path.mkdirs(parent)
    if not ok then return nil, err end
  end
  return native.mkdir(p)
end

-- Read a whole file, or nil if it can't be read.
function path.read(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

-- Write a whole file via a temporary file + rename, so readers never see half a file.
function path.write(p, data)
  local tmp = p .. ".tmp" .. tostring(native.getpid())
  local f, err = io.open(tmp, "wb")
  if not f then return nil, err end
  local ok, werr = f:write(data)
  f:close()
  if not ok then os.remove(tmp) return nil, werr end
  if native.os == "windows" then os.remove(p) end -- Windows can't rename over an existing file
  local rok, rerr = os.rename(tmp, p)
  if not rok then os.remove(tmp) return nil, rerr end
  return true
end

return path
