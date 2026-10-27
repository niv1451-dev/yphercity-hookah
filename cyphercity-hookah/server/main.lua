-- Server entry point: start-up checks, business state, periodic loops and
-- player lifecycle events.

Server = {
    ready = false,
    failure = nil,
    standaloneFallback = false,
}

Business = {
    manualOpen = Config.Business.openByDefault ~= false,
}

function Business.IsOpen()
    if not Business.manualOpen then return false end
    if Config.Business.closeWhenNoStaff and Staff.OnDutyCount() == 0 then return false end
    return true
end

function Business.SetOpen(staffSrc, open)
    if not Staff.Require(staffSrc, 'toggle_business') then return false, 'no_permission' end
    Business.manualOpen = open == true
    Logger.Info('staff', ('%s %s the lounge'):format(Security.Describe(staffSrc), Business.manualOpen and 'opened' or 'closed'))
    Sync.Staff()
    for _, id in ipairs(GetPlayers()) do Sync.Player(tonumber(id)) end
    return true, L(Business.manualOpen and 'staff_business_opened' or 'staff_business_closed')
end

function Business.CustomerAllowed(src)
    local access = Config.Business.customerAccess or {}
    if access.mode ~= 'jobs' then return true end
    if Staff.GetRole(src) then return true end
    local job = Framework.GetJob(src)
    return job ~= nil and Utils.Contains(access.jobs or {}, job.name)
end

-- Multicharacter servers can switch characters without a disconnect. If the
-- server id still holds the previous character's table / bill, treat it like a
-- disconnect of that character (logged), so the new character starts clean.
function Server.CheckIdentity(src)
    if not Framework.name or Framework.name == 'standalone' then return end
    local identifier = Framework.GetIdentifier(src)
    local _, member = Tables.Of(src)
    if (member and member.identifier ~= identifier) or Orders.HasStaleState(src, identifier) then
        Logger.Warn('security', ('Character changed on %s — previous character\'s table and open bill were closed'):format(Security.Describe(src)), { player = src })
        Orders.OnDropped(src, 'character_switch')
        Tables.OnDropped(src)
        Hookah.OnDropped(src)
        Payments.OnDropped(src)
        Sync.Player(src)
    end
end

function Business.CanServe(src)
    if not Framework.IsLoaded(src) then return false, 'character_not_loaded' end
    if not Business.IsOpen() then return false, 'business_closed' end
    if not Business.CustomerAllowed(src) then return false, 'access_denied' end
    return true
end

local function banner(level, lines)
    local color = level == 'error' and '^1' or '^3'
    print(color .. '==================================================================^7')
    for _, line in ipairs(lines) do
        print(color .. '[cyphercity-hookah]^7 ' .. line)
    end
    print(color .. '==================================================================^7')
end

local function startup()
    Security.Init()
    Logger.Init()
    Staff.Init()

    local framework, err, isFallback = Bridge.ResolveFramework()
    if not framework then
        Server.failure = err
        banner('error', {
            'STARTUP FAILED — the lounge is disabled until this is fixed.',
            err,
            'How to fix:',
            '  1. Make sure your framework is ensured BEFORE cyphercity-hookah in server.cfg.',
            '  2. Or set Config.Framework in config.lua to "esx", "qbcore", "qbox" or "standalone".',
            '  3. Run "hookahdiag" in the server console for a full report.',
        })
        return
    end

    local ok, initErr = Framework.Init(framework)
    if not ok then
        Server.failure = initErr
        banner('error', {
            ('STARTUP FAILED — could not connect to framework "%s".'):format(framework),
            tostring(initErr),
            'Check that the framework resource is up to date and started, or set Config.Framework manually.',
            'Run "hookahdiag" in the server console for a full report.',
        })
        return
    end
    Bridge.framework = framework

    if isFallback then
        Server.standaloneFallback = true
        banner('warn', {
            'No framework detected (es_extended / qb-core / qbx_core) — running in STANDALONE mode.',
            Config.Standalone.allowFreeOrders
                and 'There is no money system: bills are shown and closed WITHOUT charging anyone.'
                or 'There is no money system and Config.Standalone.allowFreeOrders = false: ordering is disabled.',
            'If your server uses a framework, set Config.Framework in config.lua and restart the resource.',
        })
    end

    Bridge.inventory = Bridge.ResolveInventory()
    Inventory.Init(Bridge.inventory)
    for _, warning in ipairs(Inventory.ValidateCatalog()) do Bridge.Print('warn', warning) end

    local bankOk, bankErr = Banking.Init()
    if not bankOk then Bridge.Print('warn', bankErr) end

    for _, message in ipairs(Catalog.errors) do Bridge.Print('error', 'Config: ' .. message) end
    for _, message in ipairs(Catalog.warnings) do Bridge.Print('warn', 'Config: ' .. message) end
    Setup.Load() -- an in-game layout (data/layout.json) replaces the positions from config.lua
    for _, message in ipairs(Tables.Init()) do Bridge.Print('error', 'Config: ' .. message) end
    for _, message in ipairs(Diagnostics.ValidateConfig()) do Bridge.Print(message.level, 'Config: ' .. message.text) end
    for _, problem in ipairs(Bridge.problems) do Bridge.Print('warn', problem) end

    Persistence.Load()
    Orders.Init()

    Server.ready = true
    Bridge.ready = true
    Bridge.Print('ok', ('Ready — framework: %s | inventory: %s | money: %s | tables: %d | products: %d'):format(
        Bridge.framework, Bridge.inventory, Payments.MoneyMode(), #Tables.list, #Catalog.products
    ))
    TriggerClientEvent('cyphercity-hookah:client:serverReady', -1)
end

CreateThread(startup)

local function safeTick(name, fn)
    local ok, err = pcall(fn)
    if not ok then Logger.Error('system', ('%s tick failed: %s'):format(name, tostring(err))) end
end

CreateThread(function()
    local ticks = 0
    while true do
        Wait(1000)
        if Server.ready then
            ticks = ticks + 1
            safeTick('tables', Tables.Tick)
            safeTick('orders', Orders.Tick)
            safeTick('hookah', Hookah.Tick)
            safeTick('walkouts', Orders.TickWalkouts)
            safeTick('waiters', WaiterVisits.Tick)
            if ticks % 5 == 0 then
                safeTick('identity', function()
                    for _, id in ipairs(GetPlayers()) do Server.CheckIdentity(tonumber(id)) end
                end)
            end
            if ticks % 2 == 0 then safeTick('discord', Logger.FlushDiscord) end
            safeTick('persistence', Persistence.Save)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(250)
        if Server.ready then safeTick('sync', Sync.Flush) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if not Server.ready then return end
    Orders.OnDropped(src, 'disconnect')
    Tables.OnDropped(src)
    Hookah.OnDropped(src)
    Payments.OnDropped(src)
    Security.OnDropped(src)
    Sync.OnDropped(src)
    Setup.OnDropped(src)
    Staff.InvalidateCache()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and Server.ready then
        Persistence.Save(true)
    end
end)

-- Job / duty changes from the frameworks. These are server-local events
-- (AddEventHandler only — never RegisterNetEvent), so clients cannot fake them.
local function refreshPlayer(src)
    src = tonumber(src)
    if not src or not Server.ready then return end
    Staff.InvalidateCache()
    Sync.Player(src)
    Sync.Staff()
end

AddEventHandler('esx:setJob', function(src) refreshPlayer(src) end)
AddEventHandler('esx:playerLoaded', function(src) refreshPlayer(src) end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src) refreshPlayer(src) end)
AddEventHandler('QBCore:Server:SetDuty', function(src) refreshPlayer(src) end)
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    refreshPlayer(type(player) == 'table' and player.PlayerData and player.PlayerData.source)
end)
