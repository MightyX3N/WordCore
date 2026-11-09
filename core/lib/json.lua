-- WordCore — JSON encode/decode.
-- Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
--
-- json.encode(value [, {pretty = true}]) -> string
-- json.decode(text) -> value | nil, err
-- json.null      — sentinel for JSON null inside tables
-- json.array(t)  — mark a (possibly empty) table as an array
-- json.object(t) — mark a (possibly empty) table as an object

local json = {}

local null = setmetatable({}, { __tostring = function() return "null" end })
json.null = null

local ARRAY = setmetatable({}, { __mode = "k" })
local OBJECT = setmetatable({}, { __mode = "k" })

function json.array(t) t = t or {}; ARRAY[t] = true; return t end
function json.object(t) t = t or {}; OBJECT[t] = true; return t end

---------------------------------------------------------------- encoding

local escapes = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escape_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function is_array(t)
  if ARRAY[t] then return true end
  if OBJECT[t] then return false end
  local n = #t
  if n == 0 then return false end
  local count = 0
  for k in pairs(t) do
    if math.type(k) ~= "integer" or k < 1 or k > n then return false end
    count = count + 1
  end
  return count == n
end

local encode_value

local function encode_table(t, out, indent, depth, seen)
  if seen[t] then error("json.encode: circular reference", 0) end
  seen[t] = true
  local pretty = indent ~= nil
  local nl = pretty and ("\n" .. indent:rep(depth + 1)) or ""
  local close_nl = pretty and ("\n" .. indent:rep(depth)) or ""
  if is_array(t) then
    if #t == 0 then out[#out + 1] = "[]" seen[t] = nil return end
    out[#out + 1] = "["
    for i = 1, #t do
      if i > 1 then out[#out + 1] = "," end
      out[#out + 1] = nl
      encode_value(t[i], out, indent, depth + 1, seen)
    end
    out[#out + 1] = close_nl .. "]"
  else
    local keys = {}
    for k in pairs(t) do
      local tk = type(k)
      if tk ~= "string" and tk ~= "number" then
        error("json.encode: object keys must be strings or numbers", 0)
      end
      keys[#keys + 1] = tostring(k)
    end
    if #keys == 0 then out[#out + 1] = "{}" seen[t] = nil return end
    table.sort(keys)
    out[#out + 1] = "{"
    for i, k in ipairs(keys) do
      if i > 1 then out[#out + 1] = "," end
      out[#out + 1] = nl .. escape_string(k) .. (pretty and ": " or ":")
      local v = t[k]
      if v == nil then v = t[tonumber(k)] end
      encode_value(v, out, indent, depth + 1, seen)
    end
    out[#out + 1] = close_nl .. "}"
  end
  seen[t] = nil
end

encode_value = function(v, out, indent, depth, seen)
  local tv = type(v)
  if v == nil or v == null then
    out[#out + 1] = "null"
  elseif tv == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif math.type(v) == "integer" then
      out[#out + 1] = ("%d"):format(v)
    else
      local s = ("%.17g"):format(v)
      if tonumber(("%.14g"):format(v)) == v then s = ("%.14g"):format(v) end
      out[#out + 1] = s
    end
  elseif tv == "string" then
    out[#out + 1] = escape_string(v)
  elseif tv == "table" then
    encode_table(v, out, indent, depth, seen)
  else
    error("json.encode: cannot encode a " .. tv, 0)
  end
end

function json.encode(v, opts)
  local out = {}
  encode_value(v, out, (opts and opts.pretty) and "  " or nil, 0, {})
  return table.concat(out)
end

---------------------------------------------------------------- decoding

local function decode_error(s, pos, msg)
  local line, col = 1, 1
  for i = 1, pos - 1 do
    if s:byte(i) == 10 then line = line + 1; col = 1 else col = col + 1 end
  end
  error({ json_error = ("%s at line %d, column %d"):format(msg, line, col) }, 0)
end

local function skip_ws(s, pos)
  return s:find("[^ \t\r\n]", pos) or #s + 1
end

local decode_value

local function codepoint_to_utf8(cp)
  return utf8.char(cp)
end

local function decode_string(s, pos)
  -- pos points at the opening quote
  local parts = {}
  local i = pos + 1
  while true do
    local j = s:find('["\\%c]', i)
    if not j then decode_error(s, pos, "unterminated string") end
    local c = s:sub(j, j)
    if c == '"' then
      parts[#parts + 1] = s:sub(i, j - 1)
      return table.concat(parts), j + 1
    elseif c == "\\" then
      parts[#parts + 1] = s:sub(i, j - 1)
      local e = s:sub(j + 1, j + 1)
      local simple = ({ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[e]
      if simple then
        parts[#parts + 1] = simple
        i = j + 2
      elseif e == "u" then
        local hex = s:match("^%x%x%x%x", j + 2)
        if not hex then decode_error(s, j, "bad \\u escape") end
        local cp = tonumber(hex, 16)
        local nexti = j + 6
        if cp >= 0xD800 and cp <= 0xDBFF then
          local lo = s:match("^\\u(%x%x%x%x)", nexti)
          local lov = lo and tonumber(lo, 16)
          if lov and lov >= 0xDC00 and lov <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lov - 0xDC00)
            nexti = nexti + 6
          else
            cp = 0xFFFD
          end
        elseif cp >= 0xDC00 and cp <= 0xDFFF then
          cp = 0xFFFD
        end
        parts[#parts + 1] = codepoint_to_utf8(cp)
        i = nexti
      else
        decode_error(s, j, "bad escape")
      end
    else
      decode_error(s, j, "control character in string")
    end
  end
end

local function decode_number(s, pos)
  local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
  if not num or num == "" or num == "-" then decode_error(s, pos, "bad number") end
  if num:match("^-?0%d") then decode_error(s, pos, "leading zero") end
  local v = tonumber(num)
  if v and not num:find("[.eE]") then v = math.tointeger(v) or v end
  if v == nil then decode_error(s, pos, "bad number") end
  return v, pos + #num
end

decode_value = function(s, pos, depth)
  if depth > 200 then decode_error(s, pos, "nesting too deep") end
  pos = skip_ws(s, pos)
  local c = s:sub(pos, pos)
  if c == "{" then
    local obj = {}
    pos = skip_ws(s, pos + 1)
    if s:sub(pos, pos) == "}" then return json.object(obj), pos + 1 end
    while true do
      pos = skip_ws(s, pos)
      if s:sub(pos, pos) ~= '"' then decode_error(s, pos, "expected string key") end
      local key
      key, pos = decode_string(s, pos)
      pos = skip_ws(s, pos)
      if s:sub(pos, pos) ~= ":" then decode_error(s, pos, "expected ':'") end
      local val
      val, pos = decode_value(s, pos + 1, depth + 1)
      obj[key] = val
      pos = skip_ws(s, pos)
      local d = s:sub(pos, pos)
      if d == "}" then return obj, pos + 1 end
      if d ~= "," then decode_error(s, pos, "expected ',' or '}'") end
      pos = pos + 1
    end
  elseif c == "[" then
    local arr = json.array({})
    pos = skip_ws(s, pos + 1)
    if s:sub(pos, pos) == "]" then return arr, pos + 1 end
    local n = 0
    while true do
      local val
      val, pos = decode_value(s, pos, depth + 1)
      n = n + 1
      arr[n] = val
      pos = skip_ws(s, pos)
      local d = s:sub(pos, pos)
      if d == "]" then return arr, pos + 1 end
      if d ~= "," then decode_error(s, pos, "expected ',' or ']'") end
      pos = pos + 1
    end
  elseif c == '"' then
    return decode_string(s, pos)
  elseif c == "-" or c:match("%d") then
    return decode_number(s, pos)
  elseif s:sub(pos, pos + 3) == "true" then
    return true, pos + 4
  elseif s:sub(pos, pos + 4) == "false" then
    return false, pos + 5
  elseif s:sub(pos, pos + 3) == "null" then
    return null, pos + 4
  end
  decode_error(s, pos, c == "" and "unexpected end of input" or ("unexpected '" .. c .. "'"))
end

function json.decode(s)
  if type(s) ~= "string" then return nil, "json.decode: expected a string" end
  local ok, res, pos = pcall(decode_value, s, 1, 0)
  if not ok then
    if type(res) == "table" and res.json_error then return nil, res.json_error end
    error(res, 0)
  end
  pos = skip_ws(s, pos)
  if pos <= #s then
    local ok2, err = pcall(decode_error, s, pos, "trailing characters")
    return nil, (not ok2) and err.json_error or "trailing characters"
  end
  return res
end

return json
