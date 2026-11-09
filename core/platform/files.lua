-- WordCore — read the core's own files (embedded in the program, or from
-- WORDCORE_CORE_DIR while developing).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local embedded = require("wc.embedded")

local files = {}

local dev_dir = os.getenv("WORDCORE_CORE_DIR")
if dev_dir == "" then dev_dir = nil end
files.dev = dev_dir ~= nil

-- read("views/admin.etlua") -> contents | nil
function files.read(rel)
  if rel:find("%.%.") then return nil end
  if dev_dir then
    if rel == "NOTICES.txt" then
      local f = io.open(dev_dir .. "/../runtime/vendor/NOTICES.txt", "rb")
      if f then local d = f:read("a") f:close() return d end
    end
    local f = io.open(dev_dir .. "/" .. rel, "rb")
    if not f then return nil end
    local data = f:read("a")
    f:close()
    return data
  end
  return embedded.get("core/" .. rel)
end

return files
