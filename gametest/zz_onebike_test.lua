-- TEMPORARY in-game photo test for the One Bike (home server). Remove this file and its manifest line after.
-- Puts the bike on the airport apron at noon, shoots it from fixed cameras (the PowerShell runner takes a
-- screenshot on every "EATTEST SHOT" line), then seats the player on it and hands control back.
local SPOT = vector4(-1145.0, -2865.0, 13.95, 240.0)
local hideHud = false

local function view(veh, cam, name, ox, oy, oz, lx, ly, lz, fov)
    local p = GetOffsetFromEntityInWorldCoords(veh, ox, oy, oz)
    local t = GetOffsetFromEntityInWorldCoords(veh, lx, ly, lz)
    SetCamCoord(cam, p.x, p.y, p.z)
    PointCamAtCoord(cam, t.x, t.y, t.z)
    SetCamFov(cam, fov)
    Wait(2000)
    print(('EATTEST SHOT %s 1'):format(name))
    Wait(1200)
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    local ped = PlayerPedId()
    while ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) or IsPlayerSwitchInProgress() do
        Wait(500)
        ped = PlayerPedId()
    end
    Wait(4000)
    print('EATTEST READY')
    NetworkOverrideClockTime(13, 0, 0)
    SetWeatherTypeNowPersist('EXTRASUNNY')
    SetOverrideWeather('EXTRASUNNY')
    SetEntityCoords(ped, SPOT.x + 4.0, SPOT.y, SPOT.z, false, false, false, false)
    RequestCollisionAtCoord(SPOT.x, SPOT.y, SPOT.z)
    Wait(3000)
    ClearAreaOfVehicles(SPOT.x, SPOT.y, SPOT.z, 80.0, false, false, false, false, false)

    local hash = joaat('onebike')
    RequestModel(hash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t0 < 10000 do Wait(0) end
    if not HasModelLoaded(hash) then
        print('EATTEST FAIL model not loaded')
        print('EATTEST DONE')
        return
    end
    local found, gz = GetGroundZFor_3dCoord(SPOT.x, SPOT.y, SPOT.z + 5.0, false)
    local veh = CreateVehicle(hash, SPOT.x, SPOT.y, (found and gz or SPOT.z) + 0.7, SPOT.w, true, false)
    SetVehicleOnGroundProperly(veh)
    SetVehicleDirtLevel(veh, 0.0)
    SetModelAsNoLongerNeeded(hash)
    Wait(3000)
    local c = GetEntityCoords(veh)
    print(('EATTEST INFO vehicle=%d pos=%.2f,%.2f,%.2f class=%d'):format(veh, c.x, c.y, c.z, GetVehicleClass(veh)))

    -- clean shots: player out of sight, HUD hidden
    SetEntityCoords(ped, SPOT.x + 20.0, SPOT.y + 20.0, SPOT.z, false, false, false, false)
    SetEntityVisible(ped, false, false)
    hideHud = true
    CreateThread(function() while hideHud do HideHudAndRadarThisFrame() Wait(0) end end)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    RenderScriptCams(true, false, 0, true, true)
    -- offsets: x right, y forward, z up from the bike's origin (0.6 m above the road in the model)
    view(veh, cam, 'photo', 1.93, -0.28, 0.43, 0.0, 0.02, 0.04, 46.0)
    view(veh, cam, 'side', 3.3, 0.0, 0.05, 0.0, 0.0, 0.05, 40.0)
    view(veh, cam, 'front34', 2.2, 2.3, 0.55, 0.0, 0.1, 0.05, 45.0)
    view(veh, cam, 'rear34', -2.1, -2.3, 0.55, 0.0, -0.1, 0.0, 45.0)
    view(veh, cam, 'wheelf', 1.25, 0.75, -0.15, 0.0, 0.65, -0.27, 40.0)
    view(veh, cam, 'wheelr', 1.25, -0.75, -0.15, 0.0, -0.65, -0.27, 40.0)
    view(veh, cam, 'cockpit', 0.9, -0.35, 0.95, 0.0, 0.35, 0.6, 45.0)

    -- rider
    SetEntityVisible(ped, true, false)
    SetPedIntoVehicle(ped, veh, -1)
    Wait(3000)
    view(veh, cam, 'rider', 2.7, -0.8, 0.55, 0.0, 0.0, 0.45, 50.0)
    view(veh, cam, 'rider_front34', 2.2, 2.4, 0.7, 0.0, 0.1, 0.4, 48.0)

    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    hideHud = false
    print('EATTEST DONE')
end)
