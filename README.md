# WordCore

A small, fast CMS written in Lua. One program that runs on your PC, on cPanel hosting, on a VPS, or exports a static site for GitHub Pages.

> **Status:** Phase 2 — pages, menus, media, the Markdown editor, themes (built-in theme "Quiet"), people and roles, member accounts and 2-step login work in server and CGI mode on every platform. The addon system is next. Start with [PLAN.md](PLAN.md); build instructions are in [runtime/](runtime/).

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

## Licence

WordCore is licensed under the [GNU GPL v3](LICENSE), with the [WordCore Addon and Theme Exception](LICENSE-EXCEPTION.md): addons and themes you make that only use WordCore's addon/theme interfaces can use any licence you like, including closed source. Everything that comes from WordCore stays GPLv3. Third-party libraries keep their own licences, and the sites and content you make are entirely yours.

By contributing to this repository you agree that your contribution is licensed under the same terms (GPLv3 + the exception).
