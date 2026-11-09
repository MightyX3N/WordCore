-- WordCore — language and time zone choices.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local locale = {}

locale.LANGUAGES = {
  { "en", "English" }, { "da", "Dansk" }, { "de", "Deutsch" }, { "nl", "Nederlands" },
  { "sv", "Svenska" }, { "nb", "Norsk" }, { "fi", "Suomi" }, { "fr", "Français" },
  { "es", "Español" }, { "it", "Italiano" }, { "pt", "Português" }, { "pl", "Polski" },
}

locale.TIMEZONES = {
  "UTC",
  "Europe/London", "Europe/Dublin", "Europe/Lisbon", "Europe/Copenhagen", "Europe/Oslo", "Europe/Stockholm",
  "Europe/Helsinki", "Europe/Berlin", "Europe/Amsterdam", "Europe/Brussels", "Europe/Paris", "Europe/Madrid",
  "Europe/Rome", "Europe/Zurich", "Europe/Vienna", "Europe/Prague", "Europe/Warsaw", "Europe/Athens",
  "Europe/Istanbul", "Europe/Kyiv", "Atlantic/Reykjavik",
  "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "America/Anchorage",
  "America/Toronto", "America/Vancouver", "America/Mexico_City", "America/Sao_Paulo", "America/Buenos_Aires",
  "Africa/Johannesburg", "Africa/Lagos", "Africa/Cairo", "Asia/Dubai", "Asia/Kolkata", "Asia/Bangkok",
  "Asia/Singapore", "Asia/Shanghai", "Asia/Tokyo", "Asia/Seoul", "Australia/Perth", "Australia/Sydney",
  "Pacific/Auckland",
}

local function set(list, key)
  local s = {}
  for _, v in ipairs(list) do s[type(v) == "table" and v[key] or v] = true end
  return s
end
local LANG_SET, TZ_SET = set(locale.LANGUAGES, 1), set(locale.TIMEZONES)

function locale.valid_language(code) return LANG_SET[code] == true end
function locale.valid_timezone(tz) return TZ_SET[tz] == true end

function locale.language_options()
  return locale.LANGUAGES
end

function locale.timezone_options()
  local out = {}
  for _, tz in ipairs(locale.TIMEZONES) do out[#out + 1] = { tz, (tz:gsub("_", " ")) } end
  return out
end

return locale
