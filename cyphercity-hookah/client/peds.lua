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

-- Walks a waiter to (x, y) and turns him towards (fx, fy, fz). Returns true when he got there.
local function goTo(entry, x, y, fx, fy, fz)
    local ped, home = entry.ped, entry.home
    local heading = (math.deg(math.atan(-(fx - x), fy - y)) + 360.0) % 360.0
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    local arrived = walkTo(ped, x, y, home.z, heading, Config.WaiterBehaviour.walkTimeout or 20000)
    if arrived and DoesEntityExist(ped) then
        TaskTurnPedToFaceCoord(ped, fx, fy, fz, 1000)
        Wait(1000)
    end
    return arrived
end

-- Back to the post, frozen in place with the idle scenario.
local function goHome(entry)
    local ped, home = entry.ped, entry.home
    if DoesEntityExist(ped) then
        ClearPedTasks(ped)
        walkTo(ped, home.x, home.y, home.z, home.w, Config.WaiterBehaviour.walkTimeout or 20000)
    end
    if DoesEntityExist(ped) then
        ClearPedTasks(ped)
        SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, false)
        SetEntityHeading(ped, home.w)
        FreezeEntityPosition(ped, true)
        startIdle(ped, entry.scenario)
    end
end

-- Serving: stop 1.3 m from the table centre, on the side facing the waiter's post.
local function serveOnce(entry, def)
    local home = entry.home
    local dx, dy = home.x - def.center.x, home.y - def.center.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then length = 1.0 end
    local tx = def.center.x + dx / length * 1.3
    local ty = def.center.y + dy / length * 1.3
    if goTo(entry, tx, ty, def.center.x, def.center.y, def.center.z) then
        local anim = Config.WaiterBehaviour.serveAnim
        if anim and ClientUtil.PlayAnim(entry.ped, anim.dict, anim.clip, anim.duration or 1500, 0) then
            Wait(anim.duration or 1500)
        end
    end
    goHome(entry)
end

-- Where the waiter stands to take an order: next to the guest who called him
-- (a little outside their seat and to its side), facing the guest.
local function standPoint(def, seatIndex, home)
    local seat = seatIndex and def.seats and def.seats[seatIndex]
    if seat then
        local ox, oy = seat.x - def.center.x, seat.y - def.center.y
        local length = math.sqrt(ox * ox + oy * oy)
        if length < 0.01 then ox, oy, length = 0.0, 1.0, 1.0 end
        ox, oy = ox / length, oy / length
        return seat.x + ox * 0.45 - oy * 0.55, seat.y + oy * 0.45 + ox * 0.55, seat.x, seat.y
    end
    local dx, dy = home.x - def.center.x, home.y - def.center.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then length = 1.0 end
    return def.center.x + dx / length * 1.3, def.center.y + dy / length * 1.3, def.center.x, def.center.y
end

local endedVisits = {} -- [visitId] = true once the server ended the visit

-- Taking an order: walk to the guests, "write" on the notepad while they pick
-- in the menu, and go back once the visit ends (or after waiting long enough).
local function takeOrderOnce(entry, def, job)
    local x, y, fx, fy = standPoint(def, job.seat, entry.home)
    goTo(entry, x, y, fx, fy, def.center.z) -- if blocked, he takes the order where he stopped
    if endedVisits[job.id] then
        goHome(entry)
        return
    end
    if job.onArrive then job.onArrive() end
    local scenario = (Config.WaiterBehaviour.takeOrder or {}).scenario
    if scenario and DoesEntityExist(entry.ped) then TaskStartScenarioInPlace(entry.ped, scenario, 0, true) end
    local deadline = GetGameTimer() + (job.wait or 60) * 1000
    while not endedVisits[job.id] and GetGameTimer() < deadline and DoesEntityExist(entry.ped) do
        Wait(250)
    end
    goHome(entry)
end

local function runJob(index, job)
    local entry = Peds.waiters[index]
    local def = Client.TableDef(job.tableId)
    if not entry or not def or not DoesEntityExist(entry.ped) then
        if job.kind == 'take' and job.onArrive and not endedVisits[job.id] then job.onArrive() end
        return
    end
    if job.kind == 'take' then
        if not endedVisits[job.id] then takeOrderOnce(entry, def, job) end
    else
        serveOnce(entry, def)
    end
end

local function enqueue(index, job, first)
    queues[index] = queues[index] or {}
    local queue = queues[index]
    if #queue >= 4 then return false end
    if first then table.insert(queue, 1, job) else queue[#queue + 1] = job end
    if walking[index] then return true end
    walking[index] = true
    CreateThread(function()
        while queues[index] and #queues[index] > 0 do
            runJob(index, table.remove(queues[index], 1))
        end
        walking[index] = nil
    end)
    return true
end

function Peds.Serve(tableId)
    if not Config.WaiterBehaviour.walkToTable then return end
    local index = Peds.WaiterForTable(tableId)
    if not index or not Peds.waiters[index] then return end
    enqueue(index, { kind = 'serve', tableId = tableId })
end

-- A guest called the waiter. onArrive runs when he stands at the table (or
-- right away when there is no waiter to walk, so the guests can always order).
function Peds.TakeOrder(tableId, visit, onArrive)
    local index = Peds.WaiterForTable(tableId)
    local job = { kind = 'take', tableId = tableId, id = visit.id, seat = visit.seat, wait = visit.wait, onArrive = onArrive }
    -- guests waiting to order go before plates waiting to be carried
    if not Config.WaiterBehaviour.walkToTable or not index or not Peds.waiters[index] or not enqueue(index, job, true) then
        if onArrive then onArrive() end
    end
end

function Peds.EndVisit(visitId)
    if visitId then endedVisits[visitId] = true end
end

function Peds.Get(kind, index)
    if kind == 'hostess' then return Peds.hostess end
    return Peds.waiters[index]
end
