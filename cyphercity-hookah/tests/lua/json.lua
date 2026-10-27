-- Minimal JSON encoder/decoder used only by the offline test harness
-- (FiveM provides its own `json` global at runtime).

local json = {}

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return escapes[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

local function encode(value, seen)
    local kind = type(value)
    if value == nil then return 'null' end
    if kind == 'boolean' then return tostring(value) end
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return 'null' end
        if math.type(value) == 'integer' then return tostring(value) end
        if value == math.floor(value) and math.abs(value) < 1e15 then return string.format('%d', value) end
        return string.format('%.14g', value)
    end
    if kind == 'string' then return encodeString(value) end
    if kind == 'table' then
        seen = seen or {}
        if seen[value] then error('circular table in json.encode') end
        seen[value] = true
        local out = {}
        local array, n = isArray(value)
        if array and n > 0 then
            for i = 1, n do out[i] = encode(value[i], seen) end
            seen[value] = nil
            return '[' .. table.concat(out, ',') .. ']'
        end
        if array then
            seen[value] = nil
            return (getmetatable(value) == json.ARRAY) and '[]' or '{}'
        end
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = value[k]
            if type(v) ~= 'function' then
                out[#out + 1] = encodeString(tostring(k)) .. ':' .. encode(v, seen)
            end
        end
        seen[value] = nil
        return '{' .. table.concat(out, ',') .. '}'
    end
    return 'null'
end

json.ARRAY = {}

function json.encode(value)
    return encode(value)
end

local function decodeError(str, pos, msg)
    error(string.format('json.decode: %s at position %d', msg, pos))
end

local decodeValue

local function skip(str, pos)
    return str:find('[^ \t\r\n]', pos) or #str + 1
end

local function decodeString(str, pos)
    local out, i = {}, pos + 1
    while true do
        local c = str:sub(i, i)
        if c == '' then decodeError(str, i, 'unterminated string') end
        if c == '"' then return table.concat(out), i + 1 end
        if c == '\\' then
            local n = str:sub(i + 1, i + 1)
            local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
            if map[n] then
                out[#out + 1] = map[n]
                i = i + 2
            elseif n == 'u' then
                local code = tonumber(str:sub(i + 2, i + 5), 16)
                out[#out + 1] = utf8.char(code)
                i = i + 6
            else
                decodeError(str, i, 'bad escape')
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

function decodeValue(str, pos)
    pos = skip(str, pos)
    local c = str:sub(pos, pos)
    if c == '{' then
        local obj = {}
        pos = skip(str, pos + 1)
        if str:sub(pos, pos) == '}' then return obj, pos + 1 end
        while true do
            local key
            key, pos = decodeString(str, skip(str, pos))
            pos = skip(str, pos)
            if str:sub(pos, pos) ~= ':' then decodeError(str, pos, 'expected :') end
            obj[key], pos = decodeValue(str, pos + 1)
            pos = skip(str, pos)
            local d = str:sub(pos, pos)
            if d == '}' then return obj, pos + 1 end
            if d ~= ',' then decodeError(str, pos, 'expected , or }') end
            pos = pos + 1
        end
    elseif c == '[' then
        local arr = {}
        pos = skip(str, pos + 1)
        if str:sub(pos, pos) == ']' then return arr, pos + 1 end
        while true do
            arr[#arr + 1], pos = decodeValue(str, pos)
            pos = skip(str, pos)
            local d = str:sub(pos, pos)
            if d == ']' then return arr, pos + 1 end
            if d ~= ',' then decodeError(str, pos, 'expected , or ]') end
            pos = pos + 1
        end
    elseif c == '"' then
        return decodeString(str, pos)
    elseif str:sub(pos, pos + 3) == 'true' then
        return true, pos + 4
    elseif str:sub(pos, pos + 4) == 'false' then
        return false, pos + 5
    elseif str:sub(pos, pos + 3) == 'null' then
        return nil, pos + 4
    else
        local num = str:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
        if not num or num == '' then decodeError(str, pos, 'unexpected character') end
        return tonumber(num), pos + #num
    end
end

function json.decode(str)
    local value = decodeValue(str, 1)
    return value
end

return json
