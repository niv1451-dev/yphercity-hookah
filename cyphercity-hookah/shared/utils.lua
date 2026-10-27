-- Shared helpers used by both client and server.

Utils = {}

Utils.RESOURCE = 'cyphercity-hookah'
Utils.EVENT_PREFIX = 'cyphercity-hookah:'

function Utils.Event(name)
    return Utils.EVENT_PREFIX .. name
end

function Utils.Now()
    return os.time()
end

-- Returns an integer when `value` is a finite number with no fractional part.
-- JSON coming from the NUI often decodes integers as floats (2.0), so accept those too.
function Utils.ToInt(value)
    if type(value) ~= 'number' then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    if value ~= math.floor(value) then return nil end
    return math.tointeger(value)
end

function Utils.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.IsArray(t)
    if type(t) ~= 'table' then return false end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k ~= math.floor(k) then return false end
        count = count + 1
    end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

function Utils.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Utils.Keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    return keys
end

function Utils.Contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

function Utils.DeepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[Utils.DeepCopy(k, seen)] = Utils.DeepCopy(v, seen)
    end
    return copy
end

-- Strips control characters and trims a user supplied string.
function Utils.SanitizeString(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if not utf8.len(value) then return nil end
    if maxLength then
        local cut = utf8.offset(value, maxLength + 1)
        if cut then value = value:sub(1, cut - 1) end
    end
    return value
end

function Utils.ToVec3(v)
    if v == nil then return nil end
    return vec3(v.x, v.y, v.z)
end

-- Horizontal distance plus a vertical sanity check. Venue checks use this so that
-- small z differences (ground snapping, sitting) never break an interaction.
function Utils.Dist2D(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function Utils.WithinRange(a, b, maxDistance, maxHeight)
    if not a or not b then return false end
    if math.abs((a.z or 0) - (b.z or 0)) > (maxHeight or 10.0) then return false end
    return Utils.Dist2D(a, b) <= maxDistance
end

function Utils.FormatMoney(amount)
    local currency = Config.Currency or {}
    local formatted = tostring(math.floor(amount or 0))
    local k
    repeat
        formatted, k = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
    until k == 0
    -- non-breaking space, so the amount and the sign never wrap apart
    local gap = currency.space and '\u{00A0}' or ''
    if currency.position == 'after' then
        return formatted .. gap .. (currency.symbol or '')
    end
    return (currency.symbol or '') .. gap .. formatted
end

function Utils.Percent(amount, percent)
    return math.floor((amount * percent) / 100 + 0.5)
end

function Utils.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format('%d:%02d', m, s)
end
