-- WordCore — activity log (logins, settings changes, setup...).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local log = {}

function log.migrate(db)
  db:migrate("core.log", {
    [[CREATE TABLE wc_log (
        id INTEGER PRIMARY KEY,
        at INTEGER NOT NULL DEFAULT (unixepoch()),
        user_id INTEGER,
        ip TEXT,
        action TEXT NOT NULL,
        detail TEXT)]],
    "CREATE INDEX wc_log_at ON wc_log (at)",
  })
end

-- log.add(db, req, "login", "detail")   (req may be nil)
function log.add(db, req, action, detail)
  local user_id = req and req.user and req.user.id or nil
  local ip = req and req.client_ip or nil
  db:run("INSERT INTO wc_log (user_id, ip, action, detail) VALUES (?, ?, ?, ?)", user_id, ip, action, detail)
  -- keep the log from growing forever
  if math.random(1, 200) == 1 then
    db:run("DELETE FROM wc_log WHERE at < unixepoch() - 180 * 86400")
  end
end

function log.recent(db, limit)
  return db:query([[SELECT l.*, u.username FROM wc_log l LEFT JOIN wc_users u ON u.id = l.user_id
                    ORDER BY l.id DESC LIMIT ?]], limit or 10)
end

return log
