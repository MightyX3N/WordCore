-- Compile every core Lua file (catches syntax errors and Lua 5.5 rules such as read-only loop variables).
local root = ...
local native = require("wc.native")
local bad = 0
local function walk(dir)
  for _, name in ipairs(native.listdir(dir)) do
    local p = dir .. "/" .. name
    if native.stat(p) == "dir" then walk(p)
    elseif name:match("%.lua$") then
      local f = assert(io.open(p, "rb")); local src = f:read("a"); f:close()
      local ok, err = load(src, "@" .. p, "t")
      if not ok then bad = bad + 1; io.stderr:write(err, "\n") end
    end
  end
end
walk(root or "core")
io.write(bad == 0 and "all core files compile\n" or (bad .. " file(s) failed\n"))
return bad == 0 and 0 or 1
