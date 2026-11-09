-- WordCore — site settings (key -> JSON value) stored in the database.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local json = require("wc.lib.json")

local settings = {}

settings.DEFAULTS = {
  ["site.name"] = "My site",
  ["site.tagline"] = "",
  ["site.language"] = "en",
  ["site.timezone"] = "UTC",
  ["site.run_mode"] = "local",
  ["site.starter"] = "simple",
  ["proxy.trust"] = false,
  ["repo.urls"] = { "https://wordcore.space/repo/" },
}

function settings.migrate(db)
  db:migrate("core.settings", {
    [[CREATE TABLE wc_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT (unixepoch()))]],
  })
end

function settings.get(db, key, default)
  local row = db:first("SELECT value FROM wc_settings WHERE key = ?", key)
  if row then
    local v = json.decode(row.value)
    if v ~= nil and v ~= json.null then return v end
  end
  if default ~= nil then return default end
  return settings.DEFAULTS[key]
end

function settings.set(db, key, value)
  db:run([[INSERT INTO wc_settings (key, value, updated_at) VALUES (?, ?, unixepoch())
           ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at]],
    key, json.encode(value))
end

function settings.set_many(db, values)
  db:transaction(function()
    for k, v in pairs(values) do settings.set(db, k, v) end
  end)
end

return settings
