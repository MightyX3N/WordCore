-- WordCore — starter content for new sites ("Simple site").
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local pages = require("wc.content.pages")
local menus = require("wc.content.menus")
local settings = require("wc.platform.settings")

local starter = {}

local HOME = [[
Welcome to **%s**. This is your home page — change it under **Pages** in the admin.

## What's here

- An **About** page, linked from the main menu
- A theme you can adjust under **Themes**

[button url="/about" text="About us"]
]]

local ABOUT = [[
Tell visitors who you are and what you do.

You can write in **Markdown**: headings start with `#`, lists with `-`, and links look like [this](https://wordcore.space).
]]

-- Put plain text into Markdown without it being read as markup or HTML.
local function md_escape(text)
  return (tostring(text):gsub("[\\`*_%[%]<>#!|~&]", "\\%0"))
end
starter.md_escape = md_escape

function starter.apply(db, kind, site_name, user_id)
  if settings.get(db, "content.seeded", false) then return end
  settings.set(db, "content.seeded", true)
  if kind ~= "simple" then return end
  if pages.count(db) > 0 then return end
  db:transaction(function()
    local home = pages.create(db, { slug = "home", title = "Home", body = HOME:format(md_escape(site_name or "your site")),
      status = "published", access = "public", layout = "home" }, user_id)
    local about = pages.create(db, { slug = "about", title = "About", body = ABOUT,
      status = "published", access = "public", layout = "default" }, user_id)
    settings.set(db, "content.home_page", home)
    menus.add_page(db, "main", home, "Home")
    menus.add_page(db, "main", about, "")
  end)
end

return starter
