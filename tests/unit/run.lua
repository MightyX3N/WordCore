-- WordCore unit tests. Run with:  wordcore run tests/unit/run.lua
-- (uses the core embedded in the program, or WORDCORE_CORE_DIR=core)

local passed, failed = 0, 0
local current = ""

local function describe(name) current = name end

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write("FAIL [", current, "] ", msg or "assertion failed", "\n")
  end
end

local function eq(a, b, msg)
  check(a == b, (msg or "") .. ("  expected %q, got %q"):format(tostring(b), tostring(a)))
end

---------------------------------------------------------------- json
describe("json")
local json = require("wc.lib.json")
eq(json.encode({ 1, 2, 3 }), "[1,2,3]")
eq(json.encode({ a = 1, b = "x" }), '{"a":1,"b":"x"}')
eq(json.encode({}), "{}")
eq(json.encode(json.array({})), "[]")
eq(json.encode("a\"b\\c\n\1"), '"a\\"b\\\\c\\n\\u0001"')
eq(json.encode(1.5), "1.5")
eq(json.encode(0.1), "0.1")
eq(json.encode(10), "10")
eq(json.encode(json.null), "null")
eq(json.encode(true), "true")
eq(json.encode(0 / 0), "null")
local t = json.decode('{"a":[1,2,{"b":null}],"c":"\\u00e6\\ud83d\\ude00","d":-1.5e2,"e":true}')
eq(t.a[1], 1)
check(math.type(t.a[1]) == "integer", "integers stay integers")
eq(t.a[3].b, json.null)
eq(t.c, "æ😀")
eq(t.d, -150.0)
eq(t.e, true)
local v, err = json.decode("{bad}")
check(v == nil and err:find("line 1"), "bad json reports position")
check(json.decode("[1,2] x") == nil, "trailing junk rejected")
check(json.decode("01") == nil, "leading zero rejected")
local deep = string.rep("[", 300) .. string.rep("]", 300)
check(json.decode(deep) == nil, "deep nesting rejected")
local rt = json.decode(json.encode({ list = { "x", "y" }, n = 3, s = "ø" }))
eq(rt.list[2], "y") eq(rt.n, 3) eq(rt.s, "ø")
local ok = pcall(json.encode, (function() local c = {} c.self = c return c end)())
check(not ok, "circular reference errors")

---------------------------------------------------------------- http helpers
describe("http")
local http = require("wc.platform.http")
eq(http.clean_path("/a/b/../c"), "/a/c")
eq(http.clean_path("/../../etc/passwd"), "/etc/passwd")
eq(http.clean_path("//a///b/"), "/a/b/")
eq(http.clean_path("/a/%2e%2e/b"), "/b")
eq(http.clean_path(""), "/")
check(http.clean_path("/a%00b") == nil, "NUL in path rejected")
local q = http.parse_query("a=1&b=x+y&c=%26&d&a=2")
eq(q.a, "2") eq(q.b, "x y") eq(q.c, "&") eq(q.d, "")
eq(http.url_encode("a b&ø"), "a%20b%26%C3%B8")
local req = http.new_request({ method = "GET", target = "/x/y?z=1#frag" })
eq(req.raw_path, "/x/y") eq(req.query.z, "1")

---------------------------------------------------------------- address
describe("address")
local address = require("wc.platform.address")
local function cgi_req(env, headers)
  local r = http.new_request({ method = "GET", target = env.REQUEST_URI, headers = headers or {} })
  return address.resolve(r, { mode = "cgi", env = env, trust_proxy = env._trust })
end

-- subfolder install through .htaccess rewrite
local r = cgi_req({ REQUEST_URI = "/wctest/blog/post?x=1", SCRIPT_NAME = "/wctest/wordcore.cgi", HTTP_HOST = "example.com", HTTPS = "on", REMOTE_ADDR = "1.2.3.4" }, { host = "example.com" })
eq(r.base_path, "/wctest") eq(r.path, "/blog/post") eq(r.scheme, "https")
eq(r.public_url, "https://example.com/wctest") eq(r.client_ip, "1.2.3.4")
eq(r:url_for("/a"), "/wctest/a")

-- subfolder root URL
r = cgi_req({ REQUEST_URI = "/wctest/", SCRIPT_NAME = "/wctest/wordcore.cgi", HTTP_HOST = "example.com" })
eq(r.path, "/") eq(r.base_path, "/wctest")
r = cgi_req({ REQUEST_URI = "/wctest", SCRIPT_NAME = "/wctest/wordcore.cgi", HTTP_HOST = "example.com" })
eq(r.path, "/")

-- web root install
r = cgi_req({ REQUEST_URI = "/about", SCRIPT_NAME = "/wordcore.cgi", HTTP_HOST = "example.com" })
eq(r.base_path, "") eq(r.path, "/about") eq(r.scheme, "http")

-- called directly without rewrite
r = cgi_req({ REQUEST_URI = "/wctest/wordcore.cgi/echo", SCRIPT_NAME = "/wctest/wordcore.cgi", HTTP_HOST = "example.com" })
eq(r.base_path, "/wctest/wordcore.cgi") eq(r.path, "/echo")

-- similar-looking folder names don't confuse the prefix match
r = cgi_req({ REQUEST_URI = "/wctester/x", SCRIPT_NAME = "/wctest/wordcore.cgi", HTTP_HOST = "example.com" })
eq(r.path, "/wctester/x")

-- proxy headers ignored unless trusted
r = cgi_req({ REQUEST_URI = "/", SCRIPT_NAME = "/wordcore.cgi", HTTP_HOST = "local:8080", REMOTE_ADDR = "127.0.0.1" },
  { host = "local:8080", ["x-forwarded-proto"] = "https", ["x-forwarded-host"] = "evil.example", ["x-forwarded-for"] = "9.9.9.9" })
eq(r.scheme, "http") eq(r.host, "local:8080") eq(r.client_ip, "127.0.0.1")
eq(#r.proxy.seen, 3) eq(r.proxy.trusted, false)

-- ...and used when trusted
r = cgi_req({ _trust = true, REQUEST_URI = "/", SCRIPT_NAME = "/wordcore.cgi", HTTP_HOST = "local:8080", REMOTE_ADDR = "127.0.0.1" },
  { ["x-forwarded-proto"] = "https", ["x-forwarded-host"] = "preview.example, other", ["x-forwarded-for"] = "9.9.9.9, 10.0.0.1" })
eq(r.scheme, "https") eq(r.host, "preview.example") eq(r.client_ip, "9.9.9.9")
eq(r.public_url, "https://preview.example")

-- RFC 7239 Forwarded header
r = cgi_req({ _trust = true, REQUEST_URI = "/", SCRIPT_NAME = "/wordcore.cgi", HTTP_HOST = "x" },
  { forwarded = 'for="[2001:db8::1]:4711";proto=https;host=site.example' })
eq(r.scheme, "https") eq(r.host, "site.example") eq(r.client_ip, "2001:db8::1")

-- bad Host header falls back safely
r = cgi_req({ REQUEST_URI = "/", SCRIPT_NAME = "/wordcore.cgi", HTTP_HOST = "evil.com/<script>" })
eq(r.host, "localhost")

-- server mode with a configured base path
local sreq = http.new_request({ method = "GET", target = "/blog/x", headers = { host = "127.0.0.1:8080" } })
address.resolve(sreq, { mode = "server", base_path = "/blog/", socket_ip = "127.0.0.1" })
eq(sreq.base_path, "/blog") eq(sreq.path, "/x") eq(sreq.public_url, "http://127.0.0.1:8080/blog")

---------------------------------------------------------------- db
describe("db")
local db = require("wc.platform.db")
local native = require("wc.native")
local tmp = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp") .. "/wc-unit-" .. native.getpid() .. ".db"
local conn = assert(db.open(tmp))
eq(conn.journal_mode, "wal")
conn:migrate("t", { "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, n REAL)" })
conn:migrate("t", { "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, n REAL)" }) -- again: no-op
local changes, id = conn:run("INSERT INTO items (name, n) VALUES (?, ?)", "a", 1.5)
eq(changes, 1) eq(id, 1)
conn:run("INSERT INTO items (name, n) VALUES (:name, :n)", { name = "b", n = 2 })
local rows = conn:query("SELECT * FROM items ORDER BY id")
eq(#rows, 2) eq(rows[2].name, "b") eq(rows[1].n, 1.5)
eq(conn:first("SELECT name FROM items WHERE id = ?", 2).name, "b")
check(conn:first("SELECT name FROM items WHERE id = ?", 99) == nil, "missing row is nil")
local okt = pcall(conn.transaction, conn, function(c)
  c:run("INSERT INTO items (name) VALUES (?)", "c")
  error("boom")
end)
check(not okt, "transaction error propagates")
eq(conn:first("SELECT COUNT(*) AS n FROM items").n, 2, "rolled back")
local okq = pcall(conn.query, conn, "SELECT * FROM no_such_table")
check(not okq, "bad SQL raises")
eq(conn:first("SELECT ? AS s", "with 'quotes' and \0 nul").s, "with 'quotes' and \0 nul", "binary-safe text")
conn:close()
os.remove(tmp) os.remove(tmp .. "-wal") os.remove(tmp .. "-shm")

---------------------------------------------------------------- native
describe("native")
eq(#native.random_bytes(32), 32)
check(native.random_bytes(16) ~= native.random_bytes(16), "random differs")
check(native.now() > 0, "clock")
check(type(native.environ()) == "table", "environ")
check(native.exe_path() ~= nil, "exe path")

---------------------------------------------------------------- done
io.write(("%d passed, %d failed\n"):format(passed, failed))
return failed == 0 and 0 or 1
