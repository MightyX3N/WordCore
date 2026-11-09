-- WordCore — turn stored content (Markdown + shortcodes) into HTML.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local markdown = require("wc.markdown")
local shortcodes = require("wc.content.shortcodes")

local render = {}

-- render.html(text, ctx) -> html, missing_shortcodes
--   ctx.preview = true marks missing shortcodes visibly (editor preview)
function render.html(text, ctx)
  ctx = ctx or {}
  local blocks, missing, seen = {}, {}, {}
  local n = 0
  local prepared = shortcodes.transform(text or "", function(name, attrs, inner, raw)
    local spec = shortcodes.get(name)
    local out
    if spec then
      local ok, res = pcall(spec.render, attrs, inner and render.html(inner, ctx) or nil, ctx)
      out = ok and tostring(res or "") or ('<!-- shortcode ' .. name .. ' failed -->')
      if not ok then io.stderr:write("wordcore: shortcode [", name, "] failed: ", tostring(res), "\n") end
    else
      if not seen[name] then seen[name] = true missing[#missing + 1] = name end
      if ctx.preview then
        out = ('<div class="wc-missing-shortcode"><strong>[%s]</strong> isn\'t rendered by any active addon. Visitors won\'t see anything here.</div>'):format(name)
      else
        out = ""
      end
    end
    n = n + 1
    blocks[n] = out
    return "WCSHORTCODE" .. n .. "X"
  end)
  local htmlout = markdown.render(prepared)
  -- a shortcode alone on its line becomes its own block, not wrapped in <p>
  htmlout = htmlout:gsub("<p>WCSHORTCODE(%d+)X</p>\n?", function(i) return blocks[tonumber(i)] .. "\n" end)
  htmlout = htmlout:gsub("WCSHORTCODE(%d+)X", function(i) return blocks[tonumber(i)] end)
  -- Content links to the site with root paths ("/about", "/media/x.jpg");
  -- prefix them when the site lives in a subfolder.
  local base = ctx.req and ctx.req.base_path or ""
  if base ~= "" then
    htmlout = htmlout:gsub('( [hs][rc][ec]f?=")(/[^/"])', function(attr, rest)
      if attr ~= ' href="' and attr ~= ' src="' then return attr .. rest end
      return attr .. base .. rest
    end)
  end
  return htmlout, missing
end

function render.text(text)
  local stripped = shortcodes.transform(text or "", function() return "" end)
  return markdown.text(stripped)
end

-- Short plain-text summary, e.g. for search results or meta descriptions.
function render.excerpt(text, max)
  max = max or 160
  local plain = render.text(text):gsub("%s+", " "):gsub("^%s+", "")
  if #plain <= max then return plain end
  local cut = plain:sub(1, max):match("^(.*)%s") or plain:sub(1, max)
  return cut .. "…"
end

return render
