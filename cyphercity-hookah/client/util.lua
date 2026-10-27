-- Client helpers: safe asset loading (every model / animation / particle is
-- checked before use, so a wrong name in config.lua only prints a warning)
-- and ground height handling.

ClientUtil = {}

local warned = {}

function ClientUtil.WarnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print(('^3[cyphercity-hookah]^7 %s'):format(message))
end

function ClientUtil.LoadModel(model)
    if not model then return nil end
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        ClientUtil.WarnOnce('model:' .. tostring(model), ('Model "%s" does not exist in this game build — skipped'):format(tostring(model)))
        return nil
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            ClientUtil.WarnOnce('modeltimeout:' .. tostring(model), ('Model "%s" did not load in time'):format(tostring(model)))
            return nil
        end
        Wait(10)
    end
    return hash
end

function ClientUtil.LoadAnimDict(dict)
    if type(dict) ~= 'string' then return false end
    if not DoesAnimDictExist(dict) then
        ClientUtil.WarnOnce('anim:' .. dict, ('Animation dictionary "%s" does not exist — animation skipped'):format(dict))
        return false
    end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(10)
    end
    return true
end

function ClientUtil.LoadPtfx(asset)
    if type(asset) ~= 'string' then return false end
    RequestNamedPtfxAsset(asset)
    local deadline = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(asset) do
        if GetGameTimer() > deadline then
            ClientUtil.WarnOnce('ptfx:' .. asset, ('Particle asset "%s" did not load — effect skipped'):format(asset))
            return false
        end
        Wait(10)
    end
    return true
end

-- Floor height under a configured point. Config coordinates are "standing"
-- coordinates (as printed by /hookahcoords), which sit ~1 m above the floor.
function ClientUtil.FloorZ(coords)
    if Config.Venue.snapToGround then
        local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
        if found then return z end
    end
    return coords.z - 1.0
end

function ClientUtil.PlayAnim(ped, dict, clip, duration, flag)
    if not ClientUtil.LoadAnimDict(dict) then return false end
    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, duration or -1, flag or 49, 0.0, false, false, false)
    return true
end
