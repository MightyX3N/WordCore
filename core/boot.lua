-- WordCore — program entry. Embedded in the `wordcore` program and run by main.c.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local arg = ...

---------------------------------------------------------------------------
-- Module loading: core modules come from inside the program (or from
-- WORDCORE_CORE_DIR while developing). Lua's own file and C-library loaders
-- are removed: nothing is loaded from disk by name, and there are no C addons.
---------------------------------------------------------------------------
local embedded = require("wc.embedded")
local dev_dir = os.getenv("WORDCORE_CORE_DIR")
if dev_dir == "" then dev_dir = nil end

local function core_source(file)
  if dev_dir then
    local f = io.open(dev_dir .. "/" .. file, "rb")
    if not f then return nil end
    local src = f:read("a")
    f:close()
    return src
  end
  return embedded.get("core/" .. file)
end

local function core_searcher(name)
  if name:sub(1, 3) ~= "wc." then
    return "\n\tnot a WordCore module"
  end
  local file = name:sub(4):gsub("%.", "/") .. ".lua"
  local src = core_source(file)
  if not src then
    return "\n\tno core module '" .. file .. "'"
  end
  local chunk, err = load(src, "@core/" .. file, "t")
  if not chunk then error(err, 0) end
  return chunk, file
end

package.searchers = { package.searchers[1], core_searcher }
package.path = ""
package.cpath = ""
package.loadlib = nil

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local native = require("wc.native")
local version = WORDCORE_VERSION or "dev"

local function usage()
  io.write(([[
WordCore %s

Usage:
  wordcore                      start the local server (same as `serve`)
  wordcore serve [options]      run the built-in web server
      --host <addr>             address to listen on (default 127.0.0.1)
      --port <n>                port (default 8080)
      --site <dir>              site folder (default: "site" next to the program)
      --trust-proxy             trust X-Forwarded-* headers from a tunnel/proxy
      --open yes                open the site in your browser once it's running
  wordcore cgi                  handle one CGI request (used by .htaccess on shared hosting;
                                chosen automatically when run by a web server)
  wordcore version              print version information
  wordcore run <file.lua> ...   run a Lua script with the core available (development)
]]):format(version))
end

local function parse_options(list, first)
  local opts = {}
  local i = first
  while i <= #list do
    local a = list[i]
    if a == "--trust-proxy" then
      opts.trust_proxy = true
    elseif a:sub(1, 2) == "--" then
      local key = a:sub(3):gsub("-", "_")
      local val = list[i + 1]
      if val == nil then error("missing value for " .. a, 0) end
      opts[key] = val
      i = i + 1
    else
      opts[#opts + 1] = a
    end
    i = i + 1
  end
  return opts
end

-- A web server running us as CGI sets GATEWAY_INTERFACE. In that case the
-- command line is ignored completely: some servers pass parts of the query
-- string as arguments, and visitors must never be able to choose a command.
if os.getenv("GATEWAY_INTERFACE") then
  return require("wc.platform.cgi").run({ version = version })
end

local cmd = arg[1] or "serve"

if cmd == "serve" then
  local opts = parse_options(arg, 2)
  local started_plain = arg[1] == nil -- double-clicked, or run with no arguments
  local code = require("wc.platform.server").run({
    version = version,
    host = opts.host or "127.0.0.1",
    port = tonumber(opts.port or "8080"),
    find_free_port = opts.port == nil,
    open_browser = started_plain or opts.open == "yes",
    site_dir = opts.site,
    trust_proxy = opts.trust_proxy,
  })
  -- A double-clicked window closes as soon as we exit; keep errors readable.
  if code ~= 0 and started_plain and native.os == "windows" then
    io.stderr:write("\nPress Enter to close this window.\n")
    io.read("l")
  end
  return code
elseif cmd == "cgi" then
  return require("wc.platform.cgi").run({ version = version })
elseif cmd == "version" or cmd == "--version" or cmd == "-v" then
  local sqlite = require("wc.sqlite")
  local os_name, arch = native.platform()
  io.write(("WordCore %s\n%s, SQLite %s, %s %s\n"):format(version, LUA_RELEASE or _VERSION, sqlite.version(), os_name, arch))
  return 0
elseif cmd == "run" then
  local file = arg[2]
  if not file then usage() return 2 end
  local chunk, err = loadfile(file, "t")
  if not chunk then io.stderr:write(err, "\n") return 1 end
  local script_args = table.move(arg, 3, #arg, 1, {})
  local result = chunk(table.unpack(script_args))
  return math.type(result) == "integer" and result or 0
elseif cmd == "help" or cmd == "--help" or cmd == "-h" then
  usage()
  return 0
else
  io.stderr:write("wordcore: unknown command '", tostring(cmd), "'\n\n")
  usage()
  return 2
end
