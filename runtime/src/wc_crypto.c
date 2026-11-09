/*
 * WordCore runtime — wc.crypto: password hashing and hashing via Monocypher.
 * Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
 *
 * Raw primitives only; encoding (PHC strings, base64, hex) is done in Lua.
 */
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "monocypher.h"
#include "wc_native.h"

/* argon2id(password, salt, memory_kib, passes, lanes [, length]) -> raw hash */
static int c_argon2id(lua_State *L) {
  size_t pass_len, salt_len;
  const char *pass = luaL_checklstring(L, 1, &pass_len);
  const char *salt = luaL_checklstring(L, 2, &salt_len);
  lua_Integer mem = luaL_checkinteger(L, 3);
  lua_Integer passes = luaL_checkinteger(L, 4);
  lua_Integer lanes = luaL_optinteger(L, 5, 1);
  lua_Integer len = luaL_optinteger(L, 6, 32);
  luaL_argcheck(L, salt_len >= 8, 2, "salt must be at least 8 bytes");
  luaL_argcheck(L, lanes >= 1 && lanes <= 16, 5, "lanes out of range");
  luaL_argcheck(L, mem >= 8 * lanes && mem <= 1024 * 1024, 3, "memory out of range");
  luaL_argcheck(L, passes >= 1 && passes <= 64, 4, "passes out of range");
  luaL_argcheck(L, len >= 16 && len <= 64, 6, "length out of range");
  luaL_argcheck(L, pass_len <= 4096, 1, "password too long");

  void *work = malloc((size_t)mem * 1024);
  if (!work) return luaL_error(L, "not enough memory for password hashing");

  uint8_t out[64];
  crypto_argon2_config config;
  config.algorithm = CRYPTO_ARGON2_ID;
  config.nb_blocks = (uint32_t)mem;
  config.nb_passes = (uint32_t)passes;
  config.nb_lanes = (uint32_t)lanes;
  crypto_argon2_inputs inputs;
  inputs.pass = (const uint8_t *)pass;
  inputs.pass_size = (uint32_t)pass_len;
  inputs.salt = (const uint8_t *)salt;
  inputs.salt_size = (uint32_t)salt_len;
  crypto_argon2(out, (uint32_t)len, work, config, inputs, crypto_argon2_no_extras);

  crypto_wipe(work, (size_t)mem * 1024);
  free(work);
  lua_pushlstring(L, (const char *)out, (size_t)len);
  crypto_wipe(out, sizeof(out));
  return 1;
}

/* blake2b(data [, size [, key]]) -> raw hash (size 1..64, default 32) */
static int c_blake2b(lua_State *L) {
  size_t len, key_len = 0;
  const char *data = luaL_checklstring(L, 1, &len);
  lua_Integer size = luaL_optinteger(L, 2, 32);
  const char *key = luaL_optlstring(L, 3, NULL, &key_len);
  luaL_argcheck(L, size >= 1 && size <= 64, 2, "size out of range");
  luaL_argcheck(L, key_len <= 64, 3, "key too long");
  uint8_t out[64];
  if (key && key_len > 0)
    crypto_blake2b_keyed(out, (size_t)size, (const uint8_t *)key, key_len, (const uint8_t *)data, len);
  else
    crypto_blake2b(out, (size_t)size, (const uint8_t *)data, len);
  lua_pushlstring(L, (const char *)out, (size_t)size);
  return 1;
}

/* equal(a, b) -> boolean, compared in constant time for equal lengths */
static int c_equal(lua_State *L) {
  size_t la, lb;
  const unsigned char *a = (const unsigned char *)luaL_checklstring(L, 1, &la);
  const unsigned char *b = (const unsigned char *)luaL_checklstring(L, 2, &lb);
  if (la != lb) { lua_pushboolean(L, 0); return 1; }
  unsigned char diff = 0;
  for (size_t i = 0; i < la; i++) diff |= (unsigned char)(a[i] ^ b[i]);
  lua_pushboolean(L, diff == 0);
  return 1;
}

static const luaL_Reg crypto_funcs[] = {
  {"argon2id", c_argon2id},
  {"blake2b", c_blake2b},
  {"equal", c_equal},
  {NULL, NULL}
};

int luaopen_wc_crypto(lua_State *L) {
  luaL_newlib(L, crypto_funcs);
  return 1;
}
