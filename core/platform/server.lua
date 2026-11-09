-- WordCore — server mode: the built-in web server (your PC, a tunnel, a VPS).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- One process, many connections: sockets are non-blocking, each connection is
-- a coroutine, and a poll() loop resumes whichever ones can make progress. An
-- idle or slow client therefore never holds up anyone else. Pages are built
-- one at a time (that's fast); only the network waiting is overlapped.

local native = require("wc.native")
local http = require("wc.platform.http")
local address = require("wc.platform.address")
local site_mod = require("wc.platform.site")
local app = require("wc.platform.app")

local server = {}

local FIRST_REQUEST_TIMEOUT = 15   -- seconds to send a complete request
local KEEPALIVE_TIMEOUT = 5        -- seconds an idle keep-alive connection may wait
local MAX_REQUESTS_PER_CONN = 100
local MAX_CONNECTIONS = 512

local function log(fmt, ...)
  io.stdout:write(os.date("%H:%M:%S "), fmt:format(...), "\n")
  io.stdout:flush()
end

---------------------------------------------------------------- connection I/O
-- These run inside a connection's coroutine and yield "r" / "w" while waiting.

local Conn = {}
Conn.__index = Conn

function Conn:recv(max)
  while true do
    local data, err = native.sock_recv(self.fd, max or 16384)
    if data then return data end
    if err ~= "again" then return nil, err end
    coroutine.yield("r")
  end
end

function Conn:send(data)
  local i = 1
  while i <= #data do
    local nexti, err = native.sock_send(self.fd, data, i)
    if not nexti then return nil, err end
    i = nexti
    if err == "again" then coroutine.yield("w") end
  end
  return true
end

-- After an error response, read and discard what the client is still sending
-- for a moment, so closing doesn't reset the connection before it reads our reply.
function Conn:drain()
  self.timeout = 1
  for _ = 1, 64 do
    local data = self:recv(65536)
    if not data then return end
  end
end

---------------------------------------------------------------- HTTP parsing

-- Read one request. `buf` holds bytes already received (pipelining).
-- Returns fields, leftover | nil, status_or_nil
local function read_request(conn, buf)
  local head_end
  while true do
    head_end = buf:find("\r\n\r\n", 1, true)
    if head_end then break end
    if #buf > http.MAX_HEADER_BYTES then return nil, 431 end
    local data = conn:recv(16384)
    if not data then return nil, nil end -- closed or timed out: nothing to answer
    buf = buf .. data
  end
  if head_end > http.MAX_HEADER_BYTES then return nil, 431 end
  conn.timeout = FIRST_REQUEST_TIMEOUT
  local head = buf:sub(1, head_end - 1)
  local rest = buf:sub(head_end + 4)

  local request_line, header_block = head:match("^([^\r\n]*)\r?\n?(.*)$")
  local method, target, version = request_line:match("^(%u+) (%S+) HTTP/(%d%.%d)$")
  if not method then return nil, 400 end
  if #target > 8192 then return nil, 414 end

  local headers = {}
  for line in (header_block .. "\r\n"):gmatch("(.-)\r\n") do
    if line ~= "" then
      local k, v = line:match("^([^:%s]+):%s*(.-)%s*$")
      if not k then return nil, 400 end
      k = k:lower()
      if headers[k] then
        if k == "host" or k == "content-length" then return nil, 400 end
        headers[k] = headers[k] .. ", " .. v
      else
        headers[k] = v
      end
    end
  end
  if version == "1.1" and not headers["host"] then return nil, 400 end

  if headers["transfer-encoding"] then return nil, 501 end
  local cl = headers["content-length"] or "0"
  if not cl:match("^%d+$") then return nil, 400 end
  local length = tonumber(cl)
  if length > http.MAX_BODY_BYTES then return nil, 413 end
  while #rest < length do
    local data = conn:recv(math.min(1048576, length - #rest))
    if not data then return nil, nil end
    rest = rest .. data
  end

  return {
    method = method,
    target = target,
    http_version = version,
    headers = headers,
    body = rest:sub(1, length),
  }, rest:sub(length + 1)
end

local function wants_keepalive(fields)
  local c = (fields.headers["connection"] or ""):lower()
  if fields.http_version == "1.0" then return c:find("keep%-alive") ~= nil end
  return not c:find("close")
end

local function serialize(res, keepalive)
  local body = res.body or ""
  local out = { ("HTTP/1.1 %d %s\r\n"):format(res.status, http.status_text[res.status] or "") }
  local has_length = false
  for name, value in res:each_header() do
    local lname = name:lower()
    if lname == "content-length" then has_length = true end
    if lname ~= "connection" then out[#out + 1] = name .. ": " .. tostring(value) .. "\r\n" end
  end
  if not has_length then out[#out + 1] = "Content-Length: " .. #body .. "\r\n" end
  out[#out + 1] = keepalive and "Connection: keep-alive\r\n\r\n" or "Connection: close\r\n\r\n"
  if not res.head_only then out[#out + 1] = body end
  return table.concat(out)
end

---------------------------------------------------------------- one connection

local function serve_connection(conn, ctx)
  local buf = ""
  for n = 1, MAX_REQUESTS_PER_CONN do
    conn.timeout = n == 1 and FIRST_REQUEST_TIMEOUT or KEEPALIVE_TIMEOUT
    local fields, rest_or_status = read_request(conn, buf)
    if not fields then
      local status = rest_or_status
      if status then
        local res = http.error_page(status, "The request couldn't be read.")
        res:apply_defaults()
        conn:send(serialize(res, false))
        log("- %s bad request %d", conn.ip, status)
        conn:drain()
      end
      return
    end
    buf = rest_or_status

    local started = native.now()
    fields.mode = "server"
    local req = http.new_request(fields)
    address.resolve(req, { mode = "server", trust_proxy = ctx.trust_proxy, base_path = ctx.base_path, socket_ip = conn.ip })
    req.started = started
    local res = app.handle(req, ctx.app_ctx)
    local keepalive = n < MAX_REQUESTS_PER_CONN and wants_keepalive(fields)
    local ok = conn:send(serialize(res, keepalive))
    log("%s %s %d %.1fms", req.method, req.raw_path, res.status, (native.now() - started) * 1000)
    if not ok or not keepalive then return end
  end
end

---------------------------------------------------------------- main loop

-- Open a URL in the default browser. The URL is built by us (host, port, code
-- from a fixed alphabet), never from outside input.
function server.open_browser(url)
  if not url:match("^http://[%w%.%-%[%]:]+/[%w/%?=%-]*$") then return end
  local os_name = native.platform()
  if os_name == "windows" then
    os.execute('start "" "' .. url .. '"')
  elseif os_name == "macos" then
    os.execute("open '" .. url .. "' >/dev/null 2>&1 &")
  else
    os.execute("xdg-open '" .. url .. "' >/dev/null 2>&1 &")
  end
end

function server.run(opts)
  local site, err = site_mod.open(opts.site_dir)
  if not site then
    io.stderr:write("wordcore: ", err, "\n")
    return 1
  end
  local ctx = {
    trust_proxy = opts.trust_proxy or site.config.trust_proxy == true,
    base_path = site.config.base_path,
    app_ctx = { site = site, mode = "server", version = opts.version },
  }

  local lfd, lerr = native.tcp_listen(opts.host, opts.port, 128)
  if not lfd and opts.find_free_port then
    for p = opts.port + 1, opts.port + 20 do
      lfd, lerr = native.tcp_listen(opts.host, p, 128)
      if lfd then opts.port = p break end
    end
  end
  if not lfd then
    io.stderr:write("wordcore: ", lerr, "\n")
    if lerr:find("in use") or lerr:find("10048") then
      io.stderr:write("Another program is using port ", tostring(opts.port), ". Try: wordcore serve --port ", tostring(opts.port + 1), "\n")
    end
    return 1
  end
  native.sock_nonblock(lfd, true)

  local shown_host = opts.host
  if shown_host == "0.0.0.0" or shown_host == "::" then shown_host = "localhost" end
  io.stdout:write(("WordCore %s\n"):format(opts.version))
  io.stdout:write(("Site folder: %s\n"):format(site.dir))
  io.stdout:write(("Running at http://%s:%d/%s\n"):format(shown_host, opts.port, ctx.trust_proxy and "  (trusting proxy headers)" or ""))
  local open_url = ("http://%s:%d/"):format(shown_host, opts.port)
  if not require("wc.people.users").has_owner(site.db) then
    local code = require("wc.setup.code").get(site)
    open_url = ("http://%s:%d/setup?code=%s"):format(shown_host, opts.port, code)
    io.stdout:write("\nFirst-time setup: ", open_url, "\n(setup code ", code, ")\n\n")
  end
  io.stdout:write("Press Ctrl+C to stop.\n")
  io.stdout:flush()
  if opts.open_browser then server.open_browser(open_url) end

  local conns = {}

  local function close(c)
    if not c.closed then
      c.closed = true
      native.sock_close(c.fd)
    end
  end

  local function step(c)
    local ok, want = coroutine.resume(c.co)
    if not ok then
      io.stderr:write("wordcore: connection error: ", tostring(want), "\n")
      close(c)
    elseif coroutine.status(c.co) == "dead" then
      close(c)
    else
      c.want = want
      c.deadline = native.now() + (c.timeout or FIRST_REQUEST_TIMEOUT)
    end
  end

  while true do
    local fds, evs = { lfd }, { "r" }
    local now = native.now()
    local wait_ms = 1000
    for _, c in ipairs(conns) do
      fds[#fds + 1] = c.fd
      evs[#evs + 1] = c.want
      local left = math.max(0, math.ceil((c.deadline - now) * 1000))
      if left < wait_ms then wait_ms = left end
    end

    local rev = native.poll(fds, evs, wait_ms)
    if rev then
      -- existing connections that can make progress
      for i, c in ipairs(conns) do
        if rev[i + 1] ~= "" and not c.closed then step(c) end
      end
      -- new connections
      if rev[1] ~= "" then
        for _ = 1, 64 do
          if #conns >= MAX_CONNECTIONS then break end
          local cfd, ip = native.tcp_accept(lfd)
          if not cfd then break end
          native.sock_nonblock(cfd, true)
          local c = setmetatable({ fd = cfd, ip = ip, timeout = FIRST_REQUEST_TIMEOUT }, Conn)
          c.co = coroutine.create(function() serve_connection(c, ctx) end)
          conns[#conns + 1] = c
          step(c)
        end
      end
    end

    -- drop finished and timed-out connections
    now = native.now()
    local alive = {}
    for _, c in ipairs(conns) do
      if not c.closed and c.deadline and now > c.deadline then close(c) end
      if not c.closed then alive[#alive + 1] = c end
    end
    conns = alive
  end
end

return server
