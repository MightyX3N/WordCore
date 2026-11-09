-- WordCore — first-run setup wizard.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Steps: 1 site · 2 owner account · 3 where it runs · 4 starting point + addon repo · 5 ready.
-- Answers are kept in the (anonymous) session until "Create site"; the
-- password is hashed as soon as it's entered and never stored in plain text.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local ratelimit = require("wc.platform.ratelimit")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local crypto = require("wc.lib.crypto")
local locale = require("wc.lib.locale")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")
local code = require("wc.setup.code")

local esc = html.escape
local wizard = {}

wizard.OFFICIAL_REPO = "https://wordcore.space/repo/"
local STEPS = { "Site", "Owner account", "Where it runs", "Starting point", "Ready" }

---------------------------------------------------------------- helpers

local function state(req)
  local s = req.session and req.session.data.setup
  if type(s) ~= "table" then s = { reached = 1 } end
  return s
end

local function save(req, s)
  session.set(req, "setup", s)
end

local function is_loopback(ip)
  return ip == "127.0.0.1" or ip == "::1" or (ip or ""):match("^127%.") ~= nil
end

-- Best guess at where this copy of WordCore is running.
function wizard.detect_mode(req)
  if req.mode == "cgi" then return "shared" end
  local h = (req.host or ""):gsub(":%d+$", "")
  if is_loopback(req.client_ip) and (h == "localhost" or h == "127.0.0.1" or h == "[::1]") then return "local" end
  return "server"
end

local MODES = {
  { value = "local", title = "This computer",
    desc = "Built-in server on localhost. Build the site here first; share it through a tunnel like playit.gg." },
  { value = "shared", title = "Shared hosting (cPanel)",
    desc = "Runs through .htaccess as CGI. No server to manage." },
  { value = "server", title = "VPS or own server",
    desc = "Built-in server, behind nginx, Caddy, Cloudflare or a tunnel." },
}

local STARTERS = {
  { value = "empty", title = "Empty", desc = "Just the core. Nothing on the front page until you add it." },
  { value = "simple", title = "Simple site", desc = "A home page, an About page and a main menu." },
  { value = "blog", title = "Blog", desc = "Posts, categories and an archive at /blog.", badge = "Needs the addon system", badge_kind = "", disabled = true },
  { value = "docs", title = "Documentation", desc = "Articles with a sidebar and search.", badge = "Needs the addon system", badge_kind = "", disabled = true },
}

local function valid_url(u)
  return type(u) == "string" and #u <= 300 and u:match("^https://[%w%.%-]+[%w]") ~= nil and not u:find("[%s<>\"']")
end

local function nav_html(req, step, next_label)
  local back = ""
  if step > 1 then
    back = ('<a class="btn" href="%s">Back</a>'):format(esc(req:url_for("/setup?step=" .. (step - 1))))
  end
  return ('<div class="wizard-nav"><div>%s</div><button type="submit" class="btn btn-primary btn-lg">%s</button></div>'):format(
    back, esc(next_label or "Continue"))
end

local function head(step, title, intro)
  return ('<div><p class="step-kicker">Step %d of %d</p><h1>%s</h1><p class="intro">%s</p></div>'):format(
    step, #STEPS, esc(title), esc(intro))
end

local function wizard_page(req, step, body)
  return page.auth(req, {
    title = "Set up your site", steps = STEPS, step = step, body = body,
    side_kicker = "Setting up a new site", side_lead = "Five quick steps, then you're editing.",
    side_foot = ("Running at <code>%s</code><br>Data folder <code>site/</code> next to the program"):format(esc(req.public_url)),
  })
end

---------------------------------------------------------------- step forms

local function form(req, step, inner, next_label)
  return ('<form method="post" action="%s" class="form" novalidate>%s%s%s</form>'):format(
    esc(req:url_for("/setup/step/" .. step)), ui.csrf(req.session.csrf), inner, nav_html(req, step, next_label))
end

local function step1(req, s, errors, values)
  local v = values or s.site or {}
  return form(req, 1, head(1, "Name your site", "You can change all of this later in Settings.") .. table.concat({
    ui.field({ name = "name", label = "Site name", value = v.name, required = true, max = 80, error = errors.name, autofocus = true, placeholder = "My site" }),
    ui.field({ name = "tagline", label = "Tagline", optional = true, value = v.tagline, max = 160, error = errors.tagline, placeholder = "A short line under the name" }),
    '<div class="row-2">',
    ui.field({ name = "language", label = "Language", type = "select", options = locale.language_options(), value = v.language or "en", error = errors.language }),
    ui.field({ name = "timezone", label = "Time zone", type = "select", options = locale.timezone_options(), value = v.timezone or "UTC", error = errors.timezone }),
    "</div>",
  }))
end

local function step2(req, s, errors, values)
  local v = values or s.owner or {}
  return form(req, 2, head(2, "Create your account", "This is the owner account. There's no default login, and roles can never lock the owner out.") .. table.concat({
    ui.field({ name = "username", label = "Username", value = v.username, required = true, max = 32, error = errors.username, autocomplete = "username", autofocus = true, spellcheck = "false" }),
    ui.field({ name = "display_name", label = "Your name", optional = true, value = v.display_name, max = 80, error = errors.display_name, autocomplete = "name" }),
    ui.field({ name = "email", label = "Email", type = "email", optional = true, value = v.email, max = 254, error = errors.email, autocomplete = "email",
      hint = "Used for password resets later. Never shown publicly." }),
    ui.field({ name = "password", label = "Password", type = "password", required = true, error = errors.password, autocomplete = "new-password",
      strength = true, hint = s.owner and s.owner.hash and "A password is already set. Leave empty to keep it." or "At least 10 characters." }),
    ui.field({ name = "password2", label = "Repeat password", type = "password", error = errors.password2, autocomplete = "new-password" }),
  }))
end

local function step3(req, s, errors)
  local detected = wizard.detect_mode(req)
  local opts = {}
  for _, m in ipairs(MODES) do
    local o = { value = m.value, title = m.title, desc = m.desc }
    if m.value == detected then o.badge = "Detected" end
    opts[#opts + 1] = o
  end
  return form(req, 3, head(3, "Where is this site running?", "We detected this for you. It only changes defaults like HTTPS and proxy settings.") ..
    ui.choices({ name = "mode", label = "Where it runs", options = opts, value = s.mode or detected, error = errors.mode }))
end

local function step4(req, s, errors, values)
  local v = values or {}
  local repo = v.repo or s.repo or wizard.OFFICIAL_REPO
  local repo_note = '<div class="note">Using another repository? Its addons still run in the sandbox and ask before they get permissions, but they\'re marked as unofficial.</div>'
  return form(req, 4, head(4, "Pick a starting point", "Starters only decide which addons get installed and add a page or two. Nothing is locked in.") .. table.concat({
    ui.choices({ name = "starter", label = "Starter", options = STARTERS, value = v.starter or s.starter or "simple", grid = true, error = errors.starter }),
    '<section class="card"><div class="card-body">',
    '<div class="card-head-inline"><span class="section-title">Addon repository</span> <span class="badge ok">Official · recommended</span></div>',
    ui.field({ name = "repo", label = "Repository address", type = "url", value = repo, mono = true, error = errors.repo,
      hint = "We recommend the official WordCore repository. Its addons are reviewed and signed." }),
    repo_note,
    "</div></section>",
  }))
end

local function step5(req, s)
  local mode_title, starter_title = s.mode, s.starter
  for _, m in ipairs(MODES) do if m.value == s.mode then mode_title = m.title end end
  for _, m in ipairs(STARTERS) do if m.value == s.starter then starter_title = m.title end end
  local rows = {
    { "Site", s.site.name },
    { "Owner", s.owner.username .. (s.owner.email ~= "" and (" · " .. s.owner.email) or "") },
    { "Runs on", mode_title },
    { "Starter", starter_title },
    { "Addon repository", s.repo },
    { "Database", "site/site.db" },
  }
  local dl = { '<dl class="kv card card-pad">' }
  for _, r in ipairs(rows) do dl[#dl + 1] = ("<dt>%s</dt><dd>%s</dd>"):format(esc(r[1]), esc(r[2])) end
  dl[#dl + 1] = "</dl>"
  return ('<form method="post" action="%s" class="form">%s%s%s%s</form>'):format(
    esc(req:url_for("/setup/finish")), ui.csrf(req.session.csrf),
    head(5, "Ready to create your site", "Check the details. Everything lives in one folder, so moving to a host later is a copy."),
    table.concat(dl), nav_html(req, 5, "Create site"))
end

local RENDER = { step1, step2, step3, step4, step5 }

---------------------------------------------------------------- code gate

local function code_page(req, err)
  local where = req.mode == "cgi"
    and "Open your hosting's File Manager, go to the folder you uploaded WordCore to, and open <code>site/setup-code.txt</code>."
    or "It's shown in the WordCore window, and saved in <code>site/setup-code.txt</code> next to the program."
  local body = ('<div><h1>Enter your setup code</h1><p class="intro">Only someone who can see this site\'s files can set it up. %s</p></div>'):format(where)
    .. ('<form method="post" action="%s" class="form">%s%s<div class="actions"><button type="submit" class="btn btn-primary btn-lg">Continue</button></div></form>'):format(
      esc(req:url_for("/setup/code")), ui.csrf(req.session.csrf),
      ui.field({ name = "code", label = "Setup code", required = true, error = err, autocomplete = "off", class = "code-input",
        placeholder = "XXXX-XXXX", autofocus = true, spellcheck = "false" }))
  return page.auth(req, {
    title = "Setup code", body = body, small = true,
    side_kicker = "Setting up a new site", side_lead = "First, prove this site is yours.",
  })
end

local function code_attempt(req, given)
  local ok_rate, retry = ratelimit.hit(req.db, "setup-code:" .. (req.client_ip or "?"), 10, 900)
  if not ok_rate then
    return false, ("Too many tries. Wait %d minutes and try again."):format(math.ceil(retry / 60))
  end
  if code.check(req.site, given) then
    local s = state(req)
    s.ok = true
    save(req, s)
    log.add(req.db, req, "setup.code", nil)
    return true
  end
  return false, "That code isn't right. Check site/setup-code.txt."
end

---------------------------------------------------------------- handlers

local function get_setup(req)
  session.ensure(req, req.db)
  local s = state(req)
  if not s.ok then
    if req.query.code then
      local ok, err = code_attempt(req, req.query.code)
      if ok then return http.new_response():redirect(req:url_for("/setup")) end
      return code_page(req, err)
    end
    code.get(req.site) -- make sure the file exists
    return code_page(req)
  end
  local step = tonumber(req.query.step or "") or s.reached
  step = math.max(1, math.min(step, s.reached, #STEPS))
  return wizard_page(req, step, RENDER[step](req, s, {}))
end

local function post_code(req)
  local ok, err = code_attempt(req, req:form().code)
  if ok then return http.new_response():redirect(req:url_for("/setup")) end
  local res = code_page(req, err)
  res.status = 422
  return res
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function post_step(req, params)
  local s = state(req)
  if not s.ok then return http.new_response():redirect(req:url_for("/setup")) end
  local step = tonumber(params.n)
  if not step or step < 1 or step > 4 or step > s.reached then
    return http.new_response():redirect(req:url_for("/setup"))
  end
  local f = req:form()
  local errors = {}

  if step == 1 then
    local v = { name = trim(f.name), tagline = trim(f.tagline), language = f.language, timezone = f.timezone }
    if v.name == "" then errors.name = "Give your site a name." elseif #v.name > 80 then errors.name = "Use at most 80 characters." end
    if #v.tagline > 160 then errors.tagline = "Use at most 160 characters." end
    if not locale.valid_language(v.language) then errors.language = "Choose a language from the list." end
    if not locale.valid_timezone(v.timezone) then errors.timezone = "Choose a time zone from the list." end
    if next(errors) then return wizard_page(req, 1, step1(req, s, errors, v)) end
    s.site = v

  elseif step == 2 then
    local v = { username = trim(f.username), display_name = trim(f.display_name), email = trim(f.email) }
    errors.username = users.validate_username(v.username)
    errors.email = users.validate_email(v.email, false)
    if #v.display_name > 80 then errors.display_name = "Use at most 80 characters." end
    local pw, pw2 = f.password or "", f.password2 or ""
    local keep = pw == "" and s.owner and s.owner.hash
    if not keep then
      errors.password = users.validate_password(pw, v.username)
      if not errors.password and pw ~= pw2 then errors.password2 = "The passwords don't match." end
    end
    if next(errors) then return wizard_page(req, 2, step2(req, s, errors, v)) end
    v.hash = keep and s.owner.hash or crypto.hash_password(pw)
    s.owner = v

  elseif step == 3 then
    local m = f.mode
    local valid = false
    for _, o in ipairs(MODES) do if o.value == m then valid = true end end
    if not valid then return wizard_page(req, 3, step3(req, s, { mode = "Choose one." })) end
    s.mode = m

  elseif step == 4 then
    local v = { starter = f.starter, repo = trim(f.repo) }
    local valid = false
    for _, o in ipairs(STARTERS) do if o.value == v.starter and not o.disabled then valid = true end end
    if not valid then errors.starter = "Choose Empty or Simple site for now." end
    if v.repo == "" then v.repo = wizard.OFFICIAL_REPO end
    if not valid_url(v.repo) then errors.repo = "Enter an https:// address." end
    if next(errors) then return wizard_page(req, 4, step4(req, s, errors, v)) end
    s.starter, s.repo = v.starter, v.repo
  end

  s.reached = math.max(s.reached, step + 1)
  save(req, s)
  return http.new_response():redirect(req:url_for("/setup?step=" .. (step + 1)))
end

local function post_finish(req)
  local s = state(req)
  if not s.ok or s.reached < 5 or not (s.site and s.owner and s.mode and s.starter and s.repo) then
    return http.new_response():redirect(req:url_for("/setup"))
  end
  local db = req.db
  local user
  local ok, err = pcall(db.transaction, db, function()
    if users.has_owner(db) then error("already set up", 0) end
    local id = users.create(db, {
      username = s.owner.username, email = s.owner.email, display_name = s.owner.display_name ~= "" and s.owner.display_name or s.owner.username,
      password_hash = s.owner.hash, role = "owner",
    })
    settings.set(db, "site.name", s.site.name)
    settings.set(db, "site.tagline", s.site.tagline)
    settings.set(db, "site.language", s.site.language)
    settings.set(db, "site.timezone", s.site.timezone)
    settings.set(db, "site.run_mode", s.mode)
    settings.set(db, "site.starter", s.starter)
    settings.set(db, "repo.urls", { s.repo })
    settings.set(db, "site.created_at", os.time())
    user = users.get(db, id)
  end)
  if not ok then
    if err == "already set up" then return http.new_response():redirect(req:url_for("/admin/login")) end
    error(err, 0)
  end
  require("wc.content.starter").apply(db, s.starter, s.site.name, user.id)
  code.remove(req.site)
  db:run("UPDATE wc_users SET last_login_at = unixepoch() WHERE id = ?", user.id)
  session.login(req, db, users.get(db, user.id))
  log.add(db, req, "setup.done", nil)
  session.flash(req, "ok", "Your site is ready. Welcome to WordCore!")
  return http.new_response():redirect(req:url_for("/admin"))
end

function wizard.register(r)
  r:get("/setup", get_setup, { name = "setup" })
  r:post("/setup/code", post_code)
  r:post("/setup/step/:n", post_step)
  r:post("/setup/finish", post_finish)
end

return wizard
