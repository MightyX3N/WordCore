-- WordCore — recognise uploaded files by their content (not their name) and
-- read image dimensions.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.

local filetype = {}

-- Allowed upload types: detected from the first bytes.
-- SVG is deliberately not allowed: it can carry scripts.
local KINDS = {
  { ext = "png",  mime = "image/png",  image = true, test = function(d) return d:sub(1, 8) == "\137PNG\r\n\26\n" end },
  { ext = "jpg",  mime = "image/jpeg", image = true, test = function(d) return d:sub(1, 3) == "\255\216\255" end },
  { ext = "gif",  mime = "image/gif",  image = true, test = function(d) return d:sub(1, 6) == "GIF87a" or d:sub(1, 6) == "GIF89a" end },
  { ext = "webp", mime = "image/webp", image = true, test = function(d) return d:sub(1, 4) == "RIFF" and d:sub(9, 12) == "WEBP" end },
  { ext = "avif", mime = "image/avif", image = true, test = function(d) return d:sub(5, 8) == "ftyp" and (d:sub(9, 12) == "avif" or d:sub(9, 12) == "avis") end },
  { ext = "pdf",  mime = "application/pdf", test = function(d) return d:sub(1, 5) == "%PDF-" end },
  { ext = "mp4",  mime = "video/mp4",  test = function(d) return d:sub(5, 8) == "ftyp" and not d:sub(9, 12):find("^avi") end },
  { ext = "webm", mime = "video/webm", test = function(d) return d:sub(1, 4) == "\26\69\223\163" end },
  { ext = "mp3",  mime = "audio/mpeg", test = function(d) return d:sub(1, 3) == "ID3" or d:byte(1) == 255 and (d:byte(2) or 0) >= 0xE0 end },
  { ext = "ogg",  mime = "audio/ogg",  test = function(d) return d:sub(1, 4) == "OggS" end },
  { ext = "zip",  mime = "application/zip", test = function(d) return d:sub(1, 4) == "PK\3\4" end },
}

function filetype.detect(data)
  for _, k in ipairs(KINDS) do
    if k.test(data) then return k end
  end
  return nil
end

function filetype.by_ext(ext)
  for _, k in ipairs(KINDS) do if k.ext == ext then return k end end
  return nil
end

local function u16be(d, i) return d:byte(i) * 256 + d:byte(i + 1) end
local function u32be(d, i) return ((d:byte(i) * 256 + d:byte(i + 1)) * 256 + d:byte(i + 2)) * 256 + d:byte(i + 3) end
local function u16le(d, i) return d:byte(i) + d:byte(i + 1) * 256 end
local function u24le(d, i) return d:byte(i) + d:byte(i + 1) * 256 + d:byte(i + 2) * 65536 end

-- Width and height of an image, or nil.
function filetype.image_size(data, ext)
  local ok, w, h = pcall(function()
    if ext == "png" then
      return u32be(data, 17), u32be(data, 21)
    elseif ext == "gif" then
      return u16le(data, 7), u16le(data, 9)
    elseif ext == "jpg" then
      local i = 3
      while i < #data do
        if data:byte(i) ~= 0xFF then i = i + 1 else
          local marker = data:byte(i + 1)
          if marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7) then
            i = i + 2
          else
            local len = u16be(data, i + 2)
            if (marker >= 0xC0 and marker <= 0xC3) or (marker >= 0xC5 and marker <= 0xC7)
              or (marker >= 0xC9 and marker <= 0xCB) or (marker >= 0xCD and marker <= 0xCF) then
              return u16be(data, i + 7), u16be(data, i + 5)
            end
            i = i + 2 + len
          end
        end
      end
    elseif ext == "webp" then
      local chunk = data:sub(13, 16)
      if chunk == "VP8 " then
        return u16le(data, 27) & 0x3FFF, u16le(data, 29) & 0x3FFF
      elseif chunk == "VP8L" then
        local b0, b1, b2, b3 = data:byte(22, 25)
        local w = 1 + (((b1 & 0x3F) << 8) | b0)
        local h = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6))
        return w, h
      elseif chunk == "VP8X" then
        return 1 + u24le(data, 25), 1 + u24le(data, 28)
      end
    end
  end)
  if ok and w and h and w > 0 and h > 0 and w < 100000 and h < 100000 then return w, h end
  return nil
end

return filetype
