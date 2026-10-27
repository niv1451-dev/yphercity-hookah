-- Hostess and waiter NPCs. They are local (non-networked) peds created once when
-- the player comes near the lounge and deleted when they leave — never per frame.
-- Every client sees the same NPCs at the same posts. The waiter "serving walk" is
-- a local visual effect played on each nearby client; the actual order flow is
-- handled by the server and does not depend on the NPC reaching the table.

Peds = {
    hostess = nil,
    waiters = {},
}

local FALLBACK_MODELS = { 'a_f_y_business_01', 's_m_y_waiter_01', 'a_m_y_business_01' }
local queues = {}   -- [waiterIndex] = { tableIds }
local walking = {}  -- [waiterIndex] = true

local function loadPedModel(model)
    local hash = ClientUtil.LoadModel(model)
    if hash then return hash end
    for _, fallback in ipairs(FALLBACK_MODELS) do
        hash = ClientUtil.LoadModel(fallback)
        if hash then return hash end
    end
    return nil
end

local function startIdle(ped, scenario)
    if scenario then
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    end
end

local function spawnPed(def)
    local hash = loadPedModel(def.model)
    if not hash then return nil end
    local c = def.coords
    local z = ClientUtil.FloorZ(c)
    local ped = CreatePed(4, hash, c.x, c.y, z, c.w, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end
    SetEntityHeading(ped, c.w)
    SetEntityInvincible(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    FreezeEntityPosition(ped, true)
    startIdle(ped, def.scenario)
    return { ped = ped, home = vec4(c.x, c.y, z, c.w), scenario = def.scenario, def = def }
end

function Peds.SpawnAll()
    if not Peds.hostess and Config.Hostess then
        Peds.hostess = spawnPed(Config.Hostess)
    end
    for index, def in ipairs(Config.Waiters or {}) do
        if not Peds.waiters[index] then
            Peds.waiters[index] = spawnPed(def)
        end
    end
end

local function deletePed(entry)
    if entry and entry.ped and DoesEntityExist(entry.ped) then
        DeleteEntity(entry.ped)
    end
end

function Peds.DespawnAll()
    deletePed(Peds.hostess)
    Peds.hostess = nil
    for index, entry in pairs(Peds.waiters) do
        deletePed(entry)
        Peds.waiters[index] = nil
    end
    queues, walking = {}, {}
end

function Peds.WaiterForTable(tableId)
    local def = Client.TableDef(tableId)
    if def and def.waiter and Peds.waiters[def.waiter] then return def.waiter end
    for index, waiter in ipairs(Config.Waiters or {}) do
        for _, id in ipairs(waiter.tables or {}) do
            if id == tableId then return index end
        end
    end
    return (Config.Waiters and #Config.Waiters > 0) and 1 or nil
end

function Peds.HostessGesture()
    local entry = Peds.hostess
    local gesture = Config.Hostess.gesture
    if not entry or not gesture or not DoesEntityExist(entry.ped) then return end
    CreateThread(function()
        ClearPedTasks(entry.ped)
        if ClientUtil.PlayAnim(entry.ped, gesture.dict, gesture.clip, gesture.duration or 1800, 48) then
            Wait(gesture.duration or 1800)
        end
        if DoesEntityExist(entry.ped) then startIdle(entry.ped, entry.scenario) end
    end)
end

local function walkTo(ped, x, y, z, heading, timeout)
    TaskGoStraightToCoord(ped, x, y, z, Config.WaiterBehaviour.walkSpeed or 1.0, timeout, heading, 0.3)
    local deadline = GetGameTimer() + timeout
    while GetGameTimer() < deadline do
        if not DoesEntityExist(ped) then return false end
        local pos = GetEntityCoords(ped)
        if Utils.Dist2D(pos, vec3(x, y, z)) < 0.7 then return true end
        Wait(250)
    end
    return false
end

local function serveOnce(index, tableId)
    local entry = Peds.waiters[index]
    local def = Client.TableDef(tableId)
    if not entry or not def or not DoesEntityExist(entry.ped) then return end
    local ped, home = entry.ped, entry.home
    local behaviour = Config.WaiterBehaviour

    -- stop 1.3 m from the table centre, on the side facing the waiter's post
    local dx, dy = home.x - def.center.x, home.y - def.center.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then length = 1.0 end
    local tx = def.center.x + dx / length * 1.3
    local ty = def.center.y + dy / length * 1.3
    local faceHeading = (math.deg(math.atan(-(def.center.x - tx), def.center.y - ty)) + 360.0) % 360.0

    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    local arrived = walkTo(ped, tx, ty, home.z, faceHeading, behaviour.walkTimeout or 20000)
    if arrived and DoesEntityExist(ped) then
        TaskTurnPedToFaceCoord(ped, def.center.x, def.center.y, def.center.z, 1000)
        Wait(1000)
        local anim = behaviour.serveAnim
        if anim and ClientUtil.PlayAnim(ped, anim.dict, anim.clip, anim.duration or 1500, 0) then
            Wait(anim.duration or 1500)
        end
    end
    if DoesEntityExist(ped) then
        walkTo(ped, home.x, home.y, home.z, home.w, behaviour.walkTimeout or 20000)
    end
    if DoesEntityExist(ped) then
        ClearPedTasks(ped)
        SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, false)
        SetEntityHeading(ped, home.w)
        FreezeEntityPosition(ped, true)
        startIdle(ped, entry.scenario)
    end
end

function Peds.Serve(tableId)
    if not Config.WaiterBehaviour.walkToTable then return end
    local index = Peds.WaiterForTable(tableId)
    if not index or not Peds.waiters[index] then return end
    queues[index] = queues[index] or {}
    local queue = queues[index]
    if #queue >= 4 then return end
    queue[#queue + 1] = tableId
    if walking[index] then return end
    walking[index] = true
    CreateThread(function()
        while queues[index] and #queues[index] > 0 do
            local nextTable = table.remove(queues[index], 1)
            serveOnce(index, nextTable)
        end
        walking[index] = nil
    end)
end

function Peds.Get(kind, index)
    if kind == 'hostess' then return Peds.hostess end
    return Peds.waiters[index]
end
