/*
 * WordCore runtime — wc.sqlite: a small SQLite binding.
 * Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
 *
 * Only what the core needs: open, exec, prepared statements with bound values.
 * Friendlier helpers (query, transactions, migrations) live in Lua.
 */
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "sqlite3.h"
#include "wc_native.h"

#define DB_MT   "wc.sqlite.db"
#define STMT_MT "wc.sqlite.stmt"

typedef struct { sqlite3 *db; } wc_db;
typedef struct { sqlite3_stmt *st; int dbref; } wc_stmt;

static wc_db *check_db(lua_State *L, int idx) {
  wc_db *d = (wc_db *)luaL_checkudata(L, idx, DB_MT);
  if (!d->db) luaL_error(L, "database is closed");
  return d;
}

static wc_stmt *check_stmt(lua_State *L, int idx) {
  wc_stmt *s = (wc_stmt *)luaL_checkudata(L, idx, STMT_MT);
  if (!s->st) luaL_error(L, "statement is finalized");
  return s;
}

static int push_db_error(lua_State *L, sqlite3 *db) {
  lua_pushnil(L);
  lua_pushstring(L, db ? sqlite3_errmsg(db) : "out of memory");
  return 2;
}

/* open(path) -> db | nil, err */
static int l_open(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  wc_db *d = (wc_db *)lua_newuserdatauv(L, sizeof(wc_db), 0);
  d->db = NULL;
  luaL_setmetatable(L, DB_MT);
  int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX;
  if (sqlite3_open_v2(path, &d->db, flags, NULL) != SQLITE_OK) {
    int r = push_db_error(L, d->db);
    if (d->db) { sqlite3_close(d->db); d->db = NULL; }
    return r;
  }
  sqlite3_extended_result_codes(d->db, 1);
  sqlite3_busy_timeout(d->db, 5000);
  return 1;
}

static int l_version(lua_State *L) {
  lua_pushstring(L, sqlite3_libversion());
  return 1;
}

static int db_close(lua_State *L) {
  wc_db *d = (wc_db *)luaL_checkudata(L, 1, DB_MT);
  if (d->db) {
    sqlite3_close_v2(d->db);
    d->db = NULL;
  }
  return 0;
}

static int db_exec(lua_State *L) {
  wc_db *d = check_db(L, 1);
  const char *sql = luaL_checkstring(L, 2);
  char *err = NULL;
  if (sqlite3_exec(d->db, sql, NULL, NULL, &err) != SQLITE_OK) {
    lua_pushnil(L);
    lua_pushstring(L, err ? err : sqlite3_errmsg(d->db));
    sqlite3_free(err);
    return 2;
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int db_prepare(lua_State *L) {
  wc_db *d = check_db(L, 1);
  size_t len;
  const char *sql = luaL_checklstring(L, 2, &len);
  wc_stmt *s = (wc_stmt *)lua_newuserdatauv(L, sizeof(wc_stmt), 0);
  s->st = NULL;
  s->dbref = LUA_NOREF;
  luaL_setmetatable(L, STMT_MT);
  if (sqlite3_prepare_v2(d->db, sql, (int)len, &s->st, NULL) != SQLITE_OK) {
    return push_db_error(L, d->db);
  }
  if (!s->st) {  /* empty statement */
    lua_pushnil(L);
    lua_pushstring(L, "empty SQL statement");
    return 2;
  }
  /* keep the database alive while the statement exists */
  lua_pushvalue(L, 1);
  s->dbref = luaL_ref(L, LUA_REGISTRYINDEX);
  return 1;
}

static int db_changes(lua_State *L) {
  wc_db *d = check_db(L, 1);
  lua_pushinteger(L, (lua_Integer)sqlite3_changes64(d->db));
  return 1;
}

static int db_last_id(lua_State *L) {
  wc_db *d = check_db(L, 1);
  lua_pushinteger(L, (lua_Integer)sqlite3_last_insert_rowid(d->db));
  return 1;
}

static int db_busy_timeout(lua_State *L) {
  wc_db *d = check_db(L, 1);
  sqlite3_busy_timeout(d->db, (int)luaL_checkinteger(L, 2));
  return 0;
}

static int db_errmsg(lua_State *L) {
  wc_db *d = check_db(L, 1);
  lua_pushstring(L, sqlite3_errmsg(d->db));
  return 1;
}

/* ------------------------------------------------------------ statements */

static int bind_one(lua_State *L, sqlite3_stmt *st, int i, int idx) {
  switch (lua_type(L, idx)) {
    case LUA_TNIL:
      return sqlite3_bind_null(st, i);
    case LUA_TBOOLEAN:
      return sqlite3_bind_int(st, i, lua_toboolean(L, idx));
    case LUA_TNUMBER:
      if (lua_isinteger(L, idx))
        return sqlite3_bind_int64(st, i, (sqlite3_int64)lua_tointeger(L, idx));
      return sqlite3_bind_double(st, i, lua_tonumber(L, idx));
    case LUA_TSTRING: {
      size_t len;
      const char *s = lua_tolstring(L, idx, &len);
      return sqlite3_bind_text64(st, i, s, (sqlite3_uint64)len, SQLITE_TRANSIENT, SQLITE_UTF8);
    }
    default:
      return luaL_error(L, "cannot bind a %s to parameter %d", luaL_typename(L, idx), i);
  }
}

/* stmt:bind(v1, v2, ...) — binds positional parameters, or one table of named ones */
static int stmt_bind(lua_State *L) {
  wc_stmt *s = check_stmt(L, 1);
  sqlite3_reset(s->st);
  sqlite3_clear_bindings(s->st);
  int top = lua_gettop(L);
  if (top == 2 && lua_istable(L, 2)) {
    int n = sqlite3_bind_parameter_count(s->st);
    for (int i = 1; i <= n; i++) {
      const char *name = sqlite3_bind_parameter_name(s->st, i);
      if (name) lua_getfield(L, 2, name + 1);  /* skip ':' / '@' / '$' */
      else lua_rawgeti(L, 2, i);
      if (bind_one(L, s->st, i, -1) != SQLITE_OK) {
        lua_pop(L, 1);
        return push_db_error(L, sqlite3_db_handle(s->st));
      }
      lua_pop(L, 1);
    }
  } else {
    for (int i = 2; i <= top; i++) {
      if (bind_one(L, s->st, i - 1, i) != SQLITE_OK)
        return push_db_error(L, sqlite3_db_handle(s->st));
    }
  }
  lua_settop(L, 1);
  return 1;
}

/* stmt:step() -> "row" | "done" | nil, err */
static int stmt_step(lua_State *L) {
  wc_stmt *s = check_stmt(L, 1);
  int rc = sqlite3_step(s->st);
  if (rc == SQLITE_ROW) { lua_pushliteral(L, "row"); return 1; }
  if (rc == SQLITE_DONE) { lua_pushliteral(L, "done"); return 1; }
  int r = push_db_error(L, sqlite3_db_handle(s->st));
  sqlite3_reset(s->st);
  return r;
}

static void push_column(lua_State *L, sqlite3_stmt *st, int i) {
  switch (sqlite3_column_type(st, i)) {
    case SQLITE_INTEGER:
      lua_pushinteger(L, (lua_Integer)sqlite3_column_int64(st, i));
      break;
    case SQLITE_FLOAT:
      lua_pushnumber(L, sqlite3_column_double(st, i));
      break;
    case SQLITE_TEXT:
    case SQLITE_BLOB: {
      const void *p = sqlite3_column_blob(st, i);
      int n = sqlite3_column_bytes(st, i);
      lua_pushlstring(L, p ? (const char *)p : "", (size_t)n);
      break;
    }
    default:
      lua_pushnil(L);
  }
}

/* stmt:row() -> { column = value, ... } for the current row */
static int stmt_row(lua_State *L) {
  wc_stmt *s = check_stmt(L, 1);
  int n = sqlite3_data_count(s->st);
  lua_createtable(L, 0, n);
  for (int i = 0; i < n; i++) {
    push_column(L, s->st, i);
    lua_setfield(L, -2, sqlite3_column_name(s->st, i));
  }
  return 1;
}

static int stmt_reset(lua_State *L) {
  wc_stmt *s = check_stmt(L, 1);
  sqlite3_reset(s->st);
  return 0;
}

static int stmt_finalize(lua_State *L) {
  wc_stmt *s = (wc_stmt *)luaL_checkudata(L, 1, STMT_MT);
  if (s->st) {
    sqlite3_finalize(s->st);
    s->st = NULL;
  }
  if (s->dbref != LUA_NOREF) {
    luaL_unref(L, LUA_REGISTRYINDEX, s->dbref);
    s->dbref = LUA_NOREF;
  }
  return 0;
}

static const luaL_Reg db_methods[] = {
  {"close", db_close},
  {"exec", db_exec},
  {"prepare", db_prepare},
  {"changes", db_changes},
  {"last_insert_id", db_last_id},
  {"busy_timeout", db_busy_timeout},
  {"errmsg", db_errmsg},
  {NULL, NULL}
};

static const luaL_Reg stmt_methods[] = {
  {"bind", stmt_bind},
  {"step", stmt_step},
  {"row", stmt_row},
  {"reset", stmt_reset},
  {"finalize", stmt_finalize},
  {NULL, NULL}
};

static const luaL_Reg module_funcs[] = {
  {"open", l_open},
  {"version", l_version},
  {NULL, NULL}
};

static void make_mt(lua_State *L, const char *name, const luaL_Reg *methods, lua_CFunction gc) {
  luaL_newmetatable(L, name);
  lua_newtable(L);
  luaL_setfuncs(L, methods, 0);
  lua_setfield(L, -2, "__index");
  lua_pushcfunction(L, gc);
  lua_setfield(L, -2, "__gc");
  lua_pushcfunction(L, gc);
  lua_setfield(L, -2, "__close");
  lua_pop(L, 1);
}

int luaopen_wc_sqlite(lua_State *L) {
  make_mt(L, DB_MT, db_methods, db_close);
  make_mt(L, STMT_MT, stmt_methods, stmt_finalize);
  luaL_newlib(L, module_funcs);
  return 1;
}
