/* WordCore build helper: precompile core Lua files to bytecode.
 * Usage: wcluac <chunkname> <in.lua> <out.luac>
 * Runs on the build machine only; the bytecode is embedded into every target
 * (all 64-bit little-endian with the same Lua config, which Lua checks on load).
 * Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception. */
#include <stdio.h>
#include <stdlib.h>
#include "lua.h"
#include "lauxlib.h"

static int writer(lua_State *L, const void *p, size_t sz, void *ud) {
  (void)L;
  return fwrite(p, 1, sz, (FILE *)ud) == sz ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc != 4) { fprintf(stderr, "usage: wcluac <chunkname> <in> <out>\n"); return 2; }
  FILE *in = fopen(argv[2], "rb");
  if (!in) { perror(argv[2]); return 1; }
  fseek(in, 0, SEEK_END); long n = ftell(in); fseek(in, 0, SEEK_SET);
  char *buf = malloc((size_t)n + 1);
  if (!buf || fread(buf, 1, (size_t)n, in) != (size_t)n) { fprintf(stderr, "read failed\n"); return 1; }
  fclose(in);
  lua_State *L = luaL_newstate();
  if (luaL_loadbufferx(L, buf, (size_t)n, argv[1], "t") != LUA_OK) {
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
    return 1;
  }
  FILE *out = fopen(argv[3], "wb");
  if (!out) { perror(argv[3]); return 1; }
  int r = lua_dump(L, writer, out, 0);   /* keep debug info: errors keep file:line */
  fclose(out);
  lua_close(L);
  return r == 0 ? 0 : 1;
}
