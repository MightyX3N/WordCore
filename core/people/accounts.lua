-- WordCore — accounts on the public site: sign in, register, your account.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Members use these themed pages; staff can too. Registration is off unless
-- the owner turns it on in Settings → Members.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local ratelimit = require("wc.platform.ratelimit")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local login = require("wc.people.login")
local twofactor = require("wc.people.twofactor")
local crypto = require("wc.lib.crypto")
local html = require("wc.lib.html")
local engine = require("wc.themes.engine")

local esc = html.escape
local accounts = {}

local CL = { form = "wc-form", field = "wc-field", input = "", error = "wc-error", button = "wc-button", hint = "wc-hint", codes = "wc-codes" }

local function field(name, label, opts)
  opts = opts or {}
  local id = "f-" .. name
  return ('<div class="wc-field"><label for="%s">%s</label><input id="%s" name="%s" type="%s"%s%s%s%s>%s%s</div>'):format(
    id, esc(label), id, esc(name), opts.type or "text",
    opts.value and (' value="' .. esc(opts.value) .. '"') or "",
    opts.autocomplete and (' autocomplete="' .. esc(opts.autocomplete) .. '"') or "",
    opts.required and " required" or "",
    opts.error and ' aria-invalid="true"' or "",
    opts.hint and ('<span class="wc-hint">' .. esc(opts.hint) .. "</span>") or "",
    opts.error and ('<span class="wc-error">' .. esc(opts.error) .. "</span>") or "")
end

local function form(req, action, inner, button)
  return ('<form method="post" action="%s" class="wc-form" novalidate><input type="hidden" name="_csrf" value="%s">%s<p><button type="submit" class="wc-button">%s</button></p></form>'):format(
    esc(req:url_for(action)), esc(req.session.csrf), inner, esc(button))
end

local function alert(text, ok)
  if not text then return "" end
  return ('<p class="wc-alert%s" role="%s">%s</p>'):format(ok and " ok" or "", ok and "status" or "alert", esc(text))
end

local function flashes(req)
  local out = {}
  for _, m in ipairs(session.take_flash(req)) do out[#out + 1] = alert(m.text, m.kind == "ok") end
  return table.concat(out)
end

local function registration_open(db) return settings.get(db, "members.registration", false) == true end

---------------------------------------------------------------- sign in

local function login_view(req, err, value, status)
  local nxt = login.safe_next(req.query.next or req:form().next)
  local body = flashes(req) .. alert(err) .. form(req, "/account/login",
    (nxt and ('<input type="hidden" name="next" value="%s">'):format(esc(nxt)) or "")
    .. field("login", "Username or email", { value = value, autocomplete = "username", required = true })
    .. field("password", "Password", { type = "password", autocomplete = "current-password", required = true }), "Sign in")
  if registration_open(req.db) then
    body = body .. ('<p>New here? <a href="%s">Create an account</a></p>'):format(esc(req:url_for("/account/register")))
  end
  local res = engine.message(req, "Sign in", body, status)
  res:set_header("Cache-Control", "no-store")
  return res
end

local function get_login(req)
  if req.user then return http.new_response():redirect(req:url_for(login.safe_next(req.query.next) or "/account")) end
  session.ensure(req, req.db)
  return login_view(req)
end

local function post_login(req)
  local f = req:form()
  local result, err, status = login.attempt(req, f.login, f.password, f.next, "site")
  if result == "2fa" then return http.new_response():redirect(req:url_for("/account/login/verify")) end
  if not result then return login_view(req, err, (f.login or ""):sub(1, 254), status) end
  return http.new_response():redirect(req:url_for(login.safe_next(f.next) or "/account"))
end

local function verify_view(req, err, status)
  local body = "<p>Enter the 6-digit code from your authenticator app, or one of your recovery codes.</p>" .. alert(err)
    .. form(req, "/account/login/verify", field("code", "Code", { autocomplete = "one-time-code", required = true }), "Verify")
  return engine.message(req, "2-step login", body, status)
end

local function get_verify(req)
  if not login.pending(req) then return http.new_response():redirect(req:url_for("/account/login")) end
  return verify_view(req)
end

local function post_verify(req)
  local result, nxt_or_err, status = login.verify(req, req:form().code)
  if result == "ok" then return http.new_response():redirect(req:url_for(nxt_or_err or "/account")) end
  if status == 410 then
    session.flash(req, "bad", nxt_or_err)
    return http.new_response():redirect(req:url_for("/account/login"))
  end
  return verify_view(req, nxt_or_err, status)
end

local function post_logout(req)
  if req.user then log.add(req.db, req, "logout", nil) end
  session.destroy(req, req.db)
  return http.new_response():redirect(req:url_for("/"))
end

---------------------------------------------------------------- register

local function register_view(req, errors, v, status)
  errors, v = errors or {}, v or {}
  local body = alert(errors._) .. form(req, "/account/register",
    field("username", "Username", { value = v.username, autocomplete = "username", required = true, error = errors.username })
    .. field("email", "Email", { type = "email", value = v.email, autocomplete = "email", error = errors.email, hint = "Optional. Used if you forget your password." })
    .. field("password", "Password", { type = "password", autocomplete = "new-password", required = true, error = errors.password, hint = "At least 10 characters." })
    .. field("password2", "Repeat password", { type = "password", autocomplete = "new-password", required = true, error = errors.password2 }),
    "Create account")
    .. ('<p>Already have an account? <a href="%s">Sign in</a></p>'):format(esc(req:url_for("/account/login")))
  return engine.message(req, "Create an account", body, status)
end

local function get_register(req)
  if not registration_open(req.db) then return require("wc.content.front").not_found(req) end
  if req.user then return http.new_response():redirect(req:url_for("/account")) end
  session.ensure(req, req.db)
  return register_view(req)
end

local function post_register(req)
  if not registration_open(req.db) then return require("wc.content.front").not_found(req) end
  local f = req:form()
  local v = { username = (f.username or ""):gsub("^%s+", ""):gsub("%s+$", ""), email = (f.email or ""):gsub("^%s+", ""):gsub("%s+$", "") }
  local ok_rate = ratelimit.hit(req.db, "register:ip:" .. (req.client_ip or "?"), 5, 3600)
  if not ok_rate then return register_view(req, { _ = "Too many new accounts from your network. Try again later." }, v, 429) end
  local errors = {}
  errors.username = users.validate_username(v.username)
  if not errors.username and users.find_by_login(req.db, v.username) then errors.username = "That username is taken." end
  errors.email = users.validate_email(v.email, false)
  if not errors.email and v.email ~= "" and users.find_by_login(req.db, v.email) then errors.email = "An account already uses this email." end
  errors.password = users.validate_password(f.password, v.username)
  if not errors.password and f.password ~= f.password2 then errors.password2 = "The passwords don't match." end
  if next(errors) then return register_view(req, errors, v, 422) end
  local id = users.create(req.db, { username = v.username, email = v.email, display_name = v.username, password = f.password, role = "member" })
  local user = users.get(req.db, id)
  session.login(req, req.db, user)
  log.add(req.db, req, "account.registered", nil)
  session.flash(req, "ok", "Welcome! Your account is ready.")
  return http.new_response():redirect(req:url_for("/account"))
end

---------------------------------------------------------------- your account

local function account_view(req, errors, status, extra_html)
  errors = errors or {}
  local u = req.user
  local parts = { flashes(req), extra_html or "" }
  if users.can(u, "admin.access") then
    parts[#parts + 1] = ('<p><a class="wc-button" href="%s">Go to the admin</a></p>'):format(esc(req:url_for("/admin")))
  end
  parts[#parts + 1] = "<h2>Profile</h2>" .. form(req, "/account/profile",
    field("display_name", "Your name", { value = u.display_name, autocomplete = "name", error = errors.display_name })
    .. field("email", "Email", { type = "email", value = u.email, autocomplete = "email", error = errors.email }), "Save profile")
  parts[#parts + 1] = "<h2>Password</h2>" .. form(req, "/account/password",
    field("current", "Current password", { type = "password", autocomplete = "current-password", error = errors.current })
    .. field("new", "New password", { type = "password", autocomplete = "new-password", error = errors.new, hint = "At least 10 characters." })
    .. field("new2", "Repeat new password", { type = "password", autocomplete = "new-password", error = errors.new2 }), "Change password")
  parts[#parts + 1] = "<h2>2-step login</h2>"
  if twofactor.enabled(u) then
    parts[#parts + 1] = "<p>On. Signing in needs a code from your authenticator app.</p>" .. form(req, "/account/2fa/off",
      field("password", "Your password (to turn it off)", { type = "password", autocomplete = "current-password", error = errors.tf_password }), "Turn off 2-step login")
  else
    parts[#parts + 1] = ('<p>Add a code from an authenticator app on top of your password.</p><p><a class="wc-button" href="%s">Turn on 2-step login</a></p>'):format(esc(req:url_for("/account/2fa")))
  end
  parts[#parts + 1] = ('<form method="post" action="%s"><input type="hidden" name="_csrf" value="%s"><p><button type="submit" class="wc-button">Sign out</button></p></form>'):format(
    esc(req:url_for("/account/logout")), esc(req.session.csrf))
  local res = engine.message(req, "Your account", table.concat(parts), status)
  res:set_header("Cache-Control", "no-store")
  return res
end

local function need_user(req)
  if req.user then return nil end
  return http.new_response():redirect(req:url_for("/account/login?next=" .. http.url_encode(req.path)))
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local handlers = {}

function handlers.account(req) return need_user(req) or account_view(req) end

function handlers.profile(req)
  local r = need_user(req) if r then return r end
  local f = req:form()
  local v = { display_name = trim(f.display_name), email = trim(f.email) }
  local errors = {}
  if #v.display_name > 80 then errors.display_name = "Use at most 80 characters." end
  errors.email = users.validate_email(v.email, false)
  if next(errors) then return account_view(req, errors, 422) end
  users.update_profile(req.db, req.user.id, v.display_name ~= "" and v.display_name or req.user.username, v.email)
  session.flash(req, "ok", "Profile saved.")
  return http.new_response():redirect(req:url_for("/account"))
end

function handlers.password(req)
  local r = need_user(req) if r then return r end
  local f = req:form()
  local errors = {}
  if not crypto.verify_password(f.current or "", req.user.password_hash) then
    errors.current = "That isn't your current password."
  else
    errors.new = users.validate_password(f.new, req.user.username)
    if not errors.new and f.new ~= f.new2 then errors.new2 = "The passwords don't match." end
  end
  if next(errors) then return account_view(req, errors, 422) end
  users.set_password(req.db, req.user.id, f.new)
  session.login(req, req.db, users.get(req.db, req.user.id), true)
  session.destroy_others(req, req.db)
  log.add(req.db, req, "account.password", nil)
  session.flash(req, "ok", "Password changed. Other devices have been signed out.")
  return http.new_response():redirect(req:url_for("/account"))
end

function handlers.tf_get(req)
  local r = need_user(req) if r then return r end
  if twofactor.enabled(req.user) then return http.new_response():redirect(req:url_for("/account")) end
  local secret = twofactor.setup_secret(req, session)
  return engine.message(req, "Turn on 2-step login", twofactor.setup_view(req, secret, req:url_for("/account/2fa"), nil, CL))
end

function handlers.tf_post(req)
  local r = need_user(req) if r then return r end
  local codes, err = twofactor.confirm(req, req.db, session, req:form().code)
  if not codes then
    local secret = twofactor.setup_secret(req, session)
    return engine.message(req, "Turn on 2-step login", twofactor.setup_view(req, secret, req:url_for("/account/2fa"), err, CL), 422)
  end
  log.add(req.db, req, "account.2fa_on", nil)
  return engine.message(req, "2-step login is on", twofactor.codes_view(codes, CL)
    .. ('<p><a class="wc-button" href="%s">I\'ve saved them</a></p>'):format(esc(req:url_for("/account"))))
end

function handlers.tf_off(req)
  local r = need_user(req) if r then return r end
  if not crypto.verify_password(req:form().password or "", req.user.password_hash) then
    return account_view(req, { tf_password = "That isn't your password." }, 422)
  end
  twofactor.disable(req.db, req.user.id)
  log.add(req.db, req, "account.2fa_off", nil)
  session.flash(req, "ok", "2-step login is off.")
  return http.new_response():redirect(req:url_for("/account"))
end

function accounts.register(r)
  r:get("/account/login", get_login)
  r:post("/account/login", post_login)
  r:get("/account/login/verify", get_verify)
  r:post("/account/login/verify", post_verify)
  r:post("/account/logout", post_logout)
  r:get("/account/register", get_register)
  r:post("/account/register", post_register)
  r:get("/account", handlers.account)
  r:post("/account/profile", handlers.profile)
  r:post("/account/password", handlers.password)
  r:get("/account/2fa", handlers.tf_get)
  r:post("/account/2fa", handlers.tf_post)
  r:post("/account/2fa/off", handlers.tf_off)
end

return accounts
