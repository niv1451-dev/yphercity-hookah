-- Venue layout placed in-game with /hookahsetup (saved in data/layout.json).
--
-- While the layout is incomplete it is only a draft: the lounge keeps running
-- on the positions from config.lua. As soon as it has a hostess, at least one
-- waiter and one table with a seat it becomes active and replaces the
-- positions from config.lua: hostess, waiters, tables (seats + hookah spots),
-- staff point, venue centre / radius and the map blip. Client and server
-- apply the same data with the same code, so both always agree.
--
-- Points are stored as plain arrays: { x, y, z, heading } (the player's own
-- position and heading when the point was placed).

Layout = {
    data = nil,     -- server: the saved layout (draft or complete); client: the active layout
    active = false,
    MAX = { waiters = 8, tables = 30, seats = 12, spots = 6, label = 24 },
    SEAT_Z = 0.6,   -- seat height correction per table is limited to ±0.6 m
}

-- Positions from config.lua, kept so a layout can be removed again.
local defaults = {
    venueCenter = Config.Venue.center,
    venueRadius = Config.Venue.radius,
    renderDistance = Config.Venue.renderDistance,
    snap = Config.Venue.snapToGround,
    hostess = Config.Hostess.coords,
    waiters = Config.Waiters,
    tables = Config.Tables,
    manager = Config.Staff.managementPoint,
    furniture = Config.Furniture.enabled,
    blip = Config.Blip and Config.Blip.coords,
}

local function round(n) return math.floor(n * 100 + 0.5) / 100 end

local function finite(n)
    return type(n) == 'number' and n == n and n > -30000 and n < 30000
end

-- { x, y, z } or { x, y, z, heading } with finite numbers, rounded to 1 cm.
local function cleanPoint(p, withHeading)
    if type(p) ~= 'table' or not finite(p[1]) or not finite(p[2]) or not finite(p[3]) then return nil end
    if withHeading then
        local heading = finite(p[4]) and (p[4] % 360.0) or 0.0
        return { round(p[1]), round(p[2]), round(p[3]), round(heading) }
    end
    return { round(p[1]), round(p[2]), round(p[3]) }
end
Layout.CleanPoint = cleanPoint

local function cleanList(list, withHeading, max)
    local out = {}
    if type(list) ~= 'table' then return out end
    for _, p in ipairs(list) do
        local point = cleanPoint(p, withHeading)
        if point and #out < max then out[#out + 1] = point end
    end
    return out
end

local function cleanSeatZ(value)
    if not finite(value) then return 0 end
    return round(Utils.Clamp(value, -Layout.SEAT_Z, Layout.SEAT_Z))
end

function Layout.Empty()
    return { version = 1, nextId = 1, hostess = nil, manager = nil, furniture = false, waiters = {}, tables = {} }
end

function Layout.DefaultLabel(id)
    return L('setup_table_default', id)
end

-- Validates raw data (from the file or after an edit) into a clean layout.
function Layout.Sanitize(raw)
    local data = Layout.Empty()
    if type(raw) ~= 'table' then return data end
    data.hostess = cleanPoint(raw.hostess, true)
    data.manager = cleanPoint(raw.manager, false)
    data.furniture = raw.furniture == true
    data.waiters = cleanList(raw.waiters, true, Layout.MAX.waiters)

    local used, maxId = {}, 0
    for _, t in ipairs(type(raw.tables) == 'table' and raw.tables or {}) do
        if type(t) == 'table' and #data.tables < Layout.MAX.tables then
            local id = Utils.ToInt(t.id)
            if not id or id < 1 or id > 9999 or used[id] then id = nil end
            if id then
                used[id] = true
                if id > maxId then maxId = id end
            end
            data.tables[#data.tables + 1] = {
                id = id,
                label = Utils.SanitizeString(t.label, Layout.MAX.label),
                vip = t.vip == true,
                seatZ = cleanSeatZ(t.seatZ),
                seats = cleanList(t.seats, true, Layout.MAX.seats),
                spots = cleanList(t.spots, true, Layout.MAX.spots),
            }
        end
    end
    -- tables without a valid id get new ones, ids are never reused
    for _, t in ipairs(data.tables) do
        if not t.id then
            maxId = maxId + 1
            t.id = maxId
        end
        if not t.label or t.label == '' then t.label = Layout.DefaultLabel(t.id) end
    end
    data.nextId = math.max(Utils.ToInt(raw.nextId) or 1, maxId + 1)
    return data
end

function Layout.FindTable(data, id)
    id = Utils.ToInt(id)
    for index, t in ipairs((data and data.tables) or {}) do
        if t.id == id then return t, index end
    end
    return nil
end

function Layout.UsableTables(data)
    local count = 0
    for _, t in ipairs((data and data.tables) or {}) do
        if #t.seats > 0 then count = count + 1 end
    end
    return count
end

-- What is still missing before the layout can replace config.lua.
function Layout.Missing(data)
    local missing = {}
    data = data or Layout.Empty()
    if not data.hostess then missing[#missing + 1] = 'hostess' end
    if #(data.waiters or {}) == 0 then missing[#missing + 1] = 'waiter' end
    if Layout.UsableTables(data) == 0 then missing[#missing + 1] = 'table' end
    return missing
end

function Layout.IsComplete(data)
    return data ~= nil and #Layout.Missing(data) == 0
end

local function v4(p) return vec4(p[1], p[2], p[3], p[4] or 0.0) end
local function v3(p) return vec3(p[1], p[2], p[3]) end

-- Seats and hookah spots of a table definition, as text. Used to detect whether
-- an edit would change a table that is in use right now.
function Layout.Signature(def)
    local parts = {}
    for _, s in ipairs(def.seats or {}) do parts[#parts + 1] = ('%.2f,%.2f,%.2f,%.1f'):format(s.x, s.y, s.z, s.w or 0.0) end
    parts[#parts + 1] = '|'
    for _, s in ipairs(def.hookahSpots or {}) do parts[#parts + 1] = ('%.2f,%.2f,%.2f'):format(s.x, s.y, s.z) end
    return table.concat(parts, ';')
end

-- Table definitions (same shape as Config.Tables) for a layout.
function Layout.BuildTables(data)
    local tables = {}
    for _, t in ipairs(data.tables or {}) do
        if #t.seats > 0 then
            local cx, cy, cz = 0, 0, 0
            for _, s in ipairs(t.seats) do cx, cy, cz = cx + s[1], cy + s[2], cz + s[3] end
            cx, cy, cz = cx / #t.seats, cy / #t.seats, cz / #t.seats
            local seats, spots = {}, {}
            for _, s in ipairs(t.seats) do seats[#seats + 1] = v4(s) end
            for _, s in ipairs(t.spots) do spots[#spots + 1] = v4(s) end
            tables[#tables + 1] = {
                id = t.id,
                label = t.label,
                capacity = #t.seats,
                vip = t.vip,
                seatZ = t.seatZ ~= 0 and t.seatZ or nil,
                center = vec3(round(cx), round(cy), round(cz)),
                seats = seats,
                hookahSpots = spots,
            }
        end
    end
    return tables
end

-- Every point of a layout (used for the venue centre and the distance check).
function Layout.Points(data)
    local points = {}
    if not data then return points end
    if data.hostess then points[#points + 1] = data.hostess end
    if data.manager then points[#points + 1] = data.manager end
    for _, p in ipairs(data.waiters or {}) do points[#points + 1] = p end
    for _, t in ipairs(data.tables or {}) do
        for _, p in ipairs(t.seats) do points[#points + 1] = p end
        for _, p in ipairs(t.spots) do points[#points + 1] = p end
    end
    return points
end

function Layout.Centroid(data)
    local points = Layout.Points(data)
    if #points == 0 then return nil end
    local cx, cy, cz = 0, 0, 0
    for _, p in ipairs(points) do cx, cy, cz = cx + p[1], cy + p[2], cz + p[3] end
    return vec3(cx / #points, cy / #points, cz / #points), points
end

-- Config.Tables as written in config.lua.
function Layout.DefaultTables()
    return defaults.tables
end

local function restoreDefaults()
    Config.Venue.center = defaults.venueCenter
    Config.Venue.radius = defaults.venueRadius
    Config.Venue.renderDistance = defaults.renderDistance
    Config.Venue.snapToGround = defaults.snap
    Config.Hostess.coords = defaults.hostess
    Config.Waiters = defaults.waiters
    Config.Tables = defaults.tables
    Config.Staff.managementPoint = defaults.manager
    Config.Furniture.enabled = defaults.furniture
    if Config.Blip then Config.Blip.coords = defaults.blip end
end

-- Applies a layout to Config. An incomplete layout (or nil) puts the positions
-- from config.lua back. Returns true when the layout is active.
function Layout.Apply(data)
    restoreDefaults()
    Layout.data = data
    Layout.active = Layout.IsComplete(data)
    if not Layout.active then return false end

    Config.Hostess.coords = v4(data.hostess)

    local waiters = {}
    for i, p in ipairs(data.waiters) do
        -- model, name and idle scenario are taken from Config.Waiters in turn
        local base = defaults.waiters[((i - 1) % math.max(1, #defaults.waiters)) + 1] or {}
        waiters[i] = { model = base.model or 's_m_y_waiter_01', scenario = base.scenario, name = base.name, coords = v4(p), tables = {} }
    end
    Config.Waiters = waiters

    -- every table is served by the nearest waiter
    Config.Tables = Layout.BuildTables(data)
    for _, t in ipairs(Config.Tables) do
        local best, bestDistance
        for i, w in ipairs(waiters) do
            local d = Utils.Dist2D(w.coords, t.center)
            if not bestDistance or d < bestDistance then best, bestDistance = i, d end
        end
        t.waiter = best
        table.insert(waiters[best].tables, t.id)
    end

    Config.Staff.managementPoint = data.manager and { coords = v3(data.manager), radius = 1.2 } or nil
    Config.Furniture.enabled = data.furniture == true

    local center, points = Layout.Centroid(data)
    local radius = 15.0
    for _, p in ipairs(points) do
        local d = Utils.Dist2D(center, v3(p)) + 8.0
        if d > radius then radius = d end
    end
    Config.Venue.center = vec3(round(center.x), round(center.y), round(center.z))
    Config.Venue.radius = math.ceil(radius)
    Config.Venue.renderDistance = math.max(defaults.renderDistance or 70.0, Config.Venue.radius + 30.0)
    -- points were taken where the admin stood, so no ground snapping is needed
    Config.Venue.snapToGround = false
    if Config.Blip then Config.Blip.coords = Config.Venue.center end
    return true
end

-- The active layout as Lua for config.lua (to keep it in the config as well).
function Layout.ToLua()
    if not Layout.active then return nil end
    local function f4(v) return ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(v.x, v.y, v.z, v.w) end
    local function f3(v) return ('vec3(%.2f, %.2f, %.2f)'):format(v.x, v.y, v.z) end
    local lines = {
        '-- ' .. Config.Business.name .. ' — layout placed in-game with /hookahsetup',
        ('Config.Venue.center = %s'):format(f3(Config.Venue.center)),
        ('Config.Venue.radius = %.1f'):format(Config.Venue.radius),
        ('Config.Venue.renderDistance = %.1f'):format(Config.Venue.renderDistance),
        'Config.Venue.snapToGround = false',
        ('Config.Furniture.enabled = %s'):format(tostring(Config.Furniture.enabled == true)),
        ('Config.Hostess.coords = %s'):format(f4(Config.Hostess.coords)),
    }
    if Config.Staff.managementPoint then
        lines[#lines + 1] = ('Config.Staff.managementPoint = { coords = %s, radius = 1.2 }'):format(f3(Config.Staff.managementPoint.coords))
    else
        lines[#lines + 1] = 'Config.Staff.managementPoint = nil'
    end
    lines[#lines + 1] = 'Config.Waiters = {'
    for _, w in ipairs(Config.Waiters) do
        local ids = {}
        for _, id in ipairs(w.tables) do ids[#ids + 1] = tostring(id) end
        lines[#lines + 1] = ('    { model = %q, name = %q, scenario = %s, coords = %s, tables = { %s } },'):format(
            w.model, w.name or '', w.scenario and ('%q'):format(w.scenario) or 'nil', f4(w.coords), table.concat(ids, ', '))
    end
    lines[#lines + 1] = '}'
    lines[#lines + 1] = 'Config.Tables = {'
    for _, t in ipairs(Config.Tables) do
        local seats, spots = {}, {}
        for _, s in ipairs(t.seats) do seats[#seats + 1] = '        ' .. f4(s) .. ',' end
        for _, s in ipairs(t.hookahSpots) do spots[#spots + 1] = '        ' .. f4(s) .. ',' end
        lines[#lines + 1] = ('    { id = %d, label = %q, capacity = %d, vip = %s, seatZ = %s, center = %s,'):format(
            t.id, t.label, t.capacity, tostring(t.vip == true), t.seatZ and ('%.2f'):format(t.seatZ) or 'nil', f3(t.center))
        lines[#lines + 1] = '      seats = {'
        for _, line in ipairs(seats) do lines[#lines + 1] = line end
        lines[#lines + 1] = '      },'
        lines[#lines + 1] = '      hookahSpots = {'
        for _, line in ipairs(spots) do lines[#lines + 1] = line end
        lines[#lines + 1] = '      } },'
    end
    lines[#lines + 1] = '}'
    return table.concat(lines, '\n')
end
