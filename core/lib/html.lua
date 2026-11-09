-- WordCore — HTML helpers.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local html = {}

local entities = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }

-- Escape text for use in HTML element content or a quoted attribute.
function html.escape(s)
  if s == nil then return "" end
  return (tostring(s):gsub("[&<>\"']", entities))
end

return html
