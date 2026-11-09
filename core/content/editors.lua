-- WordCore — the editor slot. Every content field uses the active editor;
-- the core ships the Markdown editor, addons (Block Editor) can register more.
-- Whatever the editor, the stored content is always Markdown + shortcodes.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local html = require("wc.lib.html")
local settings = require("wc.platform.settings")
local shortcodes = require("wc.content.shortcodes")
local render = require("wc.content.render")

local esc = html.escape
local editors = {}
local registry = {}

-- spec: { id, label, render = function(req, field) -> html }
--   field = { name, value, id, preview_url, media_url }
function editors.register(spec) registry[spec.id] = spec end

function editors.active(db)
  local id = settings.get(db, "content.editor", "markdown")
  return registry[id] or registry.markdown
end

function editors.list()
  local out = {}
  for _, e in pairs(registry) do out[#out + 1] = e end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

local TOOLS = {
  { "h2", "Heading", "H" }, { "bold", "Bold", "B" }, { "italic", "Italic", "I" },
  { "link", "Link", '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M6.5 9.5l3-3M7 4.5l1-1a2.8 2.8 0 014 4l-1 1M9 11.5l-1 1a2.8 2.8 0 01-4-4l1-1" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>' },
  { "ul", "Bulleted list", '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><circle cx="3" cy="4" r="1" fill="currentColor"/><circle cx="3" cy="8" r="1" fill="currentColor"/><circle cx="3" cy="12" r="1" fill="currentColor"/><path d="M6 4h8M6 8h8M6 12h8" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>' },
  { "ol", "Numbered list", "1." },
  { "quote", "Quote", '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M3 4v8M6 5h7M6 8h7M6 11h5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>' },
  { "code", "Code", "&lt;/&gt;" },
  { "image", "Insert image from media", '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="1.5" stroke="currentColor" stroke-width="1.4"/><circle cx="5.5" cy="6" r="1.3" stroke="currentColor" stroke-width="1.2"/><path d="M2 12l4-3.5 3 2.5 2-1.5 3 2.5" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>' },
}

editors.register({
  id = "markdown", label = "Markdown",
  render = function(req, f)
    local tools = {}
    for _, t in ipairs(TOOLS) do
      tools[#tools + 1] = ('<button type="button" class="md-tool" data-md="%s" aria-label="%s" title="%s">%s</button>'):format(t[1], t[2], t[2], t[3])
    end
    local sc = {}
    for _, s in ipairs(shortcodes.list()) do
      sc[#sc + 1] = ('<li><button type="button" data-insert="%s"><strong>%s</strong><span>%s</span></button></li>'):format(
        esc(s.insert or ("[" .. s.name .. "]")), esc(s.label or s.name), esc(s.description or ""))
    end
    local preview_html, missing = render.html(f.value or "", { req = req, preview = true })
    local words = 0
    for _ in (f.value or ""):gmatch("%S+") do words = words + 1 end
    local warn = ""
    if #missing > 0 then
      warn = ('<p class="flash warn">This page uses %s, which no active addon renders. Visitors won\'t see %s.</p>'):format(
        esc("[" .. table.concat(missing, "], [") .. "]"), #missing == 1 and "it" or "them")
    end
    return table.concat({
      warn,
      ('<div class="md-editor" data-preview="%s" data-media="%s">'):format(esc(f.preview_url), esc(f.media_url)),
      '<div class="md-toolbar" role="toolbar" aria-label="Formatting">', table.concat(tools),
      '<details class="md-insert"><summary class="btn btn-sm">Insert shortcode</summary><ul>', table.concat(sc), "</ul></details>",
      '<div class="md-tabs" role="group" aria-label="View"><button type="button" data-view="write">Write</button><button type="button" data-view="split" aria-pressed="true">Split</button><button type="button" data-view="preview">Preview</button></div>',
      "</div>",
      '<div class="md-panes view-split">',
      ('<label class="sr-only" for="%s">Content (Markdown)</label><textarea id="%s" name="%s" class="md-input" spellcheck="true">%s</textarea>'):format(
        esc(f.id), esc(f.id), esc(f.name), esc(f.value or "")),
      '<div class="md-preview" aria-live="polite" aria-label="Preview">', preview_html, "</div>",
      "</div>",
      ('<div class="md-status"><span>Markdown · <span data-words>%d words</span></span><span data-dirty hidden>Unsaved changes</span></div>'):format(words),
      "</div>",
      '<dialog class="md-media" aria-label="Insert image"><div class="md-media-head"><strong>Insert an image</strong><button type="button" class="btn btn-sm" data-close>Close</button></div><div class="md-media-grid" data-grid><p class="muted">Loading…</p></div></dialog>',
    })
  end,
})

return editors
