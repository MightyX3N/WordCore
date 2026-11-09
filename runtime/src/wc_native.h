/*
 * WordCore runtime — native modules exposed to Lua.
 * Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
 */
#ifndef WC_NATIVE_H
#define WC_NATIVE_H

#include "lua.h"

/* wc.native: platform, time, filesystem, process info, sockets */
int luaopen_wc_native(lua_State *L);

/* wc.sqlite: minimal SQLite binding */
int luaopen_wc_sqlite(lua_State *L);

/* wc.crypto: Argon2id, BLAKE2b, constant-time compare (Monocypher) */
int luaopen_wc_crypto(lua_State *L);

/* wc.markdown: CommonMark + GFM extensions (cmark-gfm) */
int luaopen_wc_markdown(lua_State *L);

/* Embedded files (core Lua sources), generated at build time */
typedef struct {
  const char *name;
  const unsigned char *data;
  unsigned long size;
} wc_embedded_file;

extern const wc_embedded_file wc_embedded_files[];
extern const unsigned long wc_embedded_count;

const wc_embedded_file *wc_embedded_find(const char *name);

/* Process start time, set by main(), used for request timing */
double wc_now_seconds(void);
extern double wc_process_start;

#endif
