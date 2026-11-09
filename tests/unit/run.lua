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

---------------------------------------------------------------- base64 + crypto
describe("crypto")
local base64 = require("wc.lib.base64")
eq(base64.encode("hello"), "aGVsbG8=") eq(base64.decode("aGVsbG8="), "hello")
eq(base64.url_encode("\255\254\253"), "__79") eq(base64.url_decode("__79"), "\255\254\253")
eq(base64.encode_nopad("ab"), "YWI")
check(base64.decode("!!") == nil, "bad base64 rejected")
local crypto = require("wc.lib.crypto")
local raw = require("wc.crypto")
-- reference value from argon2-cffi (RFC 9106 implementation)
eq(crypto.hex(raw.argon2id("correct horse", "saltsaltsaltsalt", 19456, 2, 1, 32)),
   "01dc1e04bc1c7e59cd5f61d55bc8b532dbbb7ebae7e0a8bb87fad8486b94ec8b", "argon2id matches reference")
eq(crypto.blake2b_hex("abc", 64):sub(1, 16), "ba80a53f981c4d0d", "blake2b matches reference")
local phc = crypto.hash_password("s3cret-password")
check(phc:match("^%$argon2id%$v=19%$m=19456,t=2,p=1%$"), "PHC format")
check(crypto.verify_password("s3cret-password", phc), "verify right password")
check(not crypto.verify_password("s3cret-passwore", phc), "reject wrong password")
check(not crypto.verify_password("x", "garbage"), "reject garbage hash")
check(crypto.hash_password("same") ~= crypto.hash_password("same"), "salted")
local ok1, rehash = crypto.verify_password("pw-for-rehash", "$argon2id$v=19$m=8192,t=1,p=1$" ..
  base64.encode_nopad("0123456789abcdef") .. "$" .. base64.encode_nopad(raw.argon2id("pw-for-rehash", "0123456789abcdef", 8192, 1, 1, 32)))
check(ok1 and rehash, "old parameters verify and ask for rehash")
check(crypto.equal("abc", "abc") and not crypto.equal("abc", "abd") and not crypto.equal("abc", "ab"), "constant-time equal")
eq(#crypto.token(32), 43)

---------------------------------------------------------------- router
describe("router")
local router = require("wc.platform.router")
local r = router.new()
r:get("/", function() return "home" end, { name = "home" })
r:get("/admin/users/:id", function() end, { name = "user" })
r:post("/admin/users/:id", function() end)
r:get("/files/*rest", function() end, { name = "files" })
local rt, params = r:match("GET", "/admin/users/42")
eq(rt.name, "user") eq(params.id, "42")
local _, _, allowed = r:match("DELETE", "/admin/users/42")
eq(table.concat(allowed, ","), "GET,POST")
check(r:match("GET", "/admin/users") == nil, "missing segment doesn't match")
check(r:match("GET", "/admin/users/1/2") == nil, "extra segment doesn't match")
eq(select(2, r:match("GET", "/files/a/b/c.txt")).rest, "a/b/c.txt")
eq(r:match("HEAD", "/").name, "home", "HEAD matches GET")
eq(r:url("user", { id = "a b" }), "/admin/users/a%20b")
eq(r:url("home"), "/")

---------------------------------------------------------------- users
describe("users")
local users = require("wc.people.users")
check(users.validate_username("ab") ~= nil, "short username")
check(users.validate_username("patrick") == nil, "good username")
check(users.validate_username("pat rick") ~= nil, "space in username")
check(users.validate_username(".hidden") ~= nil, "must start with letter/number")
check(users.validate_email("a@b.co", true) == nil and users.validate_email("nope", false) ~= nil and users.validate_email("", false) == nil, "email")
check(users.validate_password("short") ~= nil, "short password")
check(users.validate_password("aaaaaaaaaaaa") ~= nil, "repetitive password")
check(users.validate_password("password1234") ~= nil, "common password")
check(users.validate_password("mypatrickpassword", "patrick") ~= nil, "username inside password")
check(users.validate_password("Correct-Horse-Battery-9") == nil, "strong password ok")
check(users.can({ role = "owner" }, "anything.at.all"), "owner can do anything")
check(users.can({ role = "editor" }, "admin.access") and not users.can({ role = "editor" }, "settings.manage"), "editor caps")
check(not users.can({ role = "member" }, "admin.access") and not users.can(nil, "admin.access"), "member / nobody")

---------------------------------------------------------------- sessions, rate limits, settings (on a real db)
describe("session")
local session = require("wc.platform.session")
local ck = session.parse_cookies("a=1; wc_abc = tok ; b=x=y")
eq(ck.a, "1") eq(ck.wc_abc, "tok") eq(ck.b, "x=y")
local db2 = assert(db.open(tmp))
users.migrate(db2) session.migrate(db2)
require("wc.platform.ratelimit").migrate(db2)
require("wc.platform.settings").migrate(db2)
local uid = users.create(db2, { username = "alice", password = "Correct-Horse-Battery-9", role = "owner" })
local fake = http.new_request({ method = "GET", target = "/", headers = { host = "x" } })
fake.scheme, fake.base_path, fake.client_ip, fake.host = "http", "", "127.0.0.1", "x"
fake.cookie_name = session.cookie_name("abcdef0123")
session.login(fake, db2, users.get(db2, uid))
check(fake.set_cookie:find("HttpOnly") and fake.set_cookie:find("SameSite=Lax") and not fake.set_cookie:find("Secure"), "cookie flags over http")
local tok = fake.session.token
local row = db2:first("SELECT * FROM wc_sessions")
check(row.token_hash ~= tok and #row.token_hash == 64, "only the hash is stored")
local again = http.new_request({ method = "GET", target = "/", headers = { cookie = fake.cookie_name .. "=" .. tok } })
session.load(again, db2, "abcdef0123", users)
eq(again.user and again.user.username, "alice", "session loads user")
local bogus = http.new_request({ method = "GET", target = "/", headers = { cookie = fake.cookie_name .. "=" .. string.rep("A", 43) } })
session.load(bogus, db2, "abcdef0123", users)
check(bogus.user == nil and bogus.clear_cookie, "unknown token ignored and cleared")
local ratelimit = require("wc.platform.ratelimit")
for i = 1, 3 do check(ratelimit.hit(db2, "k", 3, 60), "within limit " .. i) end
local allowed2, retry = ratelimit.hit(db2, "k", 3, 60)
check(not allowed2 and retry > 0, "over limit")
ratelimit.clear(db2, "k")
check(ratelimit.hit(db2, "k", 3, 60), "cleared")
local settings = require("wc.platform.settings")
eq(settings.get(db2, "site.name"), "My site", "default setting")
settings.set(db2, "site.name", "Hi")
eq(settings.get(db2, "site.name"), "Hi")
settings.set(db2, "repo.urls", { "https://a/", "https://b/" })
eq(settings.get(db2, "repo.urls")[2], "https://b/")
db2:close()
os.remove(tmp) os.remove(tmp .. "-wal") os.remove(tmp .. "-shm")

---------------------------------------------------------------- views + ui kit
describe("views")
local ui = require("wc.admin.ui")
local f = ui.field({ name = "x", label = "<b>", value = "\"><script>", error = "bad & worse", hint = "h" })
check(not f:find("<script>") and f:find("&lt;b&gt;") and f:find("bad &amp; worse") and f:find('aria%-invalid="true"'), "fields escape and mark errors")
check(not ui.field({ name = "p", label = "P", type = "password", value = "secret" }):find("secret"), "password values never rendered")
local sel = ui.field({ name = "s", label = "S", type = "select", options = { { "a", "A" }, { "b", "B" } }, value = "b" })
check(sel:find('<option selected value="b">B</option>', 1, true), "select marks the chosen option")
local view = require("wc.platform.view")
local vreq = http.new_request({ method = "GET", target = "/" })
vreq.base_path = "/sub"
local out = view.render("front", { site_name = "<x>", tagline = "", language = "en" }, vreq)
check(out:find('href="/sub/_wc/assets/admin.css?v=', 1, true), "asset URLs include the base path and version")
check(out:find("&lt;x&gt;", 1, true) and not out:find("<x>", 1, true), "templates escape by default")
local ok_env, env_out = pcall(function()
  local etlua = require("wc.vendor.etlua")
  local fn = assert(etlua.compile("<%= os.execute ~= nil and 'leak' or 'safe' %>"))
  return fn(setmetatable({}, { __index = { os = { date = os.date } } }))
end)
check(ok_env and env_out == "safe", "templates only see what they're given: " .. tostring(env_out))


---------------------------------------------------------------- markdown
describe("markdown")
local markdown = require("wc.markdown")
check(markdown.render("# Hi\n\n**b** _i_"):find("<h1>Hi</h1>", 1, true), "headings")
check(markdown.render("~~x~~"):find("<del>x</del>", 1, true), "strikethrough")
check(markdown.render("| a | b |\n|---|---|\n| 1 | 2 |"):find("<table>", 1, true), "tables")
check(markdown.render("- [x] done"):find("checkbox", 1, true), "task lists")
check(markdown.render("see https://example.com"):find('href="https://example.com"', 1, true), "autolinks")
local unsafe = markdown.render('<script>alert(1)</script>\n\n<b onclick="x">b</b>\n\n[x](javascript:alert(1))')
check(not unsafe:find("<script", 1, true) and not unsafe:find("onclick", 1, true) and not unsafe:find("javascript:", 1, true), "raw HTML and javascript: links are removed: " .. unsafe)
eq(markdown.text("**Hello** _there_"):gsub("%s+$", ""), "Hello there")

describe("shortcodes")
local shortcodes = require("wc.content.shortcodes")
local render = require("wc.content.render")
local h1 = render.html('[button url="/contact" text="Hi <b>"]')
check(h1:find('<a class="wc-button" href="/contact">Hi &lt;b&gt;</a>', 1, true), "button shortcode renders and escapes: " .. h1)
check(not h1:find("<p><a", 1, true), "a shortcode alone on its line isn't wrapped in <p>")
local h2 = render.html('[button url="javascript:alert(1)" text="x"]')
check(h2:find('href="#"', 1, true), "button refuses javascript: urls")
local h3, missing = render.html("[gallery id=3]\n\nText [in brackets] stays.", { preview = true })
check(missing[1] == "gallery" and h3:find("wc-missing-shortcode", 1, true) and h3:find("[in brackets]", 1, true), "unknown shortcodes reported, ordinary brackets kept")
local h4 = select(1, render.html("[gallery id=3]"))
check(not h4:find("gallery", 1, true), "visitors don't see unknown shortcodes")
check(select(1, render.html("`[button]` and [[button]]")):find("[button]", 1, true), "code and [[escapes]] are left alone")
local breq = http.new_request({ method = "GET", target = "/" })
breq.base_path = "/sub"
local h5 = render.html("[a](/about) ![i](/media/x.png) [b](//cdn.example/x) [c](https://x.org/)", { req = breq })
check(h5:find('href="/sub/about"', 1, true) and h5:find('src="/sub/media/x.png"', 1, true) and h5:find('href="//cdn.example/x"', 1, true) and h5:find('href="https://x.org/"', 1, true),
  "site links get the subfolder prefix: " .. h5)
eq(render.excerpt("# Title\n\nSome **bold** text that goes on.", 20), "Title Some bold…")

describe("slug")
local slug = require("wc.lib.slug")
eq(slug.make("Hello, World!"), "hello-world")
eq(slug.make("  Ærøskøbing café  "), slug.make("Ærøskøbing café"))
check(slug.valid("about-us") and not slug.valid("About") and not slug.valid("a--b") and not slug.valid("-a") and not slug.valid(""), "slug rules")

describe("multipart")
local multipart = require("wc.lib.multipart")
local mbody = table.concat({
  "--XyZ", 'Content-Disposition: form-data; name="_csrf"', "", "tok",
  "--XyZ", 'Content-Disposition: form-data; name="files"; filename="a b.png"', "Content-Type: image/png", "", "\137PNG\r\n\26\nrest\r\nmore",
  "--XyZ--", "" }, "\r\n")
local mf, mfiles = multipart.parse(mbody, "multipart/form-data; boundary=XyZ")
check(mf and mf._csrf == "tok", "fields")
check(mfiles and mfiles[1] and mfiles[1].filename == "a b.png" and mfiles[1].data == "\137PNG\r\n\26\nrest\r\nmore", "files keep their exact bytes")
check(multipart.parse("garbage", "multipart/form-data; boundary=XyZ") == nil, "malformed bodies are refused")

describe("filetype")
local filetype = require("wc.lib.filetype")
local png = "\137PNG\r\n\26\n\0\0\0\rIHDR\0\0\1\44\0\0\0\200" .. string.rep("\0", 20)
local kind = filetype.detect(png)
check(kind and kind.ext == "png" and kind.image, "PNG detected by content")
local w, hh = filetype.image_size(png, "png")
check(w == 300 and hh == 200, "PNG size read: " .. tostring(w) .. "x" .. tostring(hh))
check(filetype.detect("<svg xmlns='http://www.w3.org/2000/svg'><script/></svg>") == nil, "SVG is not accepted")
check(filetype.detect("<?php echo 1; ?>") == nil and filetype.detect("MZ\144\0") == nil, "scripts and programs are not accepted")

describe("totp")
local totp = require("wc.lib.totp")
local secret = totp.base32_encode and totp.base32_encode("12345678901234567890") or "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
eq(totp.code(secret, 59), "287082")
eq(totp.code(secret, 1111111109), "081804")
eq(totp.code(secret, 2000000000), "279037")
local step = totp.verify(secret, "287082", nil, 59)
check(step, "verify accepts the current code")
check(not totp.verify(secret, "287082", step, 59), "a used code can't be used twice")
check(not totp.verify(secret, "000000", nil, 59), "wrong codes fail")
check(totp.uri(secret, "Site", "bob"):find("^otpauth://totp/"), "otpauth uri")

describe("qr")
local okq, matrix = require("wc.vendor.qrencode").qrcode("otpauth://totp/x?secret=ABC")
check(okq and #matrix >= 21, "QR matrix built")
check(require("wc.people.twofactor").qr_svg("hello"):find("^<svg"), "QR as SVG")

describe("pages")
local tmp3 = os.tmpname()
local db3 = assert(db.open(tmp3))
db3:pragmas()
settings.migrate(db3)
users.migrate(db3)
local pages = require("wc.content.pages")
local menus = require("wc.content.menus")
pages.migrate(db3) menus.migrate(db3)
local about = pages.create(db3, { title = "About", slug = "about", status = "published", access = "public" }, 1)
local team = pages.create(db3, { title = "Team", slug = "team", parent_id = about, status = "draft", access = "public" }, 1)
eq(pages.path(db3, pages.get(db3, team)), "/about/team")
eq(pages.find_by_path(db3, "/about/team").id, team)
check(pages.find_by_path(db3, "/team") == nil, "paths are nested")
local errs = pages.validate(db3, { title = "x", slug = "admin", status = "draft", access = "public" })
check(errs.slug, "reserved addresses refused")
errs = pages.validate(db3, { title = "x", slug = "about", status = "draft", access = "public" })
check(errs.slug, "duplicate addresses refused")
errs = pages.validate(db3, { title = "x", slug = "about", parent_id = team, status = "draft", access = "public" }, about)
check(errs.parent_id, "a page can't go inside its own subpage")
errs = pages.validate(db3, { title = "Hello there", slug = "", status = "draft", access = "public" })
check(not next(errs), "valid page")
check(not pages.is_live(pages.get(db3, team)) and pages.is_live(pages.get(db3, about)), "drafts aren't live")
check(pages.state({ status = "published", publish_at = os.time() + 3600 }) == "scheduled", "future pages are scheduled")
pages.update(db3, about, { title = "About us", slug = "about", body = "v2", status = "published", access = "public" }, 1)
eq(#pages.revisions(db3, about), 2)
menus.add_page(db3, "main", about, "")
menus.add_link(db3, "main", "Shop", "https://shop.example/")
local mreq = http.new_request({ method = "GET", target = "/" })
local tree = menus.for_theme(db3, "main", mreq, "/about")
check(#tree == 2 and tree[1].label == "About us" and tree[1].current and tree[2].external, "menu for themes")
menus.add_page(db3, "main", team, "")
eq(#menus.for_theme(db3, "main", mreq), 2, "drafts are hidden from menus")
pages.delete(db3, about)
eq(pages.path(db3, pages.get(db3, team)), "/team")
eq(#menus.items(db3, "main"), 2, "deleting a page removes its menu items")
db3:close()
os.remove(tmp3) os.remove(tmp3 .. "-wal") os.remove(tmp3 .. "-shm")

describe("themes")
local etlua = require("wc.vendor.etlua")
for _, name in ipairs({ "layout", "page", "404", "message" }) do
  local src = require("wc.platform.files").read("themes/quiet/templates/" .. name .. ".etlua")
  check(src and etlua.compile(src), "quiet/" .. name .. " compiles")
end

---------------------------------------------------------------- done
io.write(("%d passed, %d failed\n"):format(passed, failed))
return failed == 0 and 0 or 1
