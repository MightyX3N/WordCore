-- WordCore — turn a request into a response (shared by every run mode).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local http = require("wc.platform.http")

local app = {}

-- Phase 0: one built-in "hello" application that proves the program, the
-- run modes, the database and address detection work on a given host.
local handler = require("wc.app.hello")

-- ctx: { site, mode, version }
function app.handle(req, ctx)
  local ok, res = xpcall(handler, debug.traceback, req, ctx)
  if not ok then
    io.stderr:write("wordcore: error handling ", req.method or "?", " ", req.raw_path or "?", "\n", tostring(res), "\n")
    res = http.error_page(500, "Something went wrong while building this page. The details are in the server log.")
  elseif type(res) ~= "table" or getmetatable(res) == nil then
    io.stderr:write("wordcore: handler returned no response for ", req.raw_path or "?", "\n")
    res = http.error_page(500, "This page didn't produce a response.")
  end
  res:apply_defaults()
  if req.method == "HEAD" then res.head_only = true end
  return res
end

return app
