# core/

The Lua core. Everything a site needs, and nothing it doesn't. See [PLAN.md §5](../PLAN.md#5-core-what-ships-in-the-box).

## Planned modules

```
core/
├── platform/   # http (server + CGI), router, address/proxy, sessions, csrf, rate limits, db + migrations, jobs, logging
├── people/     # users, roles + capabilities, owner account, 2-step login, front-end accounts, password reset
├── content/    # pages, menus, media library, markdown, shortcodes, editor slot + markdown editor
├── themes/     # theme loader, layouts, regions/widgets, sandboxed templates, theme settings
├── admin/      # admin shell, admin UI kit, dashboard, site health
├── addons/     # manifest, sandbox, permissions, install/update/remove, repo client
├── publish/    # preview lock, export packages, saved hosts (cPanel, SSH, FTP, GitHub), pull from host, static export
└── setup/      # first-run wizard
```
