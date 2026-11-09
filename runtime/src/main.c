/*
 * WordCore runtime — program entry point.
 * Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
 *
 * Starts Lua, registers the native modules and hands control to core/boot.lua,
 * which is embedded in the program at build time. Setting WORDCORE_CORE_DIR
 * makes the program load the core from that folder instead (for development).
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "wc_native.h"

#ifndef WC_VERSION
#define WC_VERSION "0.0.0-dev"
#endif

const wc_embedded_file *wc_embedded_find(const char *name) {
  for (unsigned long i = 0; i < wc_embedded_count; i++) {
    if (strcmp(wc_embedded_files[i].name, name) == 0) return &wc_embedded_files[i];
  }
  return NULL;
}

/* embedded.get(name) -> source | nil */
static int e_get(lua_State *L) {
  const wc_embedded_file *f = wc_embedded_find(luaL_checkstring(L, 1));
  if (!f) return 0;
  lua_pushlstring(L, (const char *)f->data, (size_t)f->size);
  return 1;
}

/* embedded.list() -> { names } */
static int e_list(lua_State *L) {
  lua_createtable(L, (int)wc_embedded_count, 0);
  for (unsigned long i = 0; i < wc_embedded_count; i++) {
    lua_pushstring(L, wc_embedded_files[i].name);
    lua_rawseti(L, -2, (lua_Integer)i + 1);
  }
  return 1;
}

static int luaopen_wc_embedded(lua_State *L) {
  static const luaL_Reg funcs[] = {{"get", e_get}, {"list", e_list}, {NULL, NULL}};
  luaL_newlib(L, funcs);
  return 1;
}

static void preload(lua_State *L, const char *name, lua_CFunction fn) {
  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  lua_pushcfunction(L, fn);
  lua_setfield(L, -2, name);
  lua_pop(L, 1);
}

static int traceback(lua_State *L) {
  const char *msg = lua_tostring(L, 1);
  if (msg == NULL) {
    if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING) return 1;
    msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
  }
  luaL_traceback(L, L, msg, 1);
  return 1;
}

static int load_boot(lua_State *L) {
  const char *dev = getenv("WORDCORE_CORE_DIR");
  if (dev && *dev) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/boot.lua", dev);
    return luaL_loadfilex(L, path, "t");
  }
  const wc_embedded_file *f = wc_embedded_find("core/boot.lua");
  if (!f) {
    lua_pushliteral(L, "core/boot.lua is not embedded in this build");
    return LUA_ERRFILE;
  }
  return luaL_loadbufferx(L, (const char *)f->data, (size_t)f->size, "@core/boot.lua", "t");
}

int main(int argc, char **argv) {
  wc_process_start = wc_now_seconds();
#if !defined(_WIN32)
  signal(SIGPIPE, SIG_IGN);
#endif

  lua_State *L = luaL_newstate();
  if (!L) {
    fputs("wordcore: cannot create Lua state (out of memory)\n", stderr);
    return 1;
  }
  luaL_openlibs(L);
  preload(L, "wc.native", luaopen_wc_native);
  preload(L, "wc.sqlite", luaopen_wc_sqlite);
  preload(L, "wc.embedded", luaopen_wc_embedded);
  preload(L, "wc.crypto", luaopen_wc_crypto);

  lua_pushstring(L, WC_VERSION);
  lua_setglobal(L, "WORDCORE_VERSION");
  lua_pushstring(L, LUA_RELEASE);
  lua_setglobal(L, "LUA_RELEASE");

  lua_pushcfunction(L, traceback);
  int errfunc = lua_gettop(L);

  if (load_boot(L) != LUA_OK) {
    fprintf(stderr, "wordcore: %s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }

  lua_createtable(L, argc, 0);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }

  int status = lua_pcall(L, 1, 1, errfunc);
  int code = 0;
  if (status != LUA_OK) {
    fprintf(stderr, "wordcore: %s\n", lua_tostring(L, -1));
    code = 1;
  } else if (lua_isinteger(L, -1)) {
    code = (int)lua_tointeger(L, -1);
  }
  fflush(stdout);
  lua_close(L);
  return code;
}
