-- WordCore — shortcodes: [name attr="value"] or [name]inner[/name] in content.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- Addons register shortcodes; content stays Markdown. When nobody renders a
-- shortcode (its addon was removed), visitors see nothing, the editor still
-- shows the text, and the admin lists it as missing.
--
--   shortcodes.register("button", {
--     label = "Button", description = "A link styled as a button",
--     insert = '[button url="/contact" text="Get in touch"]',
--     render = function(attrs, inner, ctx) return '<a class="wc-button" ...>' end,  -- returns HTML
--   })
--
-- What counts as a shortcode (so ordinary [text in brackets] stays text):
-- a registered name, or anything with attributes, a closing tag, or alone on its line.

local html = require("wc.lib.html")

local shortcodes = {}
local registry = {}

function shortcodes.register(name, spec)
  assert(name:match("^[a-z][a-z0-9_%-]*$"), "bad shortcode name")
  spec.name = name
  registry[name] = spec
end

function shortcodes.get(name) return registry[name] end

function shortcodes.list()
  local out = {}
  for _, s in pairs(registry) do out[#out + 1] = s end
  table.sort(out, function(a, b) return (a.label or a.name) < (b.label or b.name) end)
  return out
end

function shortcodes.parse_attrs(s)
  local attrs = {}
  s = s or ""
  for k, v in s:gmatch('([%w_%-]+)%s*=%s*"([^"]*)"') do attrs[k:lower()] = v end
  for k, v in s:gmatch("([%w_%-]+)%s*=%s*'([^']*)'") do attrs[k:lower()] = attrs[k:lower()] or v end
  for k, v in s:gmatch('([%w_%-]+)%s*=%s*([^%s"\'%]]+)') do attrs[k:lower()] = attrs[k:lower()] or v end
  return attrs
end

-- Walk text outside fenced code blocks and inline code, calling fn(segment) on the rest.
local function map_outside_code(text, fn)
  local out = {}
  local in_fence, fence = false, nil
  for line, nl in text:gmatch("([^\n]*)(\n?)") do
    if line == "" and nl == "" then break end
    local marker = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if in_fence then
      out[#out + 1] = line .. nl
      if marker and marker:sub(1, 1) == fence:sub(1, 1) and #marker >= #fence then in_fence = false end
    elseif marker then
      in_fence, fence = true, marker
      out[#out + 1] = line .. nl
    else
      -- protect `inline code`
      local parts, last = {}, 1
      for s, code, e in line:gmatch("()(`+[^`]-`+)()") do
        parts[#parts + 1] = fn(line:sub(last, s - 1), line)
        parts[#parts + 1] = code
        last = e
      end
      parts[#parts + 1] = fn(line:sub(last), line)
      out[#out + 1] = table.concat(parts) .. nl
    end
  end
  return table.concat(out)
end

local function is_shortcode(name, attrs_text, has_close, alone)
  return registry[name] ~= nil or attrs_text:find("=") ~= nil or has_close or alone
end

-- Find shortcodes. Calls on_code(name, attrs, inner, raw) -> replacement text.
function shortcodes.transform(text, on_code)
  -- 1) enclosing shortcodes on one or more lines: [name ...]inner[/name]
  text = text:gsub("%[([a-z][a-z0-9_%-]*)([^%]\n]*)%](.-)%[/%1%]", function(name, attrs_text, inner)
    return on_code(name, shortcodes.parse_attrs(attrs_text), inner, nil)
  end)
  -- 2) single shortcodes, skipping code; [[name]] is an escape for a literal [name]
  return map_outside_code(text, function(seg, line)
    return (seg:gsub("(%[?)%[([a-z][a-z0-9_%-]*)([^%]\n]*)%](%]?)(.?)", function(open2, name, attrs_text, close2, after)
      if open2 == "[" and close2 == "]" then return "[" .. name .. attrs_text .. "]" .. after end
      if after == "(" or after == "[" or after == ":" then return nil end -- a Markdown link
      local raw = "[" .. name .. attrs_text .. "]"
      local alone = line:match("^%s*" .. raw:gsub("%p", "%%%0") .. "%s*$") ~= nil
      if attrs_text ~= "" and not attrs_text:match("^%s") then return nil end
      if not is_shortcode(name, attrs_text, false, alone) then return nil end
      return open2 .. on_code(name, shortcodes.parse_attrs(attrs_text), nil, raw) .. close2 .. after
    end))
  end)
end

-- Names of shortcodes used in text that nothing renders.
function shortcodes.missing(text)
  local seen, list = {}, {}
  shortcodes.transform(text or "", function(name)
    if not registry[name] and not seen[name] then seen[name] = true list[#list + 1] = name end
    return ""
  end)
  return list
end

---------------------------------------------------------------- built-in shortcodes

shortcodes.register("button", {
  label = "Button", description = "A link that looks like a button.",
  insert = '[button url="/contact" text="Get in touch"]',
  render = function(attrs)
    local url = attrs.url or "#"
    if url:match("^%s*[%a][%w+.-]*:") and not url:match("^https?:") and not url:match("^mailto:") then url = "#" end
    return ('<a class="wc-button" href="%s">%s</a>'):format(html.escape(url), html.escape(attrs.text or "Button"))
  end,
})

return shortcodes
