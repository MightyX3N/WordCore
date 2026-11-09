-- WordCore — the core Settings screen (built with the declarative UI kit).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local locale = require("wc.lib.locale")
local settings_page = require("wc.admin.settings_page")

local admin_settings = {}

function admin_settings.register(r)
  settings_page.register(r, {
    path = "/admin/settings", id = "settings", title = "Settings", cap = "settings.manage",
    subtitle = "The basics of your site.",
    sections = {
      { title = "Site", fields = {
        { key = "site.name", label = "Site name", type = "text", required = true, max = 80, required_text = "Give your site a name." },
        { key = "site.tagline", label = "Tagline", type = "text", max = 160, optional = true },
        { key = "site.language", label = "Language", type = "select", options = locale.language_options(),
          hint = "The language your site is written in." },
        { key = "site.timezone", label = "Time zone", type = "select", options = locale.timezone_options() },
      }},
      { title = "Front page", id = "reading", fields = {
        { key = "content.home_page", label = "Home page", type = "select", number = true, options = function(req)
            local pages = require("wc.content.pages")
            local opts = { { "0", "None — show a short welcome message" } }
            for _, e in ipairs(pages.tree(req.db)) do
              opts[#opts + 1] = { tostring(e.page.id), string.rep("— ", e.depth) .. e.page.title .. (pages.is_live(e.page) and "" or " (draft)") }
            end
            return opts
          end, hint = "The page visitors see at your site's main address." },
        { key = "content.editor", label = "Editor", type = "select", options = function()
            local opts = {}
            for _, e in ipairs(require("wc.content.editors").list()) do opts[#opts + 1] = { e.id, e.label } end
            return opts
          end, hint = "Addons can add more editors. Content is always stored as Markdown, so you can switch any time." },
      }},
      { title = "Members", id = "members", intro = "Members sign in on the site itself (not the admin) to see members-only pages.", fields = {
        { key = "members.registration", label = "Anyone can sign up as a member", type = "checkbox",
          hint = "Adds a sign-up form at /account/register. Leave off to add members yourself under People." },
      }},
      { title = "Address and proxy", id = "proxy", intro = "Only needed when the site is reached through a tunnel (like playit.gg) or a proxy (nginx, Caddy, Cloudflare).", fields = {
        { key = "proxy.trust", label = "Trust proxy headers", type = "checkbox",
          hint = "Use the address and visitor IP that the tunnel or proxy passes on. Leave off if nothing sits in front of WordCore — otherwise visitors could fake them." },
      }},
      { title = "Addon repositories", fields = {
        { key = "repo.urls", label = "Repository addresses", type = "url_list", required = true, rows = 3,
          hint = "One per line. The official repository is https://wordcore.space/repo/ — addons from others are marked unofficial." },
      }},
    },
  })
end

return admin_settings
