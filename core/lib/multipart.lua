-- WordCore — multipart/form-data parsing (file uploads).
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
--   local fields, files = multipart.parse(body, content_type)
--   fields.title           -> "..."
--   files[1]               -> { field = "file", filename = "a.png", type = "image/png", data = "..." }

local multipart = {}

function multipart.boundary(content_type)
  if not content_type then return nil end
  if not content_type:lower():find("^%s*multipart/form%-data") then return nil end
  local b = content_type:match('[Bb]oundary="([^"]+)"') or content_type:match("[Bb]oundary=([^;%s]+)")
  if not b or #b > 200 then return nil end
  return b
end

local function header_params(value)
  local out = {}
  for k, v in value:gmatch('([%w%-%*]+)%s*=%s*"([^"]*)"') do out[k:lower()] = v end
  for k, v in value:gmatch('([%w%-%*]+)%s*=%s*([^";%s]+)') do
    if out[k:lower()] == nil then out[k:lower()] = v end
  end
  return out
end

-- Returns fields (name -> value; repeated names become the last value, plus
-- fields_all[name] = { ... }), files (list), or nil + error.
function multipart.parse(body, content_type, max_files)
  local boundary = multipart.boundary(content_type)
  if not boundary then return nil, "not multipart" end
  local delim = "--" .. boundary
  local fields, fields_all, files = {}, {}, {}
  local pos = body:find(delim, 1, true)
  if not pos then return nil, "no parts" end
  pos = pos + #delim
  while true do
    -- after a delimiter: "--" means the end, otherwise CRLF then headers
    if body:sub(pos, pos + 1) == "--" then break end
    if body:sub(pos, pos + 1) ~= "\r\n" then return nil, "malformed part" end
    pos = pos + 2
    local head_end = body:find("\r\n\r\n", pos, true)
    if not head_end then return nil, "malformed headers" end
    local headers = {}
    for line in body:sub(pos, head_end - 1):gmatch("[^\r\n]+") do
      local k, v = line:match("^([^:]+):%s*(.*)$")
      if k then headers[k:lower()] = v end
    end
    local data_start = head_end + 4
    local next_delim = body:find("\r\n" .. delim, data_start, true)
    if not next_delim then return nil, "unterminated part" end
    local data = body:sub(data_start, next_delim - 1)
    local disp = header_params(headers["content-disposition"] or "")
    local name = disp.name
    if name then
      if disp.filename ~= nil then
        if disp.filename ~= "" then
          if max_files and #files >= max_files then return nil, "too many files" end
          files[#files + 1] = {
            field = name,
            filename = disp.filename:gsub("^.*[/\\]", ""),
            type = (headers["content-type"] or "application/octet-stream"):lower(),
            data = data,
          }
        end
      else
        fields[name] = data
        fields_all[name] = fields_all[name] or {}
        table.insert(fields_all[name], data)
      end
    end
    pos = next_delim + 2 + #delim
  end
  return fields, files, fields_all
end

return multipart
