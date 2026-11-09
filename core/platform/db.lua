-- WordCore — database helpers on top of the native SQLite binding.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
--   local conn = db.open(path)
--   conn:exec(sql)                         -- run statements, no results
--   conn:query(sql, ...)  -> { rows }      -- all rows as tables
--   conn:first(sql, ...)  -> row | nil
--   conn:run(sql, ...)    -> changes, last_insert_id
--   conn:transaction(function() ... end)   -- commits, or rolls back on error
--   conn:migrate(name, { [1] = sql, [2] = sql, ... })

local sqlite = require("wc.sqlite")

local db = {}

local Conn = {}
Conn.__index = Conn

function db.open(file)
  local handle, err = sqlite.open(file)
  if not handle then return nil, err end
  local conn = setmetatable({ handle = handle, file = file, cache = {} }, Conn)
  local ok, perr = conn:pragmas()
  if not ok then handle:close() return nil, perr end
  return conn
end

function Conn:pragmas()
  local mode = self:first("PRAGMA journal_mode = WAL")
  self.journal_mode = mode and mode.journal_mode or "unknown"
  local ok, err = self.handle:exec("PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
  if not ok then return nil, err end
  return true
end

local function check(ok, err, sql)
  if not ok then error(("database error: %s\n  in: %s"):format(err, sql), 3) end
  return ok
end

function Conn:statement(sql)
  local st = self.cache[sql]
  if not st then
    st = check(self.handle:prepare(sql))
    self.cache[sql] = st
  end
  return st
end

function Conn:exec(sql)
  local ok, err = self.handle:exec(sql)
  check(ok, err, sql)
  return true
end

local function bind(st, sql, ...)
  if select("#", ...) > 0 then
    local ok, err = st:bind(...)
    if not ok then check(nil, err, sql) end
  else
    st:reset()
  end
end

function Conn:query(sql, ...)
  local st = self:statement(sql)
  bind(st, sql, ...)
  local rows = {}
  while true do
    local r, err = st:step()
    if r == "row" then
      rows[#rows + 1] = st:row()
    elseif r == "done" then
      break
    else
      st:reset()
      check(nil, err, sql)
    end
  end
  st:reset()
  return rows
end

function Conn:first(sql, ...)
  local st = self:statement(sql)
  bind(st, sql, ...)
  local r, err = st:step()
  local row
  if r == "row" then row = st:row() elseif r ~= "done" then st:reset() check(nil, err, sql) end
  st:reset()
  return row
end

function Conn:run(sql, ...)
  local st = self:statement(sql)
  bind(st, sql, ...)
  local r, err = st:step()
  st:reset()
  if r ~= "done" and r ~= "row" then check(nil, err, sql) end
  return self.handle:changes(), self.handle:last_insert_id()
end

function Conn:transaction(fn)
  self:exec("BEGIN IMMEDIATE")
  local ok, err = pcall(fn, self)
  if ok then
    self:exec("COMMIT")
    return true
  end
  self.handle:exec("ROLLBACK")
  error(err, 0)
end

-- Apply numbered migration steps once each, tracked per name.
function Conn:migrate(name, steps)
  self:exec([[CREATE TABLE IF NOT EXISTS wc_migrations (
    name TEXT NOT NULL, step INTEGER NOT NULL, applied_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (name, step))]])
  local done = {}
  for _, row in ipairs(self:query("SELECT step FROM wc_migrations WHERE name = ?", name)) do
    done[row.step] = true
  end
  for i, sql in ipairs(steps) do
    if not done[i] then
      self:transaction(function(c)
        c:exec(sql)
        c:run("INSERT INTO wc_migrations (name, step) VALUES (?, ?)", name, i)
      end)
    end
  end
end

function Conn:close()
  for _, st in pairs(self.cache) do st:finalize() end
  self.cache = {}
  if self.handle then self.handle:close() self.handle = nil end
end

return db
