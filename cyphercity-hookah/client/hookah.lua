-- Hookah world objects and smoking. The server owns the sessions; each nearby
-- client spawns a local prop at the session's spot and plays the animation only
-- after the server granted the hose (so two players can never use it at once).

HookahClient = {
    props = {},     -- [sessionId] = { entity, target, session }
    smoking = false,
}

local function sessionById(id)
    for _, session in ipairs(State.hookahs or {}) do
        if session.id == id then return session end
    end
    return nil
end

local function atMyTable(session)
    return State.me and State.me.tableId == session.tableId
end

local function seatedOk()
    return not Config.Hookah.requireSeated or (Seat.current ~= nil)
end

local function useHookah(sessionId)
    local result = UI.Decorate(Callback.Await('hookahAction', { action = 'use', sessionId = sessionId }))
    if not result.ok then Notify.Send(result.message, 'error') end
end

local function simpleAction(action, sessionId)
    local result = UI.Decorate(Callback.Await('hookahAction', { action = action, sessionId = sessionId }))
    Notify.Send(result.message or L(result.ok and 'hookah_ended' or 'internal_error'), result.ok and 'success' or 'error')
end

local function buildOptions(sessionId)
    return {
        {
            name = 'cch_hookah_smoke_' .. sessionId,
            label = L('target_smoke'),
            icon = 'fa-solid fa-smoking',
            distance = 2.0,
            canInteract = function()
                local session = sessionById(sessionId)
                if not session or not atMyTable(session) or not seatedOk() or HookahClient.smoking then return false end
                return session.activeUser == nil or session.activeUser == GetPlayerServerId(PlayerId())
            end,
            onSelect = function() useHookah(sessionId) end,
        },
        {
            name = 'cch_hookah_flavor_' .. sessionId,
            label = L('target_change_flavor'),
            icon = 'fa-solid fa-lemon',
            distance = 2.0,
            canInteract = function()
                local session = sessionById(sessionId)
                return session ~= nil and atMyTable(session) and Config.Hookah.flavorChange.enabled
            end,
            onSelect = function() UI.Open('hookah', { sessionId = sessionId, mode = 'flavor' }) end,
        },
        {
            name = 'cch_hookah_coals_' .. sessionId,
            label = L('target_coals'),
            icon = 'fa-solid fa-fire',
            distance = 2.0,
            canInteract = function()
                local session = sessionById(sessionId)
                return session ~= nil and atMyTable(session) and Config.Hookah.coalRefresh.enabled
            end,
            onSelect = function() UI.Open('hookah', { sessionId = sessionId, mode = 'coals' }) end,
        },
        {
            name = 'cch_hookah_end_' .. sessionId,
            label = L('target_end_hookah'),
            icon = 'fa-solid fa-xmark',
            distance = 2.0,
            canInteract = function()
                local session = sessionById(sessionId)
                return session ~= nil and atMyTable(session) and (State.me.isOwner or session.owner == GetPlayerServerId(PlayerId()))
            end,
            onSelect = function() simpleAction('end', sessionId) end,
        },
    }
end

local function spawnProp(session)
    local def = Client.TableDef(session.tableId)
    local spot = def and def.hookahSpots and def.hookahSpots[session.spot]
    if not spot then return nil end
    local hash = ClientUtil.LoadModel(session.prop) or ClientUtil.LoadModel(Config.Hookah.defaultProp)
    if not hash then return nil end
    local object = CreateObject(hash, spot.x, spot.y, ClientUtil.FloorZ(spot), false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not object or object == 0 then return nil end
    SetEntityHeading(object, spot.w or 0.0)
    if Config.Venue.snapToGround then PlaceObjectOnGroundProperly(object) end
    FreezeEntityPosition(object, true)
    SetEntityCollision(object, false, false)
    return object
end

local function removeProp(id)
    local entry = HookahClient.props[id]
    if not entry then return end
    Target.Remove(entry.target)
    if entry.entity and DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    HookahClient.props[id] = nil
end

function HookahClient.Sync(list)
    if not State.inVenue then return end
    local alive = {}
    for _, session in ipairs(list or {}) do
        alive[session.id] = true
        if not HookahClient.props[session.id] then
            local entity = spawnProp(session)
            if entity then
                HookahClient.props[session.id] = {
                    entity = entity,
                    target = Target.AddEntity(entity, buildOptions(session.id)),
                }
            end
        end
    end
    for id in pairs(HookahClient.props) do
        if not alive[id] then removeProp(id) end
    end
end

function HookahClient.Enter()
    HookahClient.Sync(State.hookahs)
end

function HookahClient.Leave()
    for id in pairs(HookahClient.props) do removeProp(id) end
end

-- The server granted this player the hose for `duration` ms.
RegisterNetEvent('cyphercity-hookah:client:hookahSmoke', function(sessionId, duration)
    if HookahClient.smoking then return end
    HookahClient.smoking = true
    local ped = PlayerPedId()
    local anim = Config.Hookah.animation
    local played = anim and ClientUtil.PlayAnim(ped, anim.dict, anim.clip, duration, anim.flag or 49)
    Wait(duration or 7000)
    if played then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
    HookahClient.smoking = false
    if Seat.current and not IsPedUsingScenario(ped, 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER') then Seat.Resume() end
    Callback.Await('hookahAction', { action = 'release', sessionId = sessionId })
end)

-- Exhale smoke on whoever just used a hookah (visible to everyone nearby).
RegisterNetEvent('cyphercity-hookah:client:hookahPuff', function(serverId)
    local fx = Config.Hookah.particle
    if not State.inVenue or not fx or not fx.enabled then return end
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 then return end
    CreateThread(function()
        Wait(fx.delay or 3000)
        if not DoesEntityExist(ped) or not ClientUtil.LoadPtfx(fx.asset) then return end
        local offset = fx.offset or vec3(0.0, 0.0, 0.0)
        UseParticleFxAsset(fx.asset)
        StartParticleFxNonLoopedOnPedBone(fx.name, ped, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, fx.bone or 31086, fx.scale or 1.0, false, false, false)
    end)
end)
