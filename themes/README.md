# themes/

Official theme source. A theme is one package that styles every page from every addon, with no companion addon. See [PLAN.md §5 → Themes](../PLAN.md#themes-one-package-styles-everything).

## Planned themes

- `default/` — the new built-in theme
- `ink-page/` — port of Ink & Page
- `slate/` — port of Slate

## A theme contains

```
theme.json     # id, name, version, settings (colours, fonts, logo), regions
layouts/       # page layouts (default, wide, no-sidebar…)
partials/      # header, footer, nav…
templates/     # optional overrides for addon templates (blog post, forum thread…)
assets/        # css, js, images, fonts
```
