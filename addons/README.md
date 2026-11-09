# addons/

Official addon source. Each folder is one addon with an `addon.json` manifest. Release builds turn them into zips on the `pages` branch, served at `wordcore.space/repo/`. See [PLAN.md §7–8](../PLAN.md#7-the-addon-sandbox).

## Planned addons

| Folder | Addon | Static mode |
|---|---|---|
| `blog/` | Blog (posts, categories, archive, RSS, comments) | full / fallback for comments |
| `seo/` | SEO | full |
| `contact-form/` | Contact Form | fallback |
| `analytics/` | Analytics | fallback |
| `snippets/` | Snippets (CSS / JS / HTML only) | full |
| `favicons/` | Favicons | full |
| `docs/` | Docs | full |
| `block-editor/` | Block Editor | n/a |
| `forum/` | Forum | none |
| `github-actions/` | GitHub Actions (later) | — |

Addons use only the sandboxed `wc` API. No `io`, `os`, `require` or `load`.
