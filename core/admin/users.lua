-- WordCore — admin: people (staff and members).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Rules: nobody changes or deletes the owner except the owner (on their own
-- account page); you can't change your own role or delete yourself; the owner
-- role is never handed out here.

local http = require("wc.platform.http")
local session = require("wc.platform.session")
local settings = require("wc.platform.settings")
local log = require("wc.platform.log")
local users = require("wc.people.users")
local twofactor = require("wc.people.twofactor")
local crypto = require("wc.lib.crypto")
local html = require("wc.lib.html")
local ui = require("wc.admin.ui")
local page = require("wc.admin.page")

local esc = html.escape
local admin_users = {}

local ROLE_HELP = {
  admin = "Everything except deleting the owner: settings, people, themes and all content.",
  editor = "Writes, edits and publishes all pages; manages menus and media.",
  author = "Writes their own pages as drafts and uploads media. An editor publishes them.",
  member = "Can't open the admin. Signs in on the site to see members-only pages.",
}

local function role_options()
  local out = {}
  for _, r in ipairs(users.ROLES) do
    if r.id ~= "owner" then out[#out + 1] = { value = r.id, title = r.label, desc = ROLE_HELP[r.id] } end
  end
  return out
end

-- Readable one-time password: 4 groups of 4 from an unambiguous alphabet.
local ALPHA = "abcdefghjkmnpqrstuvwxyz23456789"
function admin_users.temp_password()
  local bytes = crypto.random(16)
  local out = {}
  for i = 1, 16 do
    local b = bytes:byte(i)
    out[#out + 1] = ALPHA:sub(b % #ALPHA + 1, b % #ALPHA + 1)
    if i % 4 == 0 and i < 16 then out[#out + 1] = "-" end
  end
  return table.concat(out)
end

local function name_of(u) return u.display_name ~= "" and u.display_name or u.username end

local function list(req)
  local filter = req.query.show == "members" and "members" or req.query.show == "staff" and "staff" or "all"
  local rows, counts = {}, { all = 0, staff = 0, members = 0 }
  for _, u in ipairs(req.db:query("SELECT * FROM wc_users ORDER BY CASE role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 WHEN 'editor' THEN 2 WHEN 'author' THEN 3 ELSE 4 END, username COLLATE NOCASE")) do
    local is_member = u.role == "member"
    counts.all = counts.all + 1
    counts[is_member and "members" or "staff"] = counts[is_member and "members" or "staff"] + 1
    if filter == "all" or (filter == "members") == is_member then
      rows[#rows + 1] = ('<li><span class="avatar sm" aria-hidden="true">%s</span><span class="grow"><a class="row-title" href="%s">%s</a>%s%s<br><span class="small muted">@%s%s</span></span>%s<span class="when">%s</span></li>'):format(
        esc(name_of(u):sub(1, 1):upper()), esc(req:url_for("/admin/users/" .. u.id)), esc(name_of(u)),
        u.id == req.user.id and ' <span class="badge">You</span>' or "",
        u.totp_enabled == 1 and ' <span class="badge ok">2-step</span>' or "",
        esc(u.username), u.email ~= "" and (" · " .. esc(u.email)) or "",
        ui.badge(users.role_label(u.role), u.role == "owner" and "accent" or ""),
        esc(u.last_login_at and ("signed in " .. ui.ago(u.last_login_at)) or "never signed in"))
    end
  end
  local tabs = ('<nav class="tabs" aria-label="Filter people"><a class="tab" href="%s"%s>Everyone <span class="muted">%d</span></a><a class="tab" href="%s"%s>Staff <span class="muted">%d</span></a><a class="tab" href="%s"%s>Members <span class="muted">%d</span></a></nav>'):format(
    esc(req:url_for("/admin/users")), filter == "all" and ' aria-current="page"' or "", counts.all,
    esc(req:url_for("/admin/users?show=staff")), filter == "staff" and ' aria-current="page"' or "", counts.staff,
    esc(req:url_for("/admin/users?show=members")), filter == "members" and ' aria-current="page"' or "", counts.members)
  local reg = settings.get(req.db, "members.registration", false)
  local note = ('<p class="small muted">Member sign-up on the site is <strong>%s</strong>. <a href="%s">Change in Settings</a>.</p>'):format(
    reg and "open" or "closed", esc(req:url_for("/admin/settings#members")))
  local body = tabs .. (#rows > 0 and ('<section class="card"><ul class="list">' .. table.concat(rows) .. "</ul></section>")
    or '<section class="card"><p class="empty">Nobody here yet.</p></section>') .. note
  return page.admin(req, { title = "People", subtitle = "Everyone who can sign in.", active = "users", body = body,
    actions_html = ('<a class="btn btn-primary" href="%s">Add person</a>'):format(esc(req:url_for("/admin/users/new"))) })
end

local function password_shown(req, u, pw, heading)
  local body = ('<section class="card"><div class="card-body"><p>%s</p><div class="field"><label for="f-temp">One-time password</label><div class="copy-row"><input id="f-temp" class="input mono" readonly value="%s"><button type="button" class="btn" data-copy="%s">Copy</button></div><p class="hint">Send it to them privately. It won\'t be shown again. They should change it under “Your account” after signing in.</p></div><p class="small">They sign in at <code>%s</code>.</p><div class="actions"><a class="btn btn-primary" href="%s">Done</a></div></div></section>'):format(
    esc(("%s can now sign in as @%s."):format(name_of(u), u.username)), esc(pw), esc(pw),
    esc((req.public_url or ""):gsub("/+$", "") .. (u.role == "member" and "/account/login" or "/admin/login")),
    esc(req:url_for("/admin/users/" .. u.id)))
  return page.admin(req, { title = heading, active = "users", narrow = true, body = body })
end

local function new_form(req, v, errors, status)
  v, errors = v or {}, errors or {}
  local body = ui.form({ action = req:url_for("/admin/users/new"), csrf = req.session.csrf, submit = "Add person", sections = {
    { title = "Who", fields = {
      { name = "username", label = "Username", value = v.username, max = 32, error = errors.username, autocomplete = "off", spellcheck = "false", autofocus = true,
        hint = "Letters, numbers, dots, dashes and underscores. Used to sign in." },
      { name = "display_name", label = "Name", value = v.display_name, max = 80, optional = true },
      { name = "email", label = "Email", type = "email", value = v.email, max = 254, error = errors.email, optional = true,
        hint = "They can sign in with it too. WordCore doesn't send email yet." },
    }},
    { title = "Role", fields = { { name = "role", label = "Role", type = "choice", value = v.role or "author", options = role_options(), error = errors.role } } },
  }})
  local res = page.admin(req, { title = "Add person", subtitle = "They get a one-time password to sign in with.", active = "users", narrow = true, body = body })
  if status then res.status = status end
  return res
end

local function valid_role(role)
  return role ~= "owner" and users.role_label(role) ~= role
end

local function post_new(req)
  local f = req:form()
  local v = { username = (f.username or ""):gsub("^%s+", ""):gsub("%s+$", ""), display_name = (f.display_name or ""):gsub("^%s+", ""):gsub("%s+$", ""),
    email = (f.email or ""):gsub("^%s+", ""):gsub("%s+$", ""), role = f.role }
  local errors = {}
  errors.username = users.validate_username(v.username)
  if not errors.username and users.find_by_login(req.db, v.username) then errors.username = "Someone already uses that username." end
  errors.email = users.validate_email(v.email, false)
  if not errors.email and v.email ~= "" and req.db:first("SELECT 1 AS x FROM wc_users WHERE lower(email) = lower(?)", v.email) then
    errors.email = "Someone already uses that email."
  end
  if #v.display_name > 80 then v.display_name = v.display_name:sub(1, 80) end
  if not valid_role(v.role) then errors.role = "Choose a role." end
  if next(errors) then return new_form(req, v, errors, 422) end
  local pw = admin_users.temp_password()
  local id = users.create(req.db, { username = v.username, email = v.email, display_name = v.display_name ~= "" and v.display_name or v.username, password = pw, role = v.role })
  log.add(req.db, req, "users.added", v.username .. " (" .. users.role_label(v.role) .. ")")
  return password_shown(req, users.get(req.db, id), pw, "Person added")
end

-- Can the current user change this account here?
local function guard(req, u)
  if not u then return http.error_page(404, "That person doesn't exist.") end
  if u.role == "owner" and req.user.role ~= "owner" then return http.error_page(403, "Only the owner can change the owner's account.") end
  return nil
end

local function show(req, params, errors, status)
  local u = users.get(req.db, tonumber(params.id))
  local stop = guard(req, u)
  if stop then return stop end
  local is_self = u.id == req.user.id
  local sessions = req.db:first("SELECT COUNT(*) AS n FROM wc_sessions WHERE user_id = ? AND expires_at > ?", u.id, os.time()).n
  local pages_n = req.db:first("SELECT COUNT(*) AS n FROM wc_pages WHERE author_id = ?", u.id).n
  local facts = ('<div class="card-body"><dl class="facts"><dt>Username</dt><dd>@%s</dd><dt>Email</dt><dd>%s</dd><dt>Joined</dt><dd>%s</dd><dt>Last sign-in</dt><dd>%s</dd><dt>2-step login</dt><dd>%s</dd><dt>Signed in on</dt><dd>%d device%s</dd><dt>Pages written</dt><dd>%d</dd></dl></div>'):format(
    esc(u.username), u.email ~= "" and esc(u.email) or '<span class="muted">none</span>', esc(os.date("%d %b %Y", u.created_at)),
    esc(ui.ago(u.last_login_at)), u.totp_enabled == 1 and "On" or "Off", sessions, sessions == 1 and "" or "s", pages_n)
  local body = ui.card(name_of(u), facts, { aside = ui.badge(users.role_label(u.role), u.role == "owner" and "accent" or "") })
  if is_self then
    body = body .. ('<p class="muted">This is you. Change your own details, password and 2-step login under <a href="%s">Your account</a>.</p>'):format(esc(req:url_for("/admin/account")))
  else
    local base = "/admin/users/" .. u.id
    body = body .. ui.form({ action = req:url_for(base .. "/role"), csrf = req.session.csrf, submit = "Change role", sections = {
      { title = "Role", intro = "Changing the role signs them out everywhere, so the new access applies straight away.",
        fields = { { name = "role", label = "Role", type = "choice", value = u.role, options = role_options(), error = errors and errors.role } } },
    }})
    local tools = {
      ('<form method="post" action="%s" data-confirm="Make a new one-time password for %s? Their current password stops working and they\'re signed out everywhere.">%s<button type="submit" class="btn">Reset password</button></form>'):format(
        esc(req:url_for(base .. "/password")), esc(u.username), ui.csrf(req.session.csrf)),
      sessions > 0 and ('<form method="post" action="%s">%s<button type="submit" class="btn">Sign out everywhere</button></form>'):format(
        esc(req:url_for(base .. "/signout")), ui.csrf(req.session.csrf)) or "",
      u.totp_enabled == 1 and ('<form method="post" action="%s" data-confirm="Turn off 2-step login for %s? Do this only if they lost their phone and recovery codes.">%s<button type="submit" class="btn">Turn off 2-step login</button></form>'):format(
        esc(req:url_for(base .. "/2fa-off")), esc(u.username), ui.csrf(req.session.csrf)) or "",
    }
    body = body .. ui.card("Access", '<div class="card-body"><div class="actions wrap">' .. table.concat(tools) .. "</div></div>")
    body = body .. ('<form method="post" action="%s" data-confirm="Delete %s\'s account? Their pages stay. This can\'t be undone.">%s<button type="submit" class="btn btn-danger btn-sm">Delete account</button></form>'):format(
      esc(req:url_for(base .. "/delete")), esc(u.username), ui.csrf(req.session.csrf))
  end
  local res = page.admin(req, { title = name_of(u), subtitle = users.role_label(u.role), active = "users", narrow = true, body = body,
    actions_html = ('<a class="btn" href="%s">All people</a>'):format(esc(req:url_for("/admin/users"))) })
  if status then res.status = status end
  return res
end

local function target(req, params)
  local u = users.get(req.db, tonumber(params.id))
  local stop = guard(req, u)
  if stop then return nil, stop end
  if u.id == req.user.id then return nil, http.error_page(403, "Change your own account under Your account.") end
  if u.role == "owner" then return nil, http.error_page(403, "The owner's account can't be changed here.") end
  return u
end

local function signout_all(db, id) db:run("DELETE FROM wc_sessions WHERE user_id = ?", id) end

local function post_role(req, params)
  local u, err = target(req, params)
  if not u then return err end
  local role = req:form().role
  if not valid_role(role) then return show(req, params, { role = "Choose a role." }, 422) end
  if role ~= u.role then
    req.db:run("UPDATE wc_users SET role = ? WHERE id = ?", role, u.id)
    signout_all(req.db, u.id)
    log.add(req.db, req, "users.role", ("%s: %s → %s"):format(u.username, users.role_label(u.role), users.role_label(role)))
    session.flash(req, "ok", ("%s is now %s."):format(u.username, users.role_label(role)))
  end
  return http.new_response():redirect(req:url_for("/admin/users/" .. u.id))
end

local function post_password(req, params)
  local u, err = target(req, params)
  if not u then return err end
  local pw = admin_users.temp_password()
  users.set_password(req.db, u.id, pw)
  signout_all(req.db, u.id)
  log.add(req.db, req, "users.password", u.username)
  return password_shown(req, u, pw, "New password for " .. u.username)
end

local function post_signout(req, params)
  local u, err = target(req, params)
  if not u then return err end
  signout_all(req.db, u.id)
  log.add(req.db, req, "users.signout", u.username)
  session.flash(req, "ok", ("%s is signed out everywhere."):format(u.username))
  return http.new_response():redirect(req:url_for("/admin/users/" .. u.id))
end

local function post_2fa_off(req, params)
  local u, err = target(req, params)
  if not u then return err end
  twofactor.disable(req.db, u.id)
  log.add(req.db, req, "users.2fa_off", u.username)
  session.flash(req, "ok", ("2-step login is off for %s."):format(u.username))
  return http.new_response():redirect(req:url_for("/admin/users/" .. u.id))
end

local function post_delete(req, params)
  local u, err = target(req, params)
  if not u then return err end
  req.db:transaction(function()
    signout_all(req.db, u.id)
    req.db:run("DELETE FROM wc_recovery_codes WHERE user_id = ?", u.id)
    req.db:run("DELETE FROM wc_users WHERE id = ?", u.id)
  end)
  log.add(req.db, req, "users.deleted", u.username)
  session.flash(req, "ok", ("Deleted %s's account."):format(u.username))
  return http.new_response():redirect(req:url_for("/admin/users"))
end

function admin_users.register(r)
  r:get("/admin/users", list, { name = "users", auth = "users.manage" })
  r:get("/admin/users/new", function(req) return new_form(req) end, { auth = "users.manage" })
  r:post("/admin/users/new", post_new, { auth = "users.manage" })
  r:get("/admin/users/:id", function(req, params) return show(req, params) end, { auth = "users.manage" })
  r:post("/admin/users/:id/role", post_role, { auth = "users.manage" })
  r:post("/admin/users/:id/password", post_password, { auth = "users.manage" })
  r:post("/admin/users/:id/signout", post_signout, { auth = "users.manage" })
  r:post("/admin/users/:id/2fa-off", post_2fa_off, { auth = "users.manage" })
  r:post("/admin/users/:id/delete", post_delete, { auth = "users.manage" })
end

return admin_users
