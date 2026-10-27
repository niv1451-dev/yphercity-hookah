-- Test harness: loads the resource exactly in fxmanifest.lua order inside the
-- FiveM mock, with fake ESX / QBCore / Qbox objects shaped like their real
-- public APIs (verified against the frameworks' current source code).

local H = {}

H.results = { passed = 0, failed = 0, failures = {} }

-- Manifest -----------------------------------------------------------------------
function H.ReadManifest()
    local manifest = { shared = {}, server = {}, client = {}, files = {}, meta = {} }
    local env = {}
    local function collector(list)
        return function(value)
            if type(value) == 'table' then
                for _, v in ipairs(value) do list[#list + 1] = v end
            else
                list[#list + 1] = value
            end
        end
    end
    local function meta(key) return function(value) manifest.meta[key] = value end end
    env.fx_version = meta('fx_version')
    env.game = meta('game')
    env.lua54 = meta('lua54')
    env.name = meta('name')
    env.author = meta('author')
    env.description = meta('description')
    env.version = meta('version')
    env.ui_page = meta('ui_page')
    env.shared_scripts = collector(manifest.shared)
    env.shared_script = collector(manifest.shared)
    env.server_scripts = collector(manifest.server)
    env.client_scripts = collector(manifest.client)
    env.files = collector(manifest.files)
    env.dependency = collector({})
    env.dependencies = collector({})
    local chunk = assert(loadfile(RESOURCE_ROOT .. '/fxmanifest.lua', 't', env))
    chunk()
    return manifest
end

-- Framework fakes ----------------------------------------------------------------------
local function qbPlayer(p)
    local data = {
        source = p.id,
        citizenid = 'CID' .. p.id,
        charinfo = { firstname = p.first or ('Player' .. p.id), lastname = p.last or 'Test' },
        money = { cash = p.cash or 1000, bank = p.bank or 5000, crypto = 0 },
        job = {
            name = p.job or 'unemployed', label = p.job or 'Unemployed',
            onduty = p.onduty ~= false, isboss = p.isboss == true,
            grade = { name = 'g' .. (p.grade or 0), level = p.grade or 0 },
        },
        metadata = { hunger = 50, thirst = 50 },
    }
    local player = { PlayerData = data, Functions = {} }
    player.Functions.RemoveMoney = function(kind, amount)
        if p.failRemove then return false end
        if data.money[kind] == nil then return false end
        if kind == 'cash' and data.money[kind] - amount < 0 then return false end
        data.money[kind] = data.money[kind] - amount
        return true
    end
    player.Functions.AddMoney = function(kind, amount)
        data.money[kind] = (data.money[kind] or 0) + amount
        return true
    end
    player.Functions.GetMoney = function(kind) return data.money[kind] end
    player.Functions.SetMetaData = function(key, value) data.metadata[key] = math.max(0, math.min(100, value)) end
    return player
end

local function esxPlayer(p)
    local accounts = { money = { name = 'money', money = p.cash or 1000 }, bank = { name = 'bank', money = p.bank or 5000 } }
    local xPlayer = { identifier = 'char1:' .. p.id, source = p.id }
    xPlayer.getName = function() return (p.first or ('Player' .. p.id)) .. ' ' .. (p.last or 'Test') end
    xPlayer.getJob = function()
        return { name = p.job or 'unemployed', label = p.job or 'Unemployed', grade = p.grade or 0, grade_name = p.gradeName or ('g' .. (p.grade or 0)), onDuty = p.onduty ~= false }
    end
    xPlayer.job = xPlayer.getJob()
    xPlayer.getAccount = function(name) return accounts[name] end
    xPlayer.removeAccountMoney = function(name, amount)
        if amount <= 0 then error('invalid amount') end
        if p.esxLegacyNoReturn then
            if not p.esxNoDeduct then accounts[name].money = accounts[name].money - amount end
            return nil
        end
        if p.failRemove or accounts[name].money - amount < 0 then return false end
        accounts[name].money = accounts[name].money - amount
        return true
    end
    xPlayer.addAccountMoney = function(name, amount) accounts[name].money = accounts[name].money + amount return true end
    xPlayer.getInventoryItem = function(name) return { name = name, count = (p.items or {})[name] or 0 } end
    xPlayer.canCarryItem = function() return true end
    xPlayer.addInventoryItem = function(name, count) p.items = p.items or {}; p.items[name] = (p.items[name] or 0) + count return true end
    xPlayer.removeInventoryItem = function(name, count) p.items[name] = (p.items[name] or 0) - count return true end
    xPlayer.showNotification = function() end
    xPlayer._accounts = accounts
    return xPlayer
end

function H.InstallFramework(kind)
    local store = {}
    H.store = store
    if kind == 'qbcore' then
        MOCK.resources['qb-core'] = 'started'
        local QBCore = { Functions = { GetPlayer = function(src) return store[src] end }, Shared = { Items = { beer = { name = 'beer' } } } }
        MOCK.exports['qb-core'] = { GetCoreObject = function() return QBCore end }
    elseif kind == 'qbox' then
        MOCK.resources['qbx_core'] = 'started'
        MOCK.resources['qb-core'] = 'started' -- qbx_core provides 'qb-core'
        MOCK.exports['qbx_core'] = { GetPlayer = function(_, src) return store[src] end }
        MOCK.exports['qb-core'] = { GetCoreObject = function() error('bridge should not be used') end }
    elseif kind == 'esx' then
        MOCK.resources['es_extended'] = 'started'
        local ESX = {
            GetPlayerFromId = function(src) return store[src] end,
            GetItemLabel = function(name) return name == 'beer' and 'Beer' or nil end,
        }
        MOCK.exports['es_extended'] = { getSharedObject = function() return ESX end }
    end
    H.frameworkKind = kind
end

-- Adds a player both to the FiveM mock and to the active framework fake.
function H.Player(p)
    p.name = p.name or ('Player' .. p.id)
    MOCK.AddPlayer(p)
    if H.frameworkKind == 'qbcore' or H.frameworkKind == 'qbox' then
        H.store[p.id] = qbPlayer(p)
    elseif H.frameworkKind == 'esx' then
        H.store[p.id] = esxPlayer(p)
    end
    return p
end

function H.Balance(src, account)
    local player = H.store[src]
    if not player then return nil end
    if player.PlayerData then return player.PlayerData.money[account] end
    return player._accounts[account == 'cash' and 'money' or 'bank'].money
end

function H.SetBalance(src, account, value)
    local player = H.store[src]
    if player.PlayerData then player.PlayerData.money[account] = value
    else player._accounts[account == 'cash' and 'money' or 'bank'].money = value end
end

-- Boot -------------------------------------------------------------------------------
-- options.framework : 'qbcore' | 'esx' | 'qbox' | 'standalone'
-- options.config(Config)       : tweak config before the catalog is built
-- options.serverConfig(ServerConfig)
-- options.resources            : extra resource states
function H.BootServer(options)
    options = options or {}
    MOCK.Reset(true)
    MOCK.convars.onesync = options.onesync or 'on'
    for name, state in pairs(options.resources or {}) do MOCK.resources[name] = state end
    if options.framework and options.framework ~= 'standalone' then H.InstallFramework(options.framework)
    else H.frameworkKind = 'standalone'; H.store = {} end
    for name, state in pairs(options.overrideResources or {}) do MOCK.resources[name] = state end
    if options.beforeLoad then options.beforeLoad() end

    local manifest = H.ReadManifest()
    local files = {}
    for _, f in ipairs(manifest.shared) do files[#files + 1] = f end
    for _, f in ipairs(manifest.server) do files[#files + 1] = f end
    for _, file in ipairs(files) do
        dofile(RESOURCE_ROOT .. '/' .. file)
        if file == 'config.lua' then
            Config.Debug = false
            if options.config then options.config(Config) end
        elseif file == 'config_server.lua' then
            ServerConfig.Logging.console = false
            if options.serverConfig then options.serverConfig(ServerConfig) end
        end
    end
    MOCK.Advance(0)
    return manifest
end

function H.BootClient(options)
    options = options or {}
    MOCK.Reset(false)
    for name, state in pairs(options.resources or {}) do MOCK.resources[name] = state end
    if options.beforeLoad then options.beforeLoad() end
    local manifest = H.ReadManifest()
    local files = {}
    for _, f in ipairs(manifest.shared) do files[#files + 1] = f end
    for _, f in ipairs(manifest.client) do files[#files + 1] = f end
    for _, file in ipairs(files) do
        dofile(RESOURCE_ROOT .. '/' .. file)
        if file == 'config.lua' and options.config then options.config(Config) end
    end
    return manifest
end

-- Positions --------------------------------------------------------------------------
function H.AtHostess(src)
    local c = Config.Hostess.coords
    MOCK.Move(src, vec3(c.x + 0.5, c.y, c.z))
end

function H.AtTable(src, tableId)
    for _, def in ipairs(Config.Tables) do
        if def.id == tableId then
            MOCK.Move(src, vec3(def.center.x + 0.3, def.center.y, def.center.z))
            return
        end
    end
    error('unknown table ' .. tostring(tableId))
end

function H.Far(src)
    local c = Config.Venue.center
    MOCK.Move(src, vec3(c.x + 500, c.y + 500, c.z))
end

-- Seats a player at a fresh table: hostess → walk → sit. Returns the table id.
function H.Seat(src, partySize)
    H.AtHostess(src)
    local r = MOCK.Call(src, 'requestTable', { partySize = partySize or 2 })
    assert(r and r.ok, 'requestTable failed: ' .. tostring(r and r.code))
    local tableId = r.data.tableId
    H.AtTable(src, tableId)
    local s = MOCK.Call(src, 'sit', { tableId = tableId })
    assert(s and s.ok, 'sit failed: ' .. tostring(s and s.code))
    return tableId
end

local requestCounter = 0
function H.Order(src, lines, extra)
    requestCounter = requestCounter + 1
    local payload = { lines = lines, requestId = ('req-%06d-%d'):format(requestCounter, src) }
    for k, v in pairs(extra or {}) do payload[k] = v end
    MOCK.Advance(6000) -- stay clear of the order cooldown
    return MOCK.Call(src, 'placeOrder', payload)
end

-- Runs the server loops until an order reaches `status` (or the time runs out).
function H.RunUntil(predicate, maxMs)
    local waited = 0
    while waited < (maxMs or 300000) do
        if predicate() then return true end
        MOCK.Advance(1000)
        waited = waited + 1000
    end
    return predicate()
end

-- Assertions -------------------------------------------------------------------------
local current = '?'

-- Fails the test when the server logged an internal error (tick loops and
-- callbacks run inside pcall, so such errors would otherwise stay hidden).
local function assertNoInternalErrors()
    local logger = rawget(_G, 'Logger')
    if type(logger) ~= 'table' or not logger.Recent then return end
    for _, entry in ipairs(logger.Recent(500)) do
        if entry.level == 'error' and not entry.message:find('boom', 1, true) then
            error('server logged an internal error: ' .. entry.message, 0)
        end
    end
end

function H.Test(name, fn)
    current = name
    local ok, err = xpcall(function()
        fn()
        assertNoInternalErrors()
    end, debug.traceback)
    if ok then
        H.results.passed = H.results.passed + 1
        MOCK.realPrint(('  \27[32m✔\27[0m %s'):format(name))
    else
        H.results.failed = H.results.failed + 1
        H.results.failures[#H.results.failures + 1] = { name = name, err = err }
        MOCK.realPrint(('  \27[31m✘ %s\27[0m\n      %s'):format(name, tostring(err):gsub('\n', '\n      ')))
    end
end

function H.Eq(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message or 'value', tostring(expected), tostring(actual)), 2)
    end
end

function H.True(value, message)
    if not value then error((message or 'expected true') .. ' (in ' .. current .. ')', 2) end
end

function H.Ok(result, message)
    if not (result and result.ok) then
        error(('%s: expected ok, got code=%s'):format(message or 'call', tostring(result and result.code)), 2)
    end
    return result
end

function H.Fails(result, code, message)
    if not result then error((message or 'call') .. ': no response', 2) end
    if result.ok then error(('%s: expected failure "%s" but the call succeeded'):format(message or 'call', code), 2) end
    if code and result.code ~= code then
        error(('%s: expected code "%s", got "%s"'):format(message or 'call', code, tostring(result.code)), 2)
    end
    return result
end

function H.LogContains(text)
    for _, entry in ipairs(Logger.Recent(500)) do
        if entry.message:find(text, 1, true) then return true end
    end
    return false
end

function H.Section(title)
    MOCK.realPrint('\n\27[1m' .. title .. '\27[0m')
end

return H
