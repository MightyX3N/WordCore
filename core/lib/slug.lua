-- WordCore — turn titles and file names into URL-safe slugs.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local slug = {}

-- Common letters outside ASCII, so "Æblegrød" becomes "aeblegrod".
local MAP = {
  ["æ"] = "ae", ["Æ"] = "ae", ["ø"] = "o", ["Ø"] = "o", ["å"] = "a", ["Å"] = "a",
  ["ä"] = "a", ["Ä"] = "a", ["ö"] = "o", ["Ö"] = "o", ["ü"] = "u", ["Ü"] = "u", ["ß"] = "ss",
  ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["á"] = "a", ["à"] = "a",
  ["â"] = "a", ["ã"] = "a", ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ó"] = "o",
  ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ñ"] = "n",
  ["ç"] = "c", ["ł"] = "l", ["ś"] = "s", ["ź"] = "z", ["ż"] = "z", ["ć"] = "c", ["ń"] = "n",
  ["ę"] = "e", ["ą"] = "a", ["š"] = "s", ["ž"] = "z", ["č"] = "c", ["ř"] = "r", ["ý"] = "y",
  ["’"] = "",
}

function slug.make(text, max)
  text = tostring(text or ""):gsub("'", "")
  text = text:gsub("[\192-\247][\128-\191]*", function(ch) return MAP[ch] or "-" end)
  text = text:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  max = max or 80
  if #text > max then text = text:sub(1, max):gsub("%-+$", "") end
  return text
end

function slug.valid(s)
  return type(s) == "string" and #s >= 1 and #s <= 80 and s:match("^[a-z0-9]+[a-z0-9%-]*$") ~= nil and not s:find("%-%-")
end

return slug
