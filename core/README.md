# core/

The Lua core, embedded in the `wordcore` program. Everything a site needs, and nothing it doesn't. See [PLAN.md §5](../PLAN.md#5-core-what-ships-in-the-box).

Set `WORDCORE_CORE_DIR=core` to run the program against this folder instead of its built-in copy (no rebuild while editing).

## Layout (Phase 2)

```
core/
├── boot.lua          # entry: module loader (no file/C loaders), commands, CGI detection
├── platform/         # how requests become responses
│   ├── http.lua      #   request/response objects, URL decoding, path cleaning, form + upload parsing
│   ├── address.lua   #   real site address: subfolder, web root, tunnels, proxies
│   ├── server.lua    #   built-in server: non-blocking, keep-alive, opens the browser
│   ├── cgi.lua       #   CGI mode for shared hosting
│   ├── app.lua       #   pipeline: assets → session → setup gate → route → auth → CSRF → handler
│   ├── router.lua    #   routes with :params, *rest, names
│   ├── session.lua   #   sessions (hashed tokens), CSRF, flash messages, cookies
│   ├── ratelimit.lua #   login / setup-code / sign-up limits
│   ├── settings.lua  #   site settings (key → JSON)
│   ├── log.lua       #   activity log
│   ├── db.lua        #   SQLite helpers + migrations
│   ├── site.lua      #   the site folder, config.json, core migrations
│   ├── view.lua      #   etlua templates for the admin (explicit helper set, never _G)
│   ├── assets.lua    #   built-in CSS/JS/fonts + licence notices
│   └── files.lua     #   read the core's own files (embedded or dev folder)
├── content/          # what the site is made of
│   ├── pages.lua     #   nested pages, drafts, scheduling, access, revisions
│   ├── menus.lua     #   main + footer menus
│   ├── media.lua     #   uploads in site/media, served at /media/…
│   ├── shortcodes.lua#   [name attr="…"] registry; [button] is built in
│   ├── render.lua    #   Markdown + shortcodes → HTML (and plain text / excerpts)
│   ├── editors.lua   #   the editor slot + the core Markdown editor
│   ├── front.lua     #   the public site: pages, 404, /media, theme assets
│   └── starter.lua   #   starter content for "Simple site"
├── themes/
│   ├── engine.lua    #   load, list, settings, sandboxed rendering
│   └── quiet/        #   the built-in theme
├── people/
│   ├── users.lua     #   accounts, roles, capabilities, password rules
│   ├── login.lua     #   sign-in shared by admin and site (rate limits, 2-step step)
│   ├── twofactor.lua #   authenticator codes, recovery codes, QR
│   └── accounts.lua  #   member sign-in, sign-up and account pages on the site (themed)
├── setup/            # first-run wizard + setup code
├── admin/            # sign-in, dashboard, pages, media, menus, themes, people, settings, account, UI kit
├── lib/              # json, html, path, base64, crypto, locale, multipart, filetype, slug, totp
├── views/            # admin templates (admin layout, sign-in/setup layout)
├── assets/           # admin.css, admin.js, fonts (Inter, Space Grotesk, JetBrains Mono)
├── vendor/           # etlua (MIT), luaqrcode (BSD-3)
└── app/hello.lua     # the Phase 0 host check, kept at /_wc/hostcheck (signed in) and /_wc/health
```

The program embeds this folder as precompiled Lua bytecode (built by `runtime/build`); with `WORDCORE_CORE_DIR` it loads the plain source instead. Only the core is ever loaded as bytecode — addons (Phase 3) will be source only.

Still to come: `addons/` (Phase 3), `publish/` (Phase 4).

## Security model

- **No default login.** A fresh install only shows the setup wizard, which needs a one-time setup code from `site/setup-code.txt` (or from the console window; the program opens the browser with it filled in). The file is deleted when setup finishes.
- **Passwords:** Argon2id (19 MiB, 2 passes) via Monocypher, PHC strings, automatic rehash when parameters change, at least 10 characters with a strength check, same timing for unknown users.
- **Sessions:** 32-byte random tokens; only their BLAKE2b hash is stored. New token on every sign-in and password change. `HttpOnly`, `SameSite=Lax`, `Secure` over HTTPS, path = the site's base path, cookie name unique per site. 14 days idle, 60 days max.
- **CSRF:** every POST needs the session's token; a cross-site `Origin` is refused.
- **Rate limits:** 8 failed sign-ins per account and 20 per address per 15 minutes; 10 setup-code tries per address.
- **Admin pages:** strict Content-Security-Policy (no inline scripts or styles anywhere), `no-store`, `noindex`, `frame-ancestors 'none'`.
- **No open redirects:** `?next=` only accepts paths inside the site.
- **2-step login:** TOTP (RFC 6238, checked against its test vectors) with ±30 s drift and no reuse of a code; 10 one-time recovery codes stored as BLAKE2b hashes; 5 code tries per sign-in, then start over. The password step alone never creates a session.
- **Content:** Markdown is rendered in cmark-gfm's safe mode — raw HTML is dropped and `javascript:`/`data:` links are emptied; shortcodes escape their output. Editors never write HTML into pages.
- **Uploads:** the type comes from the file's bytes, not its name or the browser (images, PDF, MP4/WebM, MP3/OGG, ZIP); SVG and HTML are refused. Files are served with `Content-Security-Policy: sandbox`, `nosniff`, and as downloads when they aren't media.
- **Roles:** capabilities are checked on every route and again in the handlers (authors only touch their own pages and can't publish). Only the owner changes the owner; nobody changes their own role.
- **Themes:** templates run sandboxed — they only see the variables and helpers they're given. Theme settings are validated (colours must be `#rrggbb`, choices from the list) before they reach CSS.

## Admin UI kit

Screens are described, not hand-written. A settings screen is a list of fields:

```lua
local settings_page = require("wc.admin.settings_page")
settings_page.register(router, {
  path = "/admin/settings", id = "settings", title = "Settings", cap = "settings.manage",
  sections = {
    { title = "Site", fields = {
      { key = "site.name", label = "Site name", type = "text", required = true, max = 80 },
      { key = "site.language", label = "Language", type = "select", options = { { "en", "English" } } },
      { key = "proxy.trust", label = "Trust proxy headers", type = "checkbox" },
      { key = "repo.urls", label = "Repositories", type = "url_list" },
    }},
  },
})
```

That gives a page that loads, validates, saves, logs the change and shows "Saved." — with consistent markup, labels, hints, errors and accessibility. Lower-level pieces live in `admin/ui.lua`: `ui.form`, `ui.field` (text, email, url, password with strength meter, textarea, select, checkbox, radio cards), `ui.card`, `ui.checks`, `ui.badge`, `ui.flash`. Addons will get the same kit in Phase 3.

## Content API (for addons, Phase 3)

```lua
-- a shortcode: [gallery folder="2026/11"]
require("wc.content.shortcodes").register("gallery", {
  label = "Gallery", description = "Images from a media folder.",
  insert = '[gallery folder=""]',
  render = function(attrs, inner_html, ctx) return "<div class=\"gallery\">…</div>" end,  -- escape what you output
})

-- another editor (the Block Editor addon): whatever it shows, it submits Markdown
require("wc.content.editors").register({ id = "blocks", label = "Block editor",
  render = function(req, field) return "…" end })   -- field = { name, value, id, preview_url, media_url }
```

## Themes

A theme is a folder: `theme.json` (id, name, version, layouts, settings), `templates/layout.etlua`, `page.etlua`, `404.etlua`, `message.etlua` (forms and notices built by the core and addons), optional `partials/`, and `assets/` served at `/_wc/theme/<id>/…`. Templates get `site`, `menus`, `theme` (its settings), `user`, `page`, `content` and the helpers `h`, `url`, `asset`, `core_asset`, `partial`. A missing template falls back to Quiet's, so a theme can start with just a layout and a stylesheet.
