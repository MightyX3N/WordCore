-- WordCore — admin UI kit: build consistent admin screens from plain Lua tables.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Everything here escapes its input. Addons will use this same kit, so a
-- settings screen is a list of fields, not hand-written HTML:
--
--   ui.form{ action = url, csrf = token, submit = "Save", sections = {
--     { title = "Site", fields = {
--       { name = "site.name", label = "Site name", type = "text", required = true, max = 80, value = v, error = e },
--     }},
--   }}

local html = require("wc.lib.html")
local esc = html.escape

local ui = {}

local function attrs(t)
  local out = {}
  for k, v in pairs(t) do
    if v == true then out[#out + 1] = " " .. k
    elseif v ~= nil and v ~= false then out[#out + 1] = (' %s="%s"'):format(k, esc(v)) end
  end
  table.sort(out)
  return table.concat(out)
end
ui.attrs = attrs

local function field_id(name) return "f-" .. tostring(name):gsub("[^%w]", "-") end

---------------------------------------------------------------- fields

local function input_field(f)
  local id = field_id(f.name)
  local value = f.value
  if f.type == "password" then value = nil end
  local described = {}
  if f.hint then described[#described + 1] = id .. "-hint" end
  if f.error then described[#described + 1] = id .. "-err" end
  local a = {
    id = id, name = f.name, type = f.type or "text", value = value, required = f.required,
    maxlength = f.max, minlength = f.min_length, placeholder = f.placeholder, autocomplete = f.autocomplete,
    class = "input" .. (f.mono and " mono" or "") .. (f.class and (" " .. f.class) or ""),
    ["aria-invalid"] = f.error and "true" or nil,
    ["aria-describedby"] = #described > 0 and table.concat(described, " ") or nil,
    autofocus = f.autofocus, spellcheck = f.spellcheck, inputmode = f.inputmode, readonly = f.readonly,
    ["data-strength"] = f.strength and (id .. "-meter") or nil,
  }
  if f.type == "textarea" then
    a.type, a.value = nil, nil
    a.rows = f.rows or 4
    return ("<textarea%s>%s</textarea>"):format(attrs(a), esc(value or ""))
  elseif f.type == "select" then
    a.type, a.value = nil, nil
    local opts = {}
    for _, o in ipairs(f.options or {}) do
      local ov, ol = o[1], o[2] or o[1]
      opts[#opts + 1] = ("<option%s>%s</option>"):format(attrs({ value = ov, selected = tostring(ov) == tostring(value) }), esc(ol))
    end
    return ("<select%s>%s</select>"):format(attrs(a), table.concat(opts))
  end
  return ("<input%s>"):format(attrs(a))
end

function ui.field(f)
  if f.type == "hidden" then
    return ('<input type="hidden" name="%s" value="%s">'):format(esc(f.name), esc(f.value or ""))
  end
  local id = field_id(f.name)
  if f.type == "checkbox" then
    local out = { ('<div class="field%s">'):format(f.error and " has-error" or "") }
    out[#out + 1] = ('<label class="checkbox"><input%s><span>%s%s</span></label>'):format(
      attrs({ type = "checkbox", id = id, name = f.name, value = "1", checked = f.value == true }),
      esc(f.label), f.hint and ('<br><span class="hint">' .. esc(f.hint) .. "</span>") or "")
    if f.error then out[#out + 1] = ('<p class="error-text" id="%s-err">%s</p>'):format(id, esc(f.error)) end
    out[#out + 1] = "</div>"
    return table.concat(out)
  end
  if f.type == "choice" then
    return ui.choices(f)
  end
  local out = { ('<div class="field%s">'):format(f.error and " has-error" or "") }
  out[#out + 1] = ('<label for="%s">%s%s</label>'):format(id, esc(f.label),
    f.optional and ' <span class="optional">(optional)</span>' or "")
  out[#out + 1] = input_field(f)
  if f.strength then
    out[#out + 1] = ('<div class="strength" id="%s-meter" aria-hidden="true"><span></span><span></span><span></span><span></span></div>'):format(id)
    out[#out + 1] = ('<p class="hint" id="%s-meter-label" data-default="%s">%s</p>'):format(id, esc(f.hint or ""), esc(f.hint or ""))
  elseif f.hint then
    out[#out + 1] = ('<p class="hint" id="%s-hint">%s</p>'):format(id, esc(f.hint))
  end
  if f.error then out[#out + 1] = ('<p class="error-text" id="%s-err">%s</p>'):format(id, esc(f.error)) end
  out[#out + 1] = "</div>"
  return table.concat(out)
end

-- Radio cards: { name, label, value, options = { {value, title, desc, badge, disabled} }, grid = true }
function ui.choices(f)
  local out = { ('<fieldset class="field"><legend class="label sr-only">%s</legend><div class="choices%s">'):format(
    esc(f.label or f.name), f.grid and " grid-2" or "") }
  for _, o in ipairs(f.options) do
    out[#out + 1] = ('<label class="choice"><input%s><span class="choice-mark" aria-hidden="true"></span><span class="choice-body"><span class="choice-title">%s%s</span>%s</span></label>'):format(
      attrs({ type = "radio", name = f.name, value = o.value, checked = tostring(o.value) == tostring(f.value), disabled = o.disabled }),
      esc(o.title), o.badge and (' <span class="badge ' .. esc(o.badge_kind or "ok") .. '">' .. esc(o.badge) .. "</span>") or "",
      o.desc and ('<span class="choice-desc">' .. esc(o.desc) .. "</span>") or "")
  end
  out[#out + 1] = "</div>"
  if f.error then out[#out + 1] = ('<p class="error-text">%s</p>'):format(esc(f.error)) end
  out[#out + 1] = "</fieldset>"
  return table.concat(out)
end

function ui.csrf(token)
  return ('<input type="hidden" name="_csrf" value="%s">'):format(esc(token or ""))
end

-- A whole form, optionally split into titled sections (each rendered as a card).
function ui.form(spec)
  local out = { ('<form method="post" action="%s" class="form"%s novalidate>'):format(esc(spec.action),
    spec.confirm and (' data-confirm="' .. esc(spec.confirm) .. '"') or ""), ui.csrf(spec.csrf) }
  if spec.sections then
    for _, sec in ipairs(spec.sections) do
      out[#out + 1] = '<section class="card">'
      if sec.title then
        out[#out + 1] = ('<div class="card-head"><h2>%s</h2>%s</div>'):format(esc(sec.title),
          sec.badge and ('<span class="badge">' .. esc(sec.badge) .. "</span>") or "")
      end
      out[#out + 1] = '<div class="card-body">'
      if sec.intro then out[#out + 1] = ('<p class="muted small">%s</p>'):format(esc(sec.intro)) end
      for _, f in ipairs(sec.fields) do out[#out + 1] = ui.field(f) end
      out[#out + 1] = "</div></section>"
    end
  else
    for _, f in ipairs(spec.fields or {}) do out[#out + 1] = ui.field(f) end
  end
  if spec.submit then
    out[#out + 1] = ('<div class="actions"><button type="submit" class="btn btn-primary">%s</button></div>'):format(esc(spec.submit))
  end
  out[#out + 1] = "</form>"
  return table.concat(out)
end

---------------------------------------------------------------- display

function ui.badge(text, kind)
  return ('<span class="badge %s">%s</span>'):format(esc(kind or ""), esc(text))
end

function ui.flash(messages)
  local out = {}
  for _, m in ipairs(messages or {}) do
    out[#out + 1] = ('<div class="flash %s" role="%s">%s</div>'):format(esc(m.kind), m.kind == "bad" and "alert" or "status", esc(m.text))
  end
  return table.concat(out)
end

-- items: { { state = "ok"|"warn"|"bad", html = "...already escaped..." } }
function ui.checks(items)
  local icon = { ok = "✓", warn = "!", bad = "×" }
  local label = { ok = "OK", warn = "Warning", bad = "Problem" }
  local out = { '<ul class="checks">' }
  for _, it in ipairs(items) do
    out[#out + 1] = ('<li><span class="check-icon %s" role="img" aria-label="%s">%s</span><span>%s</span></li>'):format(
      it.state, label[it.state], icon[it.state], it.html)
  end
  out[#out + 1] = "</ul>"
  return table.concat(out)
end

function ui.card(title, body_html, opts)
  opts = opts or {}
  return ('<section class="card"%s><div class="card-head"><h2%s>%s</h2>%s</div>%s</section>'):format(
    opts.id and (' aria-labelledby="' .. esc(opts.id) .. '"') or "",
    opts.id and (' id="' .. esc(opts.id) .. '"') or "",
    esc(title), opts.aside or "", body_html)
end

-- Human-friendly "3 min ago"
function ui.ago(t)
  if not t then return "never" end
  local d = os.time() - t
  if d < 60 then return "just now" end
  if d < 3600 then return ("%d min ago"):format(d // 60) end
  if d < 86400 then return ("%d h ago"):format(d // 3600) end
  if d < 2 * 86400 then return "yesterday" end
  if d < 30 * 86400 then return ("%d days ago"):format(d // 86400) end
  return os.date("%Y-%m-%d", t)
end

function ui.bytes(n)
  if n < 1024 then return n .. " B" end
  if n < 1024 * 1024 then return ("%.0f KB"):format(n / 1024) end
  return ("%.1f MB"):format(n / 1048576)
end

return ui
