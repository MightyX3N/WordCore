# WordCore

A small, fast CMS written in Lua. One program that runs on your PC, on cPanel hosting, on a VPS, or exports a static site for GitHub Pages.

> **Status:** planning. No code yet. Start with [PLAN.md](PLAN.md).

## The idea

- **Build locally.** Double-click `wordcore`, open `localhost:8080`, make your site.
- **Share for testing.** Put it behind a tunnel like playit.gg with a preview lock so only invited people see it.
- **Go live anywhere.** Publish to cPanel, a VPS, FTP/SFTP or GitHub Pages from the admin panel. The site is one folder, so moving it is a copy.
- **Small core, sandboxed addons.** Blog, Docs, Forum, SEO and the rest are addons that only get the permissions you approve.
- **Content is Markdown.** Whatever editor you use, so removing an addon never breaks a page.

## Folders

| Folder | What goes there |
|---|---|
| [`runtime/`](runtime/) | The native `wordcore` program (Lua + C libraries) and per-platform builds |
| [`core/`](core/) | The Lua core |
| [`addons/`](addons/) | Official addon source |
| [`themes/`](themes/) | Official theme source |
| [`tools/`](tools/) | Build, package and release scripts, repo-index builder |
| [`tests/`](tests/) | Unit, integration and browser tests |
| [`docs/`](docs/) | Developer and user documentation |
| [`registry/`](registry/) | Community addon listings for the official repo |
| [`design/`](design/) | Admin design previews and notes |
