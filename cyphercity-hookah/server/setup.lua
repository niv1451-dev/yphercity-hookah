-- In-game placement tool (/hookahsetup). An admin stands where the hostess,
-- a waiter, a seat or a hookah should be and presses a key; the server takes
-- the admin's own position (with OneSync), saves data/layout.json and applies
-- the layout to every player at once. Only players with the admin ACE
-- (ServerConfig.AdminAce) can use it, and every change is logged.

Setup = {
    revision = tostring(os.time()) .. ':0',
    saved = true,
}

local editors = {}      -- [src] = true while the placement tool is open
local changes = 0
local saveWarned = false

local function fail(code, ...)
    return { ok = false, code = code, args = { ... } }
end

local function success(data, message)
    return { ok = true, data = data, message = message }
end

local function file()
    return (ServerConfig.Layout and ServerConfig.Layout.file) or 'data/layout.json'
end

local function settings()
    return Config.Setup or {}
end

function Setup.IsAdmin(src)
    return IsPlayerAceAllowed(src, ServerConfig.AdminAce) == true
end

-- Reads data/layout.json (if any). Runs once at start-up, before Tables.Init.
function Setup.Load()
    local raw = LoadResourceFile(GetCurrentResourceName(), file())
    local data
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            data = Layout.Sanitize(decoded)
        else
            Bridge.Print('warn', ('Could not read %s — using the positions from config.lua'):format(file()))
        end
    end
    Layout.Apply(data)
    if Layout.active then
        Bridge.Print('ok', ('In-game layout from %s is active: %d tables, %d waiters'):format(file(), #Config.Tables, #Config.Waiters))
    elseif data then
        Bridge.Print('warn', ('In-game layout in %s is not finished yet (missing: %s) — using the positions from config.lua until it is'):format(
            file(), table.concat(Layout.Missing(data), ', ')))
    end
end

local function save()
    local content = Layout.data and json.encode(Layout.data) or ''
    local ok = SaveResourceFile(GetCurrentResourceName(), file(), content, -1)
    Setup.saved = ok == true
    if not Setup.saved and not saveWarned then
        saveWarned = true
        Bridge.Print('warn', ('Could not write %s (folder read-only?). The layout works until the next restart only.'):format(file()))
    end
    return Setup.saved
end

-- What clients receive: the active layout (or false = use config.lua).
function Setup.Payload()
    return { revision = Setup.revision, layout = Layout.active and Layout.data or false }
end

function Setup.State()
    local data = Layout.data or Layout.Empty()
    local busy = {}
    if Layout.active then
        for _, t in ipairs(Tables.list) do
            if t.status ~= 'free' then busy[#busy + 1] = t.id end
        end
    end
    return {
        layout = data,
        active = Layout.active,
        missing = Layout.Missing(data),
        busy = busy,
        file = file(),
        saved = Setup.saved,
        oneSync = Security.oneSync,
        limits = Layout.MAX,
    }
end

-- The admin's position and heading. With OneSync the server reads it itself;
-- without OneSync it cannot see positions, so the admin's client sends it.
local function here(src, payload)
    if Security.oneSync then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            if c and (c.x ~= 0 or c.y ~= 0 or c.z ~= 0) then
                return Layout.CleanPoint({ c.x, c.y, c.z, GetEntityHeading(ped) }, true)
            end
        end
        return nil
    end
    local p = type(payload.pos) == 'table' and payload.pos or {}
    return Layout.CleanPoint({ tonumber(p.x), tonumber(p.y), tonumber(p.z), tonumber(p.h) }, true)
end

-- A point moved `distance` metres along its own heading (negative = backwards).
-- GTA headings: 0 = north (+y), 90 = west (-x).
local function moved(point, distance)
    local h = math.rad(point[4] or 0.0)
    return { point[1] - math.sin(h) * distance, point[2] + math.cos(h) * distance, point[3], point[4] }
end

local function near(a, b, distance)
    return Utils.Dist2D(vec3(a[1], a[2], a[3]), vec3(b[1], b[2], b[3])) < distance and math.abs(a[3] - b[3]) < 1.5
end

-- Checks a new point against the rest of the layout.
local function checkPoint(data, point, sameKind)
    if not point then return false, 'setup_no_position' end
    local center = Layout.Centroid(data)
    local spread = settings().maxSpread or 150.0
    if center and Utils.Dist2D(center, vec3(point[1], point[2], point[3])) > spread then
        return false, 'setup_too_far', math.floor(spread)
    end
    for _, other in ipairs(sameKind or {}) do
        if near(point, other, 0.35) then return false, 'setup_too_close' end
    end
    return true
end

-- The table being edited and its position in data.tables.
local function needTable(data, payload)
    local t, index = Layout.FindTable(data, payload.tableId)
    if not t then return nil, 'setup_select_table' end
    return t, index
end

-- Every handler edits `data` (a copy of the layout) and returns
-- true, messageKey, args... — or false, errorCode, args...
local ACTIONS = {}

ACTIONS.hostess = function(data, payload, src)
    data.hostess = nil -- the old spot does not count for the distance check (it may be the mistake)
    local point = here(src, payload)
    local ok, code, arg = checkPoint(data, point)
    if not ok then return false, code, arg end
    data.hostess = point
    return true, 'setup_hostess_set'
end

ACTIONS.waiter_add = function(data, payload, src)
    if #data.waiters >= Layout.MAX.waiters then return false, 'setup_limit', Layout.MAX.waiters end
    local point = here(src, payload)
    local ok, code, arg = checkPoint(data, point, data.waiters)
    if not ok then return false, code, arg end
    data.waiters[#data.waiters + 1] = point
    return true, 'setup_waiter_added', #data.waiters
end

ACTIONS.waiter_remove = function(data, payload)
    local index = Utils.ToInt(payload.index) or #data.waiters
    if not data.waiters[index] then return false, 'setup_nothing_to_remove' end
    table.remove(data.waiters, index)
    return true, 'setup_waiter_removed', index
end

ACTIONS.manager = function(data, payload, src)
    data.manager = nil
    local point = here(src, payload)
    local ok, code, arg = checkPoint(data, point)
    if not ok then return false, code, arg end
    data.manager = { point[1], point[2], point[3] }
    return true, 'setup_manager_set'
end

ACTIONS.manager_clear = function(data)
    if not data.manager then return false, 'setup_nothing_to_remove' end
    data.manager = nil
    return true, 'setup_manager_cleared'
end

ACTIONS.table_add = function(data)
    if #data.tables >= Layout.MAX.tables then return false, 'setup_limit', Layout.MAX.tables end
    local id = data.nextId
    data.nextId = id + 1
    local label = Layout.DefaultLabel(id)
    data.tables[#data.tables + 1] = { id = id, label = label, vip = false, seatZ = 0, seats = {}, spots = {} }
    return true, 'setup_table_added', label
end

ACTIONS.table_remove = function(data, payload)
    local t, index = needTable(data, payload)
    if not t then return false, index end -- index holds the error code here
    table.remove(data.tables, index)
    return true, 'setup_table_removed', t.label
end

ACTIONS.table_update = function(data, payload)
    local t, err = needTable(data, payload)
    if not t then return false, err end
    if payload.label ~= nil then
        local label = Utils.SanitizeString(payload.label, Layout.MAX.label)
        if not label or label == '' then return false, 'setup_label_invalid' end
        t.label = label
    end
    if payload.vip ~= nil then t.vip = payload.vip == true end
    if payload.seatZ ~= nil then
        if type(payload.seatZ) ~= 'number' then return false, 'invalid_request' end
        t.seatZ = Utils.Clamp(payload.seatZ, -Layout.SEAT_Z, Layout.SEAT_Z)
    end
    return true, 'setup_table_updated', t.label
end

ACTIONS.seat_add = function(data, payload, src)
    local t, err = needTable(data, payload)
    if not t then return false, err end
    if #t.seats >= Layout.MAX.seats then return false, 'setup_limit', Layout.MAX.seats end
    local point = here(src, payload)
    if point then
        -- the admin stands in front of the chair, back to it, facing the table
        point = moved(point, -(settings().seatBackOffset or 0.35))
    end
    local ok, code, arg = checkPoint(data, point, t.seats)
    if not ok then return false, code, arg end
    t.seats[#t.seats + 1] = point
    return true, 'setup_seat_added', #t.seats, t.label
end

-- Fine-tuning of one seat: forward / back along its heading, or turning it.
ACTIONS.seat_nudge = function(data, payload)
    local t, err = needTable(data, payload)
    if not t then return false, err end
    local index = Utils.ToInt(payload.index) or #t.seats
    local seat = t.seats[index]
    if not seat then return false, 'setup_nothing_to_remove' end
    local forward = type(payload.forward) == 'number' and Utils.Clamp(payload.forward, -0.5, 0.5) or 0
    local turn = type(payload.turn) == 'number' and Utils.Clamp(payload.turn, -180, 180) or 0
    if forward == 0 and turn == 0 then return false, 'invalid_request' end
    local point = moved(seat, forward)
    point[4] = (point[4] + turn) % 360.0
    t.seats[index] = point
    return true, 'setup_seat_moved', index, t.label
end

ACTIONS.seat_remove = function(data, payload)
    local t, err = needTable(data, payload)
    if not t then return false, err end
    if #t.seats == 0 then return false, 'setup_nothing_to_remove' end
    table.remove(t.seats)
    return true, 'setup_seat_removed', t.label
end

ACTIONS.spot_add = function(data, payload, src)
    local t, err = needTable(data, payload)
    if not t then return false, err end
    if #t.spots >= Layout.MAX.spots then return false, 'setup_limit', Layout.MAX.spots end
    local point = here(src, payload)
    local ok, code, arg = checkPoint(data, point, t.spots)
    if not ok then return false, code, arg end
    t.spots[#t.spots + 1] = point
    return true, 'setup_spot_added', #t.spots, t.label
end

ACTIONS.spot_remove = function(data, payload)
    local t, err = needTable(data, payload)
    if not t then return false, err end
    if #t.spots == 0 then return false, 'setup_nothing_to_remove' end
    table.remove(t.spots)
    return true, 'setup_spot_removed', t.label
end

ACTIONS.furniture = function(data, payload)
    data.furniture = payload.enabled == true
    return true, data.furniture and 'setup_furniture_on' or 'setup_furniture_off'
end

-- Applies an edited layout (nil = back to config.lua) after checking that no
-- table in use would change. Returns true, or false + error code.
local function commit(candidate)
    local wasActive = Layout.active
    local willBeActive = Layout.IsComplete(candidate)
    if wasActive and candidate and not willBeActive then
        -- a running lounge always keeps a hostess, a waiter and a table
        return false, 'setup_keep_' .. Layout.Missing(candidate)[1]
    end
    if wasActive or willBeActive then
        local defs = willBeActive and Layout.BuildTables(candidate) or Layout.DefaultTables()
        local conflicts = Tables.LayoutConflicts(defs)
        if #conflicts > 0 then return false, 'setup_table_busy', table.concat(conflicts, ', ') end
    end

    Layout.Apply(candidate)
    if wasActive or Layout.active then
        for _, message in ipairs(Tables.Reload()) do Bridge.Print('error', 'Layout: ' .. message) end
        changes = changes + 1
        Setup.revision = ('%d:%d'):format(os.time(), changes)
        TriggerClientEvent('cyphercity-hookah:client:layout', -1, Setup.Payload())
        Sync.Staff()
    end
    save()
    return true
end

local function pushToEditors(except)
    local state = Setup.State()
    for src in pairs(editors) do
        if src ~= except then TriggerClientEvent('cyphercity-hookah:client:setupState', src, state) end
    end
end

local function gate(src)
    if Setup.IsAdmin(src) then return true end
    Security.Flag(src, 'setup_denied')
    return false
end

Callback.Register('setupOpen', function(src)
    if not gate(src) then return fail('setup_not_allowed') end
    editors[src] = true
    Logger.Info('setup', ('%s opened the placement tool'):format(Security.Describe(src)))
    return success(Setup.State())
end, 'setup')

Callback.Register('setupClose', function(src)
    editors[src] = nil
    return success()
end, 'setup')

Callback.Register('setupAction', function(src, payload)
    if not gate(src) then return fail('setup_not_allowed') end
    local action = payload.action

    if action == 'export' then
        if not Layout.active then return fail('setup_export_incomplete') end
        return success({ text = Layout.ToLua() }, L('setup_exported'))
    end

    local wasActive = Layout.active
    local candidate, message, args
    if action == 'reset' then
        if not Layout.data then return fail('setup_nothing_to_remove') end
        message, args = 'setup_reset_done', {}
    else
        local handler = ACTIONS[action]
        if not handler then return fail('invalid_request') end
        candidate = Utils.DeepCopy(Layout.data or Layout.Empty())
        local result = table.pack(handler(candidate, payload, src))
        if not result[1] then return fail(table.unpack(result, 2, result.n)) end
        message, args = result[2], { table.unpack(result, 3, result.n) }
        candidate = Layout.Sanitize(candidate)
    end

    local ok, code, arg = commit(candidate)
    if not ok then return fail(code, arg) end

    Logger.Info('setup', ('%s: %s'):format(Security.Describe(src), L(message, table.unpack(args))), {
        player = src, action = action, tableId = payload.tableId,
    })
    if not wasActive and Layout.active then message, args = 'setup_activated', { Config.Business.name } end
    pushToEditors(src)

    local state = Setup.State()
    if action == 'table_add' then state.selected = candidate.tables[#candidate.tables].id end
    return success(state, L(message, table.unpack(args)))
end, 'setup')

function Setup.OnDropped(src)
    editors[src] = nil
end

function Setup.Report()
    local data = Layout.data
    if not data then return 'Layout: config.lua positions (no in-game layout yet — /hookahsetup)' end
    return ('Layout: %s | file: %s | hostess: %s | waiters: %d | tables: %d (with seats: %d)%s'):format(
        Layout.active and 'in-game layout ACTIVE' or 'in-game layout is a draft',
        file(), data.hostess and 'yes' or 'no', #data.waiters, #data.tables, Layout.UsableTables(data),
        Layout.active and '' or (' | missing: ' .. table.concat(Layout.Missing(data), ', ')))
end
