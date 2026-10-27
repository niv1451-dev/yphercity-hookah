-- Offline mock of the parts of the FiveM Lua runtime this resource uses.
-- It is NOT the real game: it lets the server logic run under plain Lua 5.4 so
-- the order / payment / table / security rules can be tested automatically.

local json = dofile(TEST_ROOT .. '/lua/json.lua')

local M = {}
MOCK = M

local realTime = os.time
local BASE_TIME = 1767225600 -- 2026-01-01 00:00:00 UTC

function M.Reset(isServer)
    M.isServer = isServer
    M.clock = 0
    M.time = BASE_TIME
    M.threads = {}
    M.timers = {}
    M.handlers = {}
    M.netEvents = {}
    M.clientEvents = {}
    M.serverEvents = {}
    M.players = {}
    M.resources = {}
    M.convars = {}
    M.files = {}
    M.http = {}
    M.dropped = {}
    M.commands = {}
    M.prints = {}
    M.exports = {}
    M.nui = {}
    M.nuiCallbacks = {}
    M.focus = nil
    M.nextRequest = 1000
    M.natives = {}
end

-- Vectors -------------------------------------------------------------------------
local vmeta = {}
vmeta.__index = function(v, k)
    if k == 'xyz' then return vec3(rawget(v, 'x'), rawget(v, 'y'), rawget(v, 'z')) end
    return nil
end
vmeta.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)) end
vmeta.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, (a.z or 0) + (b.z or 0)) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + (a.z or 0) * (a.z or 0)) end
vmeta.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w end

function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
function vec4(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, vmeta) end
vector3, vector4 = vec3, vec4

json_lib = json
_G.json = json

-- Time ----------------------------------------------------------------------------
os.time = function(t)
    if t then return realTime(t) end
    return M.time
end

function GetGameTimer() return M.clock end

-- Threads -------------------------------------------------------------------------
local function resume(thread)
    local ok, wait = coroutine.resume(thread.co)
    if not ok then
        error('thread error: ' .. tostring(wait) .. '\n' .. debug.traceback(thread.co))
    end
    if coroutine.status(thread.co) == 'dead' then
        thread.dead = true
    else
        -- Wait(0) in FiveM means "next frame": model a frame as 16 ms
        thread.wake = M.clock + math.max(16, tonumber(wait) or 0)
    end
end

function CreateThread(fn)
    local thread = { co = coroutine.create(fn), wake = M.clock }
    M.threads[#M.threads + 1] = thread
    resume(thread)
    return thread
end

function Wait(ms)
    local _, main = coroutine.running()
    if main then error('Wait() called outside of a thread') end
    coroutine.yield(ms or 0)
end

function SetTimeout(ms, fn)
    M.timers[#M.timers + 1] = { at = M.clock + ms, fn = fn }
end

local promiseMeta = {}
promiseMeta.__index = promiseMeta
function promiseMeta:resolve(value)
    if self.done then return end
    self.done, self.value = true, value
end
promise = { new = function() return setmetatable({ done = false }, promiseMeta) end }

Citizen = {
    CreateThread = CreateThread,
    Wait = Wait,
    SetTimeout = SetTimeout,
    Await = function(p)
        while not p.done do Wait(0) end
        return p.value
    end,
}

-- Runs every thread / timer that is due, advancing the clock by `ms`.
function M.Advance(ms)
    local target = M.clock + (ms or 0)
    repeat
        local nextWake = target
        for _, thread in ipairs(M.threads) do
            if not thread.dead and thread.wake < nextWake then nextWake = thread.wake end
        end
        for _, timer in ipairs(M.timers) do
            if not timer.done and timer.at < nextWake then nextWake = timer.at end
        end
        if nextWake > M.clock then
            M.clock = nextWake
            M.time = BASE_TIME + math.floor(M.clock / 1000)
        end
        local ran = false
        for _, timer in ipairs(M.timers) do
            if not timer.done and timer.at <= M.clock then
                timer.done = true
                ran = true
                timer.fn()
            end
        end
        for i = 1, #M.threads do
            local thread = M.threads[i]
            if thread and not thread.dead and thread.wake <= M.clock then
                ran = true
                resume(thread)
            end
        end
    until M.clock >= target and not ran
    local alive = {}
    for _, thread in ipairs(M.threads) do if not thread.dead then alive[#alive + 1] = thread end end
    M.threads = alive
end

-- Events --------------------------------------------------------------------------
function AddEventHandler(name, fn)
    M.handlers[name] = M.handlers[name] or {}
    table.insert(M.handlers[name], fn)
    return { name = name, fn = fn }
end

function RegisterNetEvent(name, fn)
    M.netEvents[name] = true
    if fn then return AddEventHandler(name, fn) end
end

local function dispatch(name, src, ...)
    local list = M.handlers[name] or {}
    local args = table.pack(...)
    for _, fn in ipairs(list) do
        CreateThread(function()
            source = src
            fn(table.unpack(args, 1, args.n))
        end)
    end
    return #list
end

function TriggerEvent(name, ...)
    return dispatch(name, M.isServer and '' or nil, ...)
end

-- Simulates a client sending a net event to the server.
function M.FromClient(src, name, ...)
    if not M.netEvents[name] then return 0 end
    return dispatch(name, src, ...)
end

-- Simulates the server sending a net event to this client (client tests).
function M.FromServer(name, ...)
    if not M.netEvents[name] then return 0 end
    return dispatch(name, nil, ...)
end

function TriggerClientEvent(name, target, ...)
    M.clientEvents[#M.clientEvents + 1] = { name = name, target = target, args = table.pack(...) }
end

function TriggerServerEvent(name, ...)
    M.serverEvents[#M.serverEvents + 1] = { name = name, args = table.pack(...) }
    if M.onServerEvent then M.onServerEvent(name, ...) end
end

function M.EventsFor(name, target)
    local list = {}
    for _, event in ipairs(M.clientEvents) do
        if event.name == name and (target == nil or event.target == target) then list[#list + 1] = event end
    end
    return list
end

function M.ClearEvents() M.clientEvents = {} end

-- Calls a server callback the way the client bridge does and returns the reply.
function M.Call(src, name, payload)
    M.nextRequest = M.nextRequest + 1
    local id = M.nextRequest
    M.FromClient(src, 'cyphercity-hookah:cb:request', name, id, payload)
    for i = #M.clientEvents, 1, -1 do
        local event = M.clientEvents[i]
        if event.name == 'cyphercity-hookah:cb:response' and event.target == src and event.args[1] == id then
            return event.args[2]
        end
    end
    return nil
end

-- Players / resources -----------------------------------------------------------------
function M.AddPlayer(p)
    p.coords = p.coords or vec3(0, 0, 0)
    p.identifiers = p.identifiers or { license = 'license:' .. string.format('%040d', p.id) }
    p.aces = p.aces or {}
    M.players[p.id] = p
    return p
end

function M.Move(src, coords) M.players[src].coords = coords end

function M.RemovePlayer(src)
    if not M.players[src] then return end
    dispatch('playerDropped', src, 'left')
    M.players[src] = nil
end

function GetPlayers()
    local list = {}
    for id in pairs(M.players) do list[#list + 1] = tostring(id) end
    table.sort(list, function(a, b) return tonumber(a) < tonumber(b) end)
    return list
end

function GetPlayerName(src)
    local p = M.players[tonumber(src) or -1]
    return p and p.name or nil
end

function GetPlayerPed(src)
    if not M.players[tonumber(src) or -1] then return 0 end
    return 100000 + tonumber(src)
end

function GetEntityCoords(ped)
    local p = M.players[ped - 100000]
    return p and p.coords or vec3(0, 0, 0)
end

function GetPlayerIdentifierByType(src, kind)
    local p = M.players[tonumber(src) or -1]
    if not p then return nil end
    for _, id in pairs(p.identifiers) do
        if id:sub(1, #kind + 1) == kind .. ':' then return id end
    end
    return nil
end

function GetPlayerIdentifiers(src)
    local p = M.players[tonumber(src) or -1]
    local list = {}
    if p then for _, id in pairs(p.identifiers) do list[#list + 1] = id end end
    return list
end

function IsPlayerAceAllowed(src, ace)
    local p = M.players[tonumber(src) or -1]
    return p ~= nil and p.aces[ace] == true
end

function DropPlayer(src, reason)
    M.dropped[#M.dropped + 1] = { src = src, reason = reason }
end

function IsDuplicityVersion() return M.isServer end
function GetResourceState(name) return M.resources[name] or 'missing' end
function GetResourceMetadata() return '1.0.0' end
function GetCurrentResourceName() return 'cyphercity-hookah' end
function GetConvar(name, default) return M.convars[name] or default end
function LoadResourceFile(_, path) return M.files[path] end
function SaveResourceFile(_, path, data) M.files[path] = data return true end
function PerformHttpRequest(url, cb, method, data, headers)
    M.http[#M.http + 1] = { url = url, method = method, data = data, headers = headers }
    if cb then cb(204, '', {}) end
end
function RegisterCommand(name, fn) M.commands[name] = fn end
function GetHashKey(s) return #tostring(s) end

local realPrint = print
function print(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    M.prints[#M.prints + 1] = table.concat(parts, ' ')
    if os.getenv('VERBOSE') then realPrint(...) end
end
M.realPrint = realPrint

exports = setmetatable({}, {
    __index = function(_, resource)
        return setmetatable({}, {
            __index = function(_, name)
                local res = M.exports[resource]
                local fn = res and res[name]
                if not fn then
                    return function() error(('No such export %s in resource %s'):format(name, resource)) end
                end
                return fn
            end,
        })
    end,
})

-- Client-only natives used by client scripts (simple recorders) ---------------------
function SendNUIMessage(message) M.nui[#M.nui + 1] = message end
function SetNuiFocus(a, b) M.focus = { a, b } end
function RegisterNUICallback(name, fn) M.nuiCallbacks[name] = fn end

M.Reset(true)
return M
