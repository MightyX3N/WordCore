# core/

The Lua core, embedded in the `wordcore` program. Everything a site needs, and nothing it doesn't. See [PLAN.md §5](../PLAN.md#5-core-what-ships-in-the-box).

Set `WORDCORE_CORE_DIR=core` to run the program against this folder instead of its built-in copy (no rebuild while editing).

## Layout (Phase 1)

```
core/
├── boot.lua          # entry: module loader (no file/C loaders), commands, CGI detection
├── platform/         # how requests become responses
│   ├── http.lua      #   request/response objects, URL decoding, path cleaning
│   ├── address.lua   #   real site address: subfolder, web root, tunnels, proxies
│   ├── server.lua    #   built-in server: non-blocking, keep-alive, opens the browser
│   ├── cgi.lua       #   CGI mode for shared hosting
│   ├── app.lua       #   pipeline: assets → session → setup gate → route → auth → CSRF → handler
│   ├── router.lua    #   routes with :params, *rest, names
│   ├── session.lua   #   sessions (hashed tokens), CSRF, flash messages, cookies
│   ├── ratelimit.lua #   login / setup-code limits
│   ├── settings.lua  #   site settings (key → JSON)
│   ├── log.lua       #   activity log
│   ├── db.lua        #   SQLite helpers + migrations
│   ├── site.lua      #   the site folder, config.json, core migrations
│   ├── view.lua      #   etlua templates with an explicit helper set (never _G)
│   ├── assets.lua    #   built-in CSS/JS/fonts + licence notices
│   └── files.lua     #   read the core's own files (embedded or dev folder)
├── people/users.lua  # accounts, roles, capabilities, password rules
├── setup/            # first-run wizard + setup code
├── admin/            # sign-in, dashboard, settings, account, UI kit
├── lib/              # json, html, path, base64, crypto, locale
├── views/            # etlua templates (admin layout, sign-in/setup layout, front page)
├── assets/           # admin.css, admin.js, fonts (Inter, Space Grotesk, JetBrains Mono)
├── vendor/etlua.lua  # templates (MIT)
└── app/hello.lua     # the Phase 0 host check, kept at /_wc/hostcheck (signed in) and /_wc/health
```

Still to come: `content/` (Phase 2), `themes/` (Phase 2), `addons/` (Phase 3), `publish/` (Phase 4).

## Security model so far

- **No default login.** A fresh install only shows the setup wizard, which needs a one-time setup code from `site/setup-code.txt` (or from the console window; the program opens the browser with it filled in). The file is deleted when setup finishes.
- **Passwords:** Argon2id (19 MiB, 2 passes) via Monocypher, PHC strings, automatic rehash when parameters change, at least 10 characters with a strength check, same timing for unknown users.
- **Sessions:** 32-byte random tokens; only their BLAKE2b hash is stored. New token on every sign-in and password change. `HttpOnly`, `SameSite=Lax`, `Secure` over HTTPS, path = the site's base path, cookie name unique per site. 14 days idle, 60 days max.
- **CSRF:** every POST needs the session's token; a cross-site `Origin` is refused.
- **Rate limits:** 8 failed sign-ins per account and 20 per address per 15 minutes; 10 setup-code tries per address.
- **Admin pages:** strict Content-Security-Policy (no inline scripts or styles anywhere), `no-store`, `noindex`, `frame-ancestors 'none'`.
- **No open redirects:** `?next=` only accepts paths inside the site.

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
