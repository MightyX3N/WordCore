-- WordCore — simple fixed-window rate limits stored in the database.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
--   local ok, retry_after = ratelimit.hit(db, "login:ip:1.2.3.4", 20, 900)
--   ratelimit.clear(db, "login:user:alice")

local ratelimit = {}

function ratelimit.migrate(db)
  db:migrate("core.ratelimit", {
    [[CREATE TABLE wc_rate (key TEXT PRIMARY KEY, count INTEGER NOT NULL, reset_at INTEGER NOT NULL)]],
  })
end

-- Count one attempt. Returns true if allowed, or false + seconds until allowed again.
function ratelimit.hit(db, key, limit, window)
  local now = os.time()
  local row = db:first("SELECT count, reset_at FROM wc_rate WHERE key = ?", key)
  if not row or row.reset_at <= now then
    db:run([[INSERT INTO wc_rate (key, count, reset_at) VALUES (?, 1, ?)
             ON CONFLICT(key) DO UPDATE SET count = 1, reset_at = excluded.reset_at]], key, now + window)
    return true
  end
  if row.count >= limit then
    return false, row.reset_at - now
  end
  db:run("UPDATE wc_rate SET count = count + 1 WHERE key = ?", key)
  return true
end

-- Is the key over its limit right now (without counting an attempt)?
function ratelimit.blocked(db, key, limit)
  local row = db:first("SELECT count, reset_at FROM wc_rate WHERE key = ?", key)
  if row and row.reset_at > os.time() and row.count >= limit then
    return true, row.reset_at - os.time()
  end
  return false
end

function ratelimit.clear(db, key)
  db:run("DELETE FROM wc_rate WHERE key = ?", key)
end

function ratelimit.cleanup(db)
  db:run("DELETE FROM wc_rate WHERE reset_at <= ?", os.time())
end

return ratelimit
