-- In-game placement tool (/hookahsetup, server admins only).
-- The admin picks a tool in the menu (hostess, waiter, seat, hookah spot, staff
-- point), walks to the spot and presses the place key. The server reads the
-- position, saves data/layout.json and applies the layout to every player.
-- This file: the mode itself, the key bindings, the HUD and the markers that
-- show every placed point while the mode is on.

Placement = {
    active = false,
    state = nil,        -- from the server: layout (draft), active, missing, busy, ...
    tool = 'hostess',
    tableId = nil,
    sitting = false,
    busy = false,
}

local TOOLS = {
    hostess = { action = 'hostess' },
    waiter = { action = 'waiter_add' },
    seat = { action = 'seat_add', needsTable = true },
    spot = { action = 'spot_add', needsTable = true },
    manager = { action = 'manager' },
}

-- marker colours per kind of point
local COLORS = {
    hostess = { 212, 175, 95 },
    waiter = { 110, 170, 230 },
    seat = { 90, 200, 120 },
    spot = { 200, 120, 220 },
    manager = { 230, 120, 90 },
    table = { 212, 175, 95 },
}

local settings = Config.Setup or {}
local placeKey = settings.placeKey or 'E'
local menuKey = settings.menuKey or 'F7'

local function layout()
    return (Placement.state and Placement.state.layout) or {}
end

local function list(value)
    return type(value) == 'table' and value or {}
end

local function findTable(id)
    for _, t in ipairs(list(layout().tables)) do
        if t.id == id then return t end
    end
    return nil
end

local function context()
    return {
        setup = Placement.state,
        tool = Placement.tool,
        tableId = Placement.tableId,
        sitting = Placement.sitting,
        keys = { place = placeKey, menu = menuKey },
    }
end

-- Keeps the NUI (menu + HUD) in line with the Lua side.
local function push()
    local data = context()
    data.active = Placement.active
    UI.Send('setup', data)
end

function Placement.SetState(state)
    if type(state) ~= 'table' then return end
    Placement.state = state
    if state.selected then
        Placement.tableId = state.selected
        Placement.tool = 'seat'
    end
    if Placement.tableId and not findTable(Placement.tableId) then Placement.tableId = nil end
    push()
end

RegisterNetEvent('cyphercity-hookah:client:setupState', function(state)
    if Placement.active then Placement.SetState(state) end
end)

-- Sends an edit to the server. The position is added for servers without
-- OneSync (with OneSync the server reads the position itself).
local function send(payload)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    payload.pos = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped) }
    local result = UI.Decorate(Callback.Await('setupAction', payload))
    -- edits answer with the new state; 'export' answers with the config text only
    if result.ok and type(result.data) == 'table' and result.data.layout then Placement.SetState(result.data) end
    return result
end

function Placement.StandUp()
    if not Placement.sitting then return end
    Placement.sitting = false
    ClearPedTasks(PlayerPedId())
    push()
end

-- Sits the admin on a placed seat (local only) to check its position and height.
function Placement.TestSit(tableId, index)
    local t = findTable(tableId)
    local seats = t and list(t.seats) or {}
    local seat = seats[index or #seats]
    if not seat then
        Notify.Send(L('setup_no_seats'), 'error')
        return
    end
    -- same height as Seat.Coords uses for an active layout (points are standing positions)
    local z = seat[3] - 1.0 + (Config.Furniture.seatZOffset or 0.5) + (t.seatZ or 0.0)
    TaskStartScenarioAtPosition(PlayerPedId(), Seat.SCENARIO, seat[1], seat[2], z, seat[4] or 0.0, -1, true, true)
    Placement.sitting = true
    Notify.Send(L('setup_sit_test', placeKey), 'info')
    push()
end

-- Place key: puts the selected tool's point where the admin stands.
function Placement.Place(fromMenu)
    if not Placement.active or Placement.busy then return nil end
    if not fromMenu and UI.IsOpen() then return nil end
    if Placement.sitting then
        Placement.StandUp()
        return nil
    end
    local tool = TOOLS[Placement.tool]
    if not tool then return nil end
    local result
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        result = { ok = false, message = L('setup_in_vehicle') }
    elseif tool.needsTable and not Placement.tableId then
        result = { ok = false, message = L('setup_select_table') }
    else
        Placement.busy = true
        result = send({ action = tool.action, tableId = Placement.tableId })
        Placement.busy = false
    end
    if not fromMenu then Notify.Send(result.message, result.ok and 'success' or 'error') end
    return result
end

local startMarkers

function Placement.Open()
    if Placement.active then
        UI.Open('setup', context())
        return
    end
    local result = UI.Decorate(Callback.Await('setupOpen', {}))
    if not result.ok then
        Notify.Send(result.message, 'error')
        return
    end
    Placement.active = true
    Placement.SetState(result.data)
    Client.SetPromptsActive(false)
    startMarkers()
    Notify.Send(L('setup_mode_on', placeKey, menuKey), 'info')
    UI.Open('setup', context())
end

-- Leaves the mode locally (also used when the resource stops).
function Placement.Stop()
    if not Placement.active then return end
    Placement.StandUp()
    Placement.active = false
    push()
    Client.SetPromptsActive(true)
end

function Placement.Exit()
    if not Placement.active then return end
    Placement.Stop()
    CreateThread(function() Callback.Await('setupClose', {}) end)
    Notify.Send(L('setup_mode_off'), 'info')
end

-- Commands and key bindings -------------------------------------------------------
-- Key bindings can be changed per player: Settings → Key Bindings → FiveM.
-- GTA's settings menu cannot show Hebrew, so the descriptions are in English.

RegisterCommand(settings.command or 'hookahsetup', function()
    Placement.Open()
end, false)

RegisterCommand('hookahsetup_place', function()
    if Placement.active then Placement.Place(false) end
end, false)

RegisterCommand('hookahsetup_menu', function()
    if Placement.active and not UI.IsOpen() then UI.Open('setup', context()) end
end, false)

RegisterKeyMapping('hookahsetup_place', "Sheikh's Place setup: place point here (admins)", 'keyboard', placeKey)
RegisterKeyMapping('hookahsetup_menu', "Sheikh's Place setup: open menu (admins)", 'keyboard', menuKey)

-- NUI ---------------------------------------------------------------------------------

RegisterNUICallback('setupPlace', function(_, cb)
    cb(Placement.Place(true) or { ok = false })
end)

RegisterNUICallback('setupAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    if not Placement.active then
        cb({ ok = false })
        return
    end
    cb(send(data))
end)

RegisterNUICallback('setupSelect', function(data, cb)
    data = type(data) == 'table' and data or {}
    if TOOLS[data.tool] then Placement.tool = data.tool end
    local id = tonumber(data.tableId)
    if data.tableId == false then
        Placement.tableId = nil
    elseif id and findTable(id) then
        Placement.tableId = id
    end
    cb({ ok = true })
end)

RegisterNUICallback('setupTestSit', function(data, cb)
    data = type(data) == 'table' and data or {}
    cb({ ok = true })
    UI.Close()
    Placement.TestSit(tonumber(data.tableId), tonumber(data.seat))
end)

RegisterNUICallback('setupExit', function(_, cb)
    cb({ ok = true })
    UI.Close()
    Placement.Exit()
end)

-- Markers -------------------------------------------------------------------------------
-- Every placed point gets a coloured ring on the floor, a short line for its
-- heading and a number above it (GTA's own text cannot show Hebrew, so the
-- labels are numbers; the HUD explains the colours). Positions are collected
-- twice a second, drawing happens every frame.

local function marker(kind, x, y, floor, size)
    local c = COLORS[kind]
    DrawMarker(1, x, y, floor, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 0.06,
        c[1], c[2], c[3], 150, false, false, 2, false, nil, nil, false)
end

local function headingLine(kind, x, y, floor, heading, length)
    local c = COLORS[kind]
    local h = math.rad(heading or 0.0)
    DrawLine(x, y, floor + 0.08, x - math.sin(h) * length, y + math.cos(h) * length, floor + 0.08, c[1], c[2], c[3], 230)
end

local function text3d(kind, x, y, z, label)
    local c = COLORS[kind]
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(c[1], c[2], c[3], 235)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function collect()
    local items = {}
    local function add(kind, p, label, size, lineLength)
        if type(p) ~= 'table' or not p[3] then return end
        items[#items + 1] = { kind = kind, x = p[1], y = p[2], floor = p[3] - 1.0, heading = p[4], label = label, size = size or 0.45, line = lineLength }
    end
    local data = layout()
    add('hostess', data.hostess, nil, 0.6, 0.8)
    if data.manager then add('manager', data.manager, nil, 0.8) end
    for i, p in ipairs(list(data.waiters)) do add('waiter', p, tostring(i), 0.6, 0.8) end
    for _, t in ipairs(list(data.tables)) do
        local seats = list(t.seats)
        local cx, cy, cz = 0, 0, 0
        for i, p in ipairs(seats) do
            add('seat', p, ('%d-%d'):format(t.id, i), 0.4, 0.6)
            cx, cy, cz = cx + p[1], cy + p[2], cz + p[3]
        end
        for i, p in ipairs(list(t.spots)) do add('spot', p, ('%d-%d'):format(t.id, i), 0.3) end
        if #seats > 0 then
            local center = { cx / #seats, cy / #seats, cz / #seats }
            add('table', center, tostring(t.id), t.id == Placement.tableId and 1.4 or 0.9)
            if t.id == Placement.tableId then
                for _, p in ipairs(seats) do
                    items[#items + 1] = { link = true, x1 = p[1], y1 = p[2], z1 = p[3] - 0.95, x2 = center[1], y2 = center[2], z2 = center[3] - 0.95 }
                end
            end
        end
    end
    return items
end

startMarkers = function()
    CreateThread(function()
        local items, collectedAt = {}, 0
        local labelDistance = settings.labelDistance or 25.0
        while Placement.active do
            local now = GetGameTimer()
            if now - collectedAt > 500 then
                items = collect()
                collectedAt = now
            end
            local ped = PlayerPedId()
            local position = GetEntityCoords(ped)
            for _, item in ipairs(items) do
                if item.link then
                    DrawLine(item.x1, item.y1, item.z1, item.x2, item.y2, item.z2, 212, 175, 95, 160)
                else
                    local distance = #(position - vec3(item.x, item.y, item.floor))
                    if distance < 60.0 then
                        marker(item.kind, item.x, item.y, item.floor, item.size)
                        if item.line then headingLine(item.kind, item.x, item.y, item.floor, item.heading, item.line) end
                        if item.label and distance < labelDistance then text3d(item.kind, item.x, item.y, item.floor + 1.25, item.label) end
                    end
                end
            end
            -- preview of the point the place key would create: ring + facing line
            local tool = Placement.tool
            if not Placement.sitting and COLORS[tool] then
                local floor = position.z - 1.0
                local heading = GetEntityHeading(ped)
                local x, y = position.x, position.y
                if tool == 'seat' then
                    -- seats are saved behind the admin (see Config.Setup.seatBackOffset)
                    local back, h = settings.seatBackOffset or 0.35, math.rad(heading)
                    x, y = x + math.sin(h) * back, y - math.cos(h) * back
                end
                marker(tool, x, y, floor, 0.35)
                headingLine(tool, x, y, floor, heading, 1.0)
            end
            Wait(0)
        end
    end)
end
