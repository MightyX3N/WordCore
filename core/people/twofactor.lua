-- WordCore — 2-step login (authenticator app codes + one-time recovery codes).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local totp = require("wc.lib.totp")
local crypto = require("wc.lib.crypto")
local html = require("wc.lib.html")
local qrencode = require("wc.vendor.qrencode")
local settings = require("wc.platform.settings")

local esc = html.escape
local twofactor = {}

local function norm_recovery(code) return ((code or ""):lower():gsub("[^%w]", "")) end
local function hash_recovery(code) return crypto.blake2b_hex("wc-recovery:" .. norm_recovery(code), 32) end

function twofactor.enabled(user) return user and user.totp_enabled == 1 end

-- A QR code as inline SVG (no images, no outside services).
function twofactor.qr_svg(text)
  local ok, matrix = qrencode.qrcode(text)
  if not ok then return "" end
  local n = #matrix
  local quiet = 2
  local d = {}
  for x = 1, n do
    for y = 1, n do
      if matrix[x][y] > 0 then d[#d + 1] = ("M%d %dh1v1h-1z"):format(x - 1 + quiet, y - 1 + quiet) end
    end
  end
  local size = n + quiet * 2
  return ('<svg class="wc-qr" viewBox="0 0 %d %d" role="img" aria-label="QR code for your authenticator app" shape-rendering="crispEdges"><rect width="%d" height="%d" fill="#fff"/><path fill="#000" d="%s"/></svg>'):format(
    size, size, size, size, table.concat(d))
end

-- Begin setup: a fresh secret kept in the session until it's confirmed.
function twofactor.setup_secret(req, session)
  local s = req.session.data.totp_setup
  if type(s) ~= "table" or (os.time() - (s.at or 0)) > 1800 then
    s = { secret = totp.new_secret(), at = os.time() }
    session.set(req, "totp_setup", s)
  end
  return s.secret
end

function twofactor.setup_view(req, secret, action, err, classes)
  classes = classes or {}
  local issuer = settings.get(req.db, "site.name")
  local uri = totp.uri(secret, req.user.username, issuer)
  local grouped = secret:gsub("(....)", "%1 "):gsub("%s+$", "")
  return table.concat({
    '<p>Scan this with an authenticator app (Google Authenticator, Microsoft Authenticator, 1Password, Bitwarden…), then type the 6-digit code it shows.</p>',
    twofactor.qr_svg(uri),
    ('<p class="%s">Can\'t scan it? Enter this key instead: <code>%s</code></p>'):format(esc(classes.hint or ""), esc(grouped)),
    ('<form method="post" action="%s" class="%s">'):format(esc(action), esc(classes.form or "")),
    ('<input type="hidden" name="_csrf" value="%s">'):format(esc(req.session.csrf)),
    ('<div class="%s"><label for="totp-code">Code from the app</label><input id="totp-code" name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="7" required class="%s"%s></div>'):format(
      esc(classes.field or ""), esc(classes.input or ""), err and ' aria-invalid="true"' or ""),
    err and ('<p class="%s" role="alert">%s</p>'):format(esc(classes.error or ""), esc(err)) or "",
    ('<button type="submit" class="%s">Turn on 2-step login</button></form>'):format(esc(classes.button or "")),
  })
end

-- Confirm setup with a code. Returns recovery codes (plain, shown once) or nil, error.
function twofactor.confirm(req, db, session, code)
  local secret = req.session.data.totp_setup and req.session.data.totp_setup.secret
  if not secret then return nil, "The setup expired. Start again." end
  local step = totp.verify(secret, code, nil)
  if not step then return nil, "That code didn't match. Check the time on your phone and try again." end
  db:transaction(function()
    db:run("UPDATE wc_users SET totp_secret = ?, totp_enabled = 1, totp_last_step = ? WHERE id = ?", secret, step, req.user.id)
  end)
  session.set(req, "totp_setup", nil)
  return twofactor.new_recovery_codes(db, req.user.id)
end

function twofactor.new_recovery_codes(db, user_id)
  local codes = {}
  db:transaction(function()
    db:run("DELETE FROM wc_recovery_codes WHERE user_id = ?", user_id)
    for _ = 1, 10 do
      local raw = totp.base32_encode(crypto.random(5)):lower()
      local code = raw:sub(1, 4) .. "-" .. raw:sub(5, 8)
      codes[#codes + 1] = code
      db:run("INSERT INTO wc_recovery_codes (user_id, code_hash) VALUES (?, ?)", user_id, hash_recovery(code))
    end
  end)
  return codes
end

function twofactor.remaining_codes(db, user_id)
  return db:first("SELECT COUNT(*) AS n FROM wc_recovery_codes WHERE user_id = ? AND used_at IS NULL", user_id).n
end

function twofactor.disable(db, user_id)
  db:run("UPDATE wc_users SET totp_secret = NULL, totp_enabled = 0, totp_last_step = NULL WHERE id = ?", user_id)
  db:run("DELETE FROM wc_recovery_codes WHERE user_id = ?", user_id)
end

-- Check a sign-in code (authenticator or recovery). Returns true, "totp"|"recovery" or false.
function twofactor.check(db, user, code)
  code = code or ""
  if code:gsub("%s", ""):match("^%d+$") then
    local step = totp.verify(user.totp_secret or "", code, user.totp_last_step)
    if step then
      db:run("UPDATE wc_users SET totp_last_step = ? WHERE id = ?", step, user.id)
      return true, "totp"
    end
    return false
  end
  local h = hash_recovery(code)
  local row = db:first("SELECT id FROM wc_recovery_codes WHERE user_id = ? AND code_hash = ? AND used_at IS NULL", user.id, h)
  if row then
    db:run("UPDATE wc_recovery_codes SET used_at = unixepoch() WHERE id = ?", row.id)
    return true, "recovery"
  end
  return false
end

function twofactor.codes_view(codes, classes)
  classes = classes or {}
  local items = {}
  for _, c in ipairs(codes) do items[#items + 1] = "<li>" .. esc(c) .. "</li>" end
  return ('<p><strong>Save these recovery codes</strong> somewhere safe, like a password manager. Each one works once if you lose your phone. They won\'t be shown again.</p><ul class="%s">%s</ul>'):format(
    esc(classes.codes or ""), table.concat(items))
end

return twofactor
