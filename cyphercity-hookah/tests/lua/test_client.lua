-- Client script tests with stubbed game natives. They check that the client
-- scripts load, register their NUI callbacks / events, spawn and clean up
-- NPCs and props, and drive the built-in E-key interaction. They cannot check
-- what the game actually renders — that needs a real FiveM client.

local H = HARNESS

local natives = {}       -- name → call count
local entities = {}      -- handle → { coords, model, kind, deleted }
local nextHandle = 500
local player = { coords = vec3(0, 0, 0), keyE = false }
local calls = {}

local function record(name, ...)
    natives[name] = (natives[name] or 0) + 1
    calls[#calls + 1] = { name = name, args = table.pack(...) }
end

local function newEntity(kind, model, x, y, z)
    nextHandle = nextHandle + 1
    entities[nextHandle] = { kind = kind, model = model, coords = vec3(x, y, z) }
    return nextHandle
end

local STUBS = {
    NetworkIsSessionStarted = function() return true end,
    PlayerPedId = function() return 1 end,
    PlayerId = function() return 0 end,
    GetPlayerServerId = function() return 1 end,
    GetPlayerFromServerId = function() return 0 end,
    GetPlayerPed = function() return 1 end,
    GetEntityCoords = function(entity)
        if entity == 1 then return player.coords end
        return entities[entity] and entities[entity].coords or vec3(0, 0, 0)
    end,
    GetEntityHeading = function() return 90.0 end,
    DoesEntityExist = function(entity) return entity == 1 or (entities[entity] ~= nil and not entities[entity].deleted) end,
    IsModelInCdimage = function() return true end,
    IsModelValid = function() return true end,
    HasModelLoaded = function() return true end,
    DoesAnimDictExist = function() return true end,
    HasAnimDictLoaded = function() return true end,
    HasNamedPtfxAssetLoaded = function() return true end,
    GetGroundZFor_3dCoord = function(_, _, z) return true, z - 3.0 end,
    CreatePed = function(_, model, x, y, z) return newEntity('ped', model, x, y, z) end,
    CreateObject = function(model, x, y, z) return newEntity('object', model, x, y, z) end,
    DeleteEntity = function(entity) if entities[entity] then entities[entity].deleted = true end end,
    IsControlJustReleased = function(_, control) return control == 38 and player.keyE end,
    IsPedUsingScenario = function() return true end,
    IsEntityDead = function() return false end,
    IsPedInAnyVehicle = function() return false end,
    AddBlipForCoord = function() return 77 end,
    GetPedBoneIndex = function() return 10 end,
}

local function installStubs()
    natives, entities, calls = {}, {}, {}
    nextHandle = 500
    player = { coords = vec3(0, 0, 0), keyE = false }
    for name, fn in pairs(STUBS) do
        _G[name] = function(...) record(name, ...) return fn(...) end
    end
    setmetatable(_G, {
        __index = function(_, name)
            if type(name) == 'string' and name:match('^%u') then
                return function(...) record(name, ...) return nil end
            end
            return nil
        end,
    })
end

-- A fake server that answers the client's callback requests.
local responses = {}
local function respond(name, result) responses[name] = result end

local function installServer()
    MOCK.onServerEvent = function(eventName, cbName, requestId, payload)
        if eventName ~= 'cyphercity-hookah:cb:request' then return end
        local result = responses[cbName]
        if type(result) == 'function' then result = result(payload) end
        MOCK.FromServer('cyphercity-hookah:cb:response', requestId, result or { ok = false, code = 'internal_error' })
    end
end

local function nuiMessages(action)
    local list = {}
    for _, message in ipairs(MOCK.nui) do
        if message.action == action then list[#list + 1] = message end
    end
    return list
end

local function liveEntities(kind)
    local n = 0
    for _, e in pairs(entities) do if e.kind == kind and not e.deleted then n = n + 1 end end
    return n
end

local function bootClient()
    Logger = nil -- server-only module from the previous suite
    H.BootClient({ beforeLoad = function() installStubs() installServer() end })
    respond('bootstrap', function()
        return {
            ok = true,
            data = {
                settings = { framework = 'qbcore', moneyMode = 'money', timing = 'on_bill', accounts = {} },
                catalog = Catalog.ForNui(),
                tables = {},
                hookahs = {},
                me = { serverId = 1, perms = {} },
            },
        }
    end)
end

H.Section('Client scripts (stubbed natives)')

H.Test('client: loads and registers NUI callbacks and net events', function()
    bootClient()
    for _, name in ipairs({ 'ready', 'close', 'placeOrder', 'getBill', 'pay', 'hookahAction', 'staffOpen', 'staffAction',
        'requestTable', 'leaveTable', 'invite', 'nearbyPlayers', 'consume', 'callWaiter', 'contextSelect', 'contextClose', 'sit', 'switchPanel', 'cancelOrder',
        'setupPlace', 'setupAction', 'setupSelect', 'setupTestSit', 'setupExit' }) do
        H.True(MOCK.nuiCallbacks[name] ~= nil, 'NUI callback ' .. name)
    end
    for _, name in ipairs({ 'tables', 'hookahs', 'playerState', 'staffState', 'notify', 'consume', 'hookahSmoke', 'hookahPuff',
        'waiterServe', 'forceStand', 'openBill', 'tableAssigned', 'serverReady', 'diagnostics', 'layout', 'setupState' }) do
        H.True(MOCK.netEvents['cyphercity-hookah:client:' .. name], 'net event ' .. name)
    end
end)

H.Test('client: bootstraps with the server and sends init to the NUI after ready', function()
    bootClient()
    MOCK.Advance(100)
    H.True(State.bootstrapped, 'bootstrapped')
    H.Eq(Bridge.target, 'standalone', 'no target resource → built-in interaction')
    MOCK.nuiCallbacks.ready({}, function() end)
    local init = nuiMessages('init')
    H.True(#init >= 1, 'init message')
    H.True(#init[#init].data.catalog.products > 0, 'catalog sent')
end)

H.Test('client: NPCs and furniture spawn once near the lounge and are deleted on leaving', function()
    bootClient()
    MOCK.Advance(100)
    player.coords = Config.Venue.center
    MOCK.Advance(3000)
    H.True(State.inVenue, 'in venue')
    H.Eq(liveEntities('ped'), 1 + #Config.Waiters, 'hostess + waiters')
    local furniture = 0
    for _, def in ipairs(Config.Tables) do furniture = furniture + 1 + #def.seats end
    H.Eq(liveEntities('object'), furniture, 'tables + chairs')
    local created = natives.CreatePed
    MOCK.Advance(10000)
    H.Eq(natives.CreatePed, created, 'no re-spawning while staying')
    player.coords = vec3(Config.Venue.center.x + 500, Config.Venue.center.y, Config.Venue.center.z)
    MOCK.Advance(5000)
    H.True(not State.inVenue, 'left venue')
    H.Eq(liveEntities('ped'), 0, 'peds deleted')
    H.Eq(liveEntities('object'), 0, 'furniture deleted')
end)

H.Test('client: built-in E prompt opens the hostess panel', function()
    bootClient()
    MOCK.Advance(100)
    MOCK.nuiCallbacks.ready({}, function() end)
    local h = Config.Hostess.coords
    player.coords = vec3(h.x + 0.5, h.y, h.z)
    MOCK.Advance(3000)
    local prompts = nuiMessages('prompt')
    H.True(#prompts > 0 and prompts[#prompts].data.show, 'prompt shown')
    H.True(prompts[#prompts].data.label ~= nil, 'prompt label')
    player.keyE = true
    MOCK.Advance(50)
    player.keyE = false
    MOCK.Advance(50)
    local opens = nuiMessages('open')
    H.True(#opens > 0, 'panel opened')
    H.Eq(opens[#opens].data.panel, 'host', 'host panel')
    H.True(MOCK.focus and MOCK.focus[1] == true, 'NUI focus on')
    MOCK.nuiCallbacks.close({}, function() end)
    H.True(MOCK.focus[1] == false, 'NUI focus released')
end)

H.Test('client: server errors are translated before reaching the NUI', function()
    bootClient()
    MOCK.Advance(100)
    respond('placeOrder', { ok = false, code = 'too_many_items', args = { 25 } })
    local result
    CreateThread(function()
        MOCK.nuiCallbacks.placeOrder({ lines = {} }, function(r) result = r end)
    end)
    MOCK.Advance(100)
    H.True(result and not result.ok, 'failure passed through')
    H.Eq(result.message, L('too_many_items', 25), 'localized message')
end)

H.Test('client: hookah props follow the server list; consume animation cleans up its prop', function()
    bootClient()
    MOCK.Advance(100)
    player.coords = Config.Venue.center
    MOCK.Advance(3000)
    local before = liveEntities('object')
    MOCK.FromServer('cyphercity-hookah:client:hookahs', { { id = 7, tableId = 1, spot = 1, prop = 'prop_bong_01', flavors = {}, remaining = 100, total = 100 } })
    MOCK.Advance(100)
    H.Eq(liveEntities('object'), before + 1, 'hookah prop spawned')
    MOCK.FromServer('cyphercity-hookah:client:hookahs', {})
    MOCK.Advance(100)
    H.Eq(liveEntities('object'), before, 'hookah prop removed')
    MOCK.FromServer('cyphercity-hookah:client:consume', 'fries', 'food')
    MOCK.Advance(100)
    H.Eq(liveEntities('object'), before + 1, 'food prop in hand')
    MOCK.Advance(6000)
    H.Eq(liveEntities('object'), before, 'food prop deleted')
    H.True(not Consume.active, 'consume finished')
end)

H.Test('client: player state updates reach the NUI and a forced stand clears the seat', function()
    bootClient()
    MOCK.Advance(100)
    respond('sit', { ok = true, data = { tableId = 1, seat = 2 }, message = 'ok' })
    CreateThread(function() Seat.RequestSit(1) end)
    MOCK.Advance(100)
    H.True(Seat.current ~= nil and Seat.current.seat == 2, 'seated locally')
    MOCK.FromServer('cyphercity-hookah:client:playerState', { tableId = 1, seat = 2, perms = {} })
    MOCK.Advance(100)
    H.True(#nuiMessages('state') > 0, 'state forwarded to NUI')
    MOCK.FromServer('cyphercity-hookah:client:forceStand')
    MOCK.Advance(100)
    H.True(Seat.current == nil, 'seat cleared')
end)

H.Test('client: after a server restart the seat is cleared when the server no longer knows it', function()
    bootClient()
    MOCK.Advance(100)
    respond('sit', { ok = true, data = { tableId = 1, seat = 1 }, message = 'ok' })
    CreateThread(function() Seat.RequestSit(1) end)
    MOCK.Advance(100)
    H.True(Seat.current ~= nil, 'seated')
    MOCK.FromServer('cyphercity-hookah:client:serverReady')
    MOCK.Advance(100)
    H.True(State.bootstrapped, 'bootstrapped again')
    H.True(Seat.current == nil, 'stale seat cleared')
end)


-- A complete in-game layout far away from the demo venue of config.lua.
local LAYOUT_BASE = vec3(-1200.0, -880.0, 13.0)
local function sampleLayout()
    local b = LAYOUT_BASE
    return {
        version = 1, nextId = 3, furniture = false,
        hostess = { b.x, b.y, b.z, 180.0 },
        manager = { b.x + 6, b.y + 2, b.z },
        waiters = { { b.x + 6, b.y, b.z, 90.0 }, { b.x - 6, b.y, b.z, 270.0 } },
        tables = {
            { id = 1, label = 'ספה', vip = false, seatZ = -0.1, seats = { { b.x + 3, b.y + 4.65, b.z, 0.0 }, { b.x + 3, b.y + 7.35, b.z, 180.0 } }, spots = { { b.x + 4, b.y + 6, b.z, 0.0 } } },
            { id = 2, label = 'VIP', vip = true, seatZ = 0, seats = { { b.x - 3, b.y + 5, b.z, 0.0 } }, spots = {} },
        },
    }
end

local function sendSetupMessages()
    local list = nuiMessages('setup')
    return list[#list] and list[#list].data
end

H.Test('client: an in-game layout from the server moves the NPCs, tables and venue — and back', function()
    bootClient()
    local base = responses.bootstrap
    respond('bootstrap', function()
        local r = base()
        r.data.layout = { revision = 'r1', layout = sampleLayout() }
        return r
    end)
    MOCK.FromServer('cyphercity-hookah:client:serverReady') -- bootstrap again with the layout
    MOCK.Advance(100)
    H.True(Layout.active, 'layout applied on bootstrap')
    H.Eq(#Config.Tables, 2, 'tables from the layout')
    H.Eq(Client.TableDef(2).label, 'VIP', 'table index rebuilt')
    H.Eq(Config.Tables[1].waiter, 1, 'nearest waiter serves table 1')
    H.Eq(Config.Tables[2].waiter, 2, 'nearest waiter serves table 2')
    player.coords = LAYOUT_BASE
    MOCK.Advance(3000)
    H.True(State.inVenue, 'player at the placed venue is inside it')
    H.Eq(liveEntities('ped'), 3, 'hostess + two waiters')
    H.Eq(liveEntities('object'), 0, 'no furniture: the map has its own')
    local hostess
    for _, e in pairs(entities) do if e.kind == 'ped' and not e.deleted and math.abs(e.coords.x - LAYOUT_BASE.x) < 0.01 then hostess = e end end
    H.True(hostess and math.abs(hostess.coords.z - (LAYOUT_BASE.z - 1.0)) < 0.01, 'hostess on the floor under the placed point')
    local seat = Seat.Coords(1, 1)
    H.True(math.abs(seat.z - (LAYOUT_BASE.z - 1.0 + 0.5 - 0.1)) < 0.001, 'seat height uses the per-table correction')

    -- the admin resets the layout: everything goes back to config.lua
    MOCK.FromServer('cyphercity-hookah:client:layout', { revision = 'r2', layout = false })
    H.True(not Layout.active, 'layout removed')
    H.Eq(#Config.Tables, 6, 'config.lua tables')
    H.Eq(liveEntities('ped'), 0, 'NPCs at the old place removed at once')
    MOCK.Advance(3000)
    H.True(not State.inVenue, 'the player is no longer at the venue')
    H.Eq(liveEntities('ped'), 0, 'nothing spawned far from the venue')
    -- the same revision twice does nothing
    local created = natives.CreatePed or 0
    MOCK.FromServer('cyphercity-hookah:client:layout', { revision = 'r2', layout = false })
    MOCK.Advance(2000)
    H.Eq(natives.CreatePed or 0, created, 'no respawn for a repeated revision')
end)

H.Test('client: placement mode — admin only, place key, table tools, test sit and exit', function()
    bootClient()
    MOCK.Advance(100)
    MOCK.nuiCallbacks.ready({}, function() end)
    respond('setupOpen', { ok = false, code = 'setup_not_allowed' })
    CreateThread(function() MOCK.commands.hookahsetup() end)
    MOCK.Advance(100)
    H.True(not Placement.active, 'refused for non-admins')

    local state = { layout = sampleLayout(), active = true, missing = {}, busy = {}, file = 'data/layout.json', saved = true, oneSync = true }
    local sent = {}
    respond('setupOpen', { ok = true, data = state })
    respond('setupAction', function(payload)
        sent[#sent + 1] = payload
        return { ok = true, data = state, message = 'ok' }
    end)
    respond('setupClose', { ok = true })
    player.coords = LAYOUT_BASE
    CreateThread(function() MOCK.commands.hookahsetup() end)
    MOCK.Advance(100)
    H.True(Placement.active, 'placement mode on')
    local opens = nuiMessages('open')
    H.Eq(opens[#opens].data.panel, 'setup', 'setup menu opened')
    H.True(not Target.active, 'interaction prompts off while placing')
    MOCK.nuiCallbacks.close({}, function() end)

    -- place key with the default tool (hostess) sends the position as a fallback for servers without OneSync
    CreateThread(function() MOCK.commands.hookahsetup_place() end)
    MOCK.Advance(100)
    H.Eq(#sent, 1, 'one request')
    H.Eq(sent[1].action, 'hostess', 'hostess tool')
    H.True(sent[1].pos and sent[1].pos.x == LAYOUT_BASE.x and sent[1].pos.h == 90.0, 'position + heading attached')

    -- seat tool needs a table
    MOCK.nuiCallbacks.setupSelect({ tool = 'seat', tableId = false }, function() end)
    CreateThread(function() MOCK.commands.hookahsetup_place() end)
    MOCK.Advance(100)
    H.Eq(#sent, 1, 'no request without a table')
    MOCK.nuiCallbacks.setupSelect({ tableId = 2 }, function() end)
    CreateThread(function() MOCK.commands.hookahsetup_place() end)
    MOCK.Advance(100)
    H.Eq(sent[2].action, 'seat_add', 'seat tool')
    H.Eq(sent[2].tableId, 2, 'selected table')
    MOCK.nuiCallbacks.setupSelect({ tableId = 99 }, function() end)
    H.Eq(Placement.tableId, 2, 'unknown table ids are ignored')

    -- markers are drawn every frame while the mode is on
    local markers = natives.DrawMarker or 0
    MOCK.Advance(500)
    H.True((natives.DrawMarker or 0) > markers + 20, 'markers drawn')
    H.True((natives.EndTextCommandDisplayText or 0) > 0, 'numbers drawn above the points')
    H.True(sendSetupMessages().active, 'HUD told the mode is on')

    -- test sit on table 1 seat 2 (local only), the place key stands up again
    calls = {}
    MOCK.nuiCallbacks.setupTestSit({ tableId = 1, seat = 2 }, function() end)
    local sit
    for _, c in ipairs(calls) do if c.name == 'TaskStartScenarioAtPosition' then sit = c.args end end
    H.True(sit ~= nil, 'sitting scenario played')
    H.True(math.abs(sit[5] - (LAYOUT_BASE.z - 1.0 + 0.5 - 0.1)) < 0.001, 'test sit uses the real seat height')
    H.Eq(sit[6], 180.0, 'facing the table')
    H.True(Placement.sitting, 'sitting')
    CreateThread(function() MOCK.commands.hookahsetup_place() end)
    MOCK.Advance(100)
    H.True(not Placement.sitting, 'stood up')
    H.Eq(#sent, 2, 'standing up sends nothing')

    -- export answers with text only: the state must not be replaced by it
    respond('setupAction', { ok = true, data = { text = 'Config.Tables = {}' }, message = 'copied' })
    local exported
    CreateThread(function() MOCK.nuiCallbacks.setupAction({ action = 'export' }, function(r) exported = r end) end)
    MOCK.Advance(100)
    H.Eq(exported.data.text, 'Config.Tables = {}', 'export text passed to the NUI')
    H.True(Placement.state.layout ~= nil, 'state kept')

    MOCK.nuiCallbacks.setupExit({}, function() end)
    MOCK.Advance(100)
    H.True(not Placement.active, 'mode off')
    H.True(not sendSetupMessages().active, 'HUD hidden')
    local closed = false
    for _, e in ipairs(MOCK.serverEvents) do if e.args[1] == 'setupClose' then closed = true end end
    H.True(closed, 'server told the editor left')
    local markersOff = natives.DrawMarker or 0
    MOCK.Advance(500)
    H.True((natives.DrawMarker or 0) - markersOff < 5, 'markers stop')
end)

H.Test('client: unknown natives used by the client scripts are reported', function()
    bootClient()
    MOCK.Advance(100)
    player.coords = Config.Venue.center
    MOCK.Advance(3000)
    -- every PascalCase global that the scripts called but which is not stubbed
    local used = {}
    for name in pairs(natives) do used[#used + 1] = name end
    table.sort(used)
    CLIENT_NATIVES_USED = used
    H.True(#used > 10, 'natives recorded')
end)

setmetatable(_G, nil)
