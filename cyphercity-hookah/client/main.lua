-- Client entry point: bootstrap with the server, receive state updates, manage
-- the venue (spawn things only while the player is nearby) and commands.

State = {
    bootstrapped = false,
    bootstrapping = false,
    settings = nil,
    catalog = nil,
    tables = {},
    hookahs = {},
    me = {},
    staff = nil,
    inVenue = false,
    layoutRevision = nil,
    waiterVisit = nil,   -- id of the waiter visit whose menu is open
}

Client = {}

local tableDefs = {}

-- Index of Config.Tables by id (rebuilt when an in-game layout is applied).
function Client.RebuildDefs()
    tableDefs = {}
    for _, def in ipairs(Config.Tables or {}) do tableDefs[def.id] = def end
end
Client.RebuildDefs()

function Client.TableDef(id)
    return tableDefs[id]
end

function Client.Bootstrap()
    if State.bootstrapped then return true end
    if State.bootstrapping then
        local deadline = GetGameTimer() + 10000
        while State.bootstrapping and GetGameTimer() < deadline do Wait(100) end
        return State.bootstrapped
    end
    State.bootstrapping = true
    local result = Callback.Await('bootstrap', {})
    State.bootstrapping = false
    if not result.ok then return false end
    local data = result.data
    State.settings = data.settings
    State.catalog = data.catalog
    State.tables = data.tables or {}
    State.hookahs = data.hookahs or {}
    Client.ApplyLayout(data.layout)
    -- through ApplyState so a seat the server no longer knows (resource restart) is cleared
    Client.ApplyState(data.me or {})
    Bridge.framework = data.settings.framework
    Bridge.notify = Bridge.ResolveNotify()
    State.bootstrapped = true
    UI.SendInit()
    HookahClient.Sync(State.hookahs)
    return true
end

function Client.Refresh()
    local result = Callback.Await('getState', {})
    if result.ok then
        Client.ApplyState(result.data)
    end
end

function Client.ApplyState(state)
    local previous = State.me
    State.me = state or {}
    UI.Send('state', State.me)
    Seat.OnState(previous, State.me)
end

-- Server → client state ----------------------------------------------------------

RegisterNetEvent('cyphercity-hookah:client:serverReady', function()
    State.bootstrapped = false
    CreateThread(Client.Bootstrap)
end)

RegisterNetEvent('cyphercity-hookah:client:tables', function(list)
    State.tables = list or {}
    UI.Send('tables', State.tables)
end)

RegisterNetEvent('cyphercity-hookah:client:hookahs', function(list)
    State.hookahs = list or {}
    HookahClient.Sync(State.hookahs)
end)

RegisterNetEvent('cyphercity-hookah:client:playerState', function(state)
    Client.ApplyState(state)
end)

RegisterNetEvent('cyphercity-hookah:client:staffState', function(state)
    State.staff = state
    UI.Send('staff', state)
end)

RegisterNetEvent('cyphercity-hookah:client:tableAssigned', function(tableId)
    Peds.HostessGesture()
    Seat.Guide(tableId)
end)

RegisterNetEvent('cyphercity-hookah:client:openBill', function(mode)
    UI.Open('bill', { mode = mode })
end)

RegisterNetEvent('cyphercity-hookah:client:waiterServe', function(tableId)
    if State.inVenue then Peds.Serve(tableId) end
end)

-- NPC waiter visit: the waiter walks to the table; when he gets there the menu
-- opens for the guests of that table and he "writes" while they choose.
local function waiterArrived(tableId, visit)
    if (State.me or {}).tableId ~= tableId then return end
    local takeOrder = Config.WaiterBehaviour.takeOrder or {}
    if takeOrder.openMenu == false or (UI.open and UI.panel ~= 'menu') or UI.contextOpen then
        Notify.Send(L('waiter_at_table', visit.waiter), 'info')
        return
    end
    -- closing this menu without ordering tells the waiter "nothing for me" (see UI.Close)
    State.waiterVisit = visit.id
    if not UI.open then UI.Open('menu') end
end

RegisterNetEvent('cyphercity-hookah:client:waiterVisit', function(tableId, visit)
    if type(visit) ~= 'table' then return end
    local mine = (State.me or {}).tableId == tableId
    if State.inVenue then
        Peds.TakeOrder(tableId, visit, mine and function() waiterArrived(tableId, visit) end or nil)
    elseif mine then
        waiterArrived(tableId, visit)
    end
end)

RegisterNetEvent('cyphercity-hookah:client:waiterVisitEnd', function(_, visitId)
    Peds.EndVisit(visitId)
    if State.waiterVisit == visitId then State.waiterVisit = nil end
end)

RegisterNetEvent('cyphercity-hookah:client:diagnostics', function(lines)
    for _, line in ipairs(lines or {}) do print(line) end
end)

-- Framework job / duty / load events only trigger a refresh; permissions are
-- always decided by the server.
for _, eventName in ipairs({
    'esx:setJob', 'esx:playerLoaded',
    'QBCore:Client:OnJobUpdate', 'QBCore:Client:OnPlayerLoaded', 'QBCore:Client:SetDuty',
}) do
    RegisterNetEvent(eventName, function()
        if State.bootstrapped then CreateThread(Client.Refresh) else CreateThread(Client.Bootstrap) end
    end)
end

-- Venue lifecycle ----------------------------------------------------------------------

local function enterVenue()
    State.inVenue = true
    Peds.SpawnAll()
    Furniture.Spawn()
    Interactions.Register()
    HookahClient.Enter()
    -- no interaction prompts while an admin is placing points (same key)
    Target.SetActive(not Placement.active)
    if not State.bootstrapped then CreateThread(Client.Bootstrap) end
end

local function leaveVenue(keepUi)
    State.inVenue = false
    Target.SetActive(false)
    Interactions.Unregister()
    HookahClient.Leave()
    Furniture.Despawn()
    Peds.DespawnAll()
    if UI.open and not keepUi then UI.Close() end
end

local blip
local function createBlip()
    if blip then RemoveBlip(blip) blip = nil end
    local settings = Config.Blip
    if not settings or not settings.enabled then return end
    local coords = settings.coords or Config.Venue.center
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, settings.sprite or 93)
    SetBlipColour(blip, settings.color or 46)
    SetBlipScale(blip, settings.scale or 0.85)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(settings.label or 'Hookah Lounge')
    EndTextCommandSetBlipName(blip)
end

-- The in-game layout (/hookahsetup) changed, or arrived with the bootstrap:
-- everything that was spawned at the old positions is removed; the venue loop
-- spawns it again at the new positions within a second.
function Client.ApplyLayout(payload)
    if type(payload) ~= 'table' or payload.revision == State.layoutRevision then return end
    State.layoutRevision = payload.revision
    if State.inVenue then leaveVenue(true) end
    Layout.Apply(payload.layout or nil)
    Client.RebuildDefs()
    createBlip()
end

RegisterNetEvent('cyphercity-hookah:client:layout', function(payload)
    Client.ApplyLayout(payload)
end)

function Client.SetPromptsActive(active)
    Target.SetActive(active and State.inVenue)
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Bridge.target = Bridge.ResolveTarget()
    Target.Init(Bridge.target)
    Bridge.notify = Bridge.ResolveNotify()
    createBlip()
    for _, problem in ipairs(Bridge.problems) do print('^3[cyphercity-hookah]^7 ' .. problem) end

    for _ = 1, 30 do
        if Client.Bootstrap() then break end
        Wait(5000)
    end

    while true do
        local render = Config.Venue.renderDistance or 70.0
        local position = GetEntityCoords(PlayerPedId())
        local distance = #(position - Config.Venue.center)
        if not State.inVenue and distance <= render then
            enterVenue()
        elseif State.inVenue and distance > render + 10.0 then
            leaveVenue()
        end
        Wait(State.inVenue and 1000 or 2500)
    end
end)

-- Closes the UI if the player dies or gets into a vehicle while it is open.
CreateThread(function()
    while true do
        Wait(1000)
        if UI.open then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then UI.Close() end
        end
    end
end)

-- Commands -------------------------------------------------------------------------------

function Client.OpenStaff()
    local result = UI.Decorate(Callback.Await('staffOpen', {}))
    if not result.ok then
        Notify.Send(result.message, 'error')
        return
    end
    State.staff = result.data
    UI.Open('staff', { staff = result.data })
end

if Config.Staff.panelCommand then
    RegisterCommand(Config.Staff.panelCommand, function()
        Client.OpenStaff()
    end, false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if UI.open then SetNuiFocus(false, false) end
    Seat.StandLocal()
    Placement.Stop()
    Interactions.Unregister()
    HookahClient.Leave()
    Furniture.Despawn()
    Peds.DespawnAll()
    if blip then RemoveBlip(blip) end
end)
