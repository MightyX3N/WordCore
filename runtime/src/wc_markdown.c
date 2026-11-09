/*
 * WordCore runtime — wc.markdown: CommonMark + GitHub extensions via cmark-gfm.
 * Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
 *
 * Safe by default: raw HTML in Markdown is not passed through, and links like
 * javascript: are dropped by cmark. Only trusted callers may ask for unsafe.
 */
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "cmark-gfm.h"
#include "cmark-gfm-core-extensions.h"
#include "wc_native.h"

static const char *EXTENSIONS[] = { "table", "strikethrough", "autolink", "tagfilter", "tasklist", NULL };

static int opt_flag(lua_State *L, int idx, const char *name) {
  if (!lua_istable(L, idx)) return 0;
  lua_getfield(L, idx, name);
  int v = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return v;
}

/* parse with extensions; caller frees the document */
static cmark_node *parse(lua_State *L, const char *md, size_t len, int options, cmark_parser **out_parser) {
  cmark_gfm_core_extensions_ensure_registered();
  cmark_parser *parser = cmark_parser_new(options);
  if (!parser) { luaL_error(L, "out of memory"); return NULL; }
  for (int i = 0; EXTENSIONS[i]; i++) {
    cmark_syntax_extension *ext = cmark_find_syntax_extension(EXTENSIONS[i]);
    if (ext) cmark_parser_attach_syntax_extension(parser, ext);
  }
  cmark_parser_feed(parser, md, len);
  cmark_node *doc = cmark_parser_finish(parser);
  *out_parser = parser;
  return doc;
}

/* render(markdown [, {unsafe=bool, hardbreaks=bool, smart=bool}]) -> html */
static int md_render(lua_State *L) {
  size_t len;
  const char *md = luaL_checklstring(L, 1, &len);
  int options = CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8;
  if (opt_flag(L, 2, "unsafe")) options |= CMARK_OPT_UNSAFE;
  if (opt_flag(L, 2, "hardbreaks")) options |= CMARK_OPT_HARDBREAKS;
  if (opt_flag(L, 2, "smart")) options |= CMARK_OPT_SMART;
  cmark_parser *parser = NULL;
  cmark_node *doc = parse(L, md, len, options, &parser);
  char *html = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser));
  cmark_node_free(doc);
  cmark_parser_free(parser);
  if (!html) return luaL_error(L, "markdown render failed");
  lua_pushstring(L, html);
  free(html);
  return 1;
}

/* text(markdown) -> plain text (for excerpts and search) */
static int md_text(lua_State *L) {
  size_t len;
  const char *md = luaL_checklstring(L, 1, &len);
  int options = CMARK_OPT_DEFAULT | CMARK_OPT_VALIDATE_UTF8;
  cmark_parser *parser = NULL;
  cmark_node *doc = parse(L, md, len, options, &parser);
  char *text = cmark_render_plaintext(doc, options, 0);
  cmark_node_free(doc);
  cmark_parser_free(parser);
  if (!text) return luaL_error(L, "markdown render failed");
  lua_pushstring(L, text);
  free(text);
  return 1;
}

static int md_version(lua_State *L) {
  lua_pushstring(L, cmark_version_string());
  return 1;
}

int luaopen_wc_markdown(lua_State *L) {
  static const luaL_Reg funcs[] = {
    {"render", md_render}, {"text", md_text}, {"version", md_version}, {NULL, NULL}
  };
  luaL_newlib(L, funcs);
  return 1;
}
