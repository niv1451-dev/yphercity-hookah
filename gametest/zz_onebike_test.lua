-- TEMPORARY in-game photo test for the One Bike (home server). Remove this file and its manifest line after.
-- Puts the bike on the airport apron at noon, shoots it from fixed cameras (the PowerShell runner takes a
-- screenshot on every "EATTEST SHOT" line), then seats the player on it and hands control back.
local SPOT = vector4(-1145.0, -2865.0, 13.95, 240.0)
local COMPARE_MODEL = 'powersurge'   -- GTA's own electric motorbike, measured the same way for comparison
local hideHud = false

-- Prints where the game really put the bones and wheels ("EATTEST INFO" lines end up in the runner's output).
local BONES = { 'chassis', 'swingarm', 'wheel_lr', 'forks_u', 'forks_l', 'wheel_lf', 'handlebars', 'seat_f' }
local function f3(v) return ('%.3f,%.3f,%.3f'):format(v.x, v.y, v.z) end
local function measure(tag, veh)
    local c = GetEntityCoords(veh)
    print(('EATTEST INFO %s z=%.3f above=%.3f allWheels=%s wheels=%d speed=%.2f'):format(tag, c.z,
        GetEntityHeightAboveGround(veh), tostring(IsVehicleOnAllWheels(veh)), GetVehicleNumberOfWheels(veh), GetEntitySpeed(veh)))
    for _, name in ipairs(BONES) do
        local idx = GetEntityBoneIndexByName(veh, name)
        if idx ~= -1 then
            local w = GetWorldPositionOfEntityBone(veh, idx)
            local l = GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z)
            local ok, o = pcall(Citizen.InvokeNative, 0xCE6294A232D03786, veh, idx, Citizen.ResultAsVector())
            print(('EATTEST INFO %s bone %s idx=%d local=%s obj=%s'):format(tag, name, idx, f3(l), ok and o and f3(o) or '-'))
        end
    end
    for i = 0, GetVehicleNumberOfWheels(veh) - 1 do
        local function g(fn) local ok, v = pcall(fn, veh, i); return (ok and v) and ('%.3f'):format(v) or '-' end
        print(('EATTEST INFO %s wheel %d xoff=%s tyreR=%s rimR=%s width=%s susp=%s'):format(tag, i,
            g(GetVehicleWheelXOffset), g(GetVehicleWheelTireColliderSize), g(GetVehicleWheelRimColliderSize),
            g(GetVehicleWheelTireColliderWidth), g(GetVehicleWheelSuspensionCompression)))
    end
end

local function compare_vehicle(near)
    local hash = joaat(COMPARE_MODEL)
    RequestModel(hash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t0 < 10000 do Wait(0) end
    if not HasModelLoaded(hash) then print('EATTEST INFO compare model not loaded') return end
    -- 10 מטר לצד ימין של האופניים שלנו: מאחורי המצלמה בצילום מהצד, כדי שלא יפריע לתמונות שלנו
    local p = GetOffsetFromEntityInWorldCoords(near, 10.0, 0.0, 0.0)
    local v = CreateVehicle(hash, p.x, p.y, p.z + 0.7, SPOT.w, false, false)
    SetVehicleOnGroundProperly(v)
    SetVehicleDirtLevel(v, 0.0)
    Wait(3000)
    measure(COMPARE_MODEL, v)
    SetModelAsNoLongerNeeded(hash)
    return v
end

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
    ped = PlayerPedId()   -- המשחק מחליף את השחקן בסיום הכניסה; תמיד לקחת את הנוכחי
    NetworkOverrideClockTime(13, 0, 0)
    SetWeatherTypeNowPersist('EXTRASUNNY')
    SetOverrideWeather('EXTRASUNNY')
    SetEntityCoords(ped, SPOT.x + 4.0, SPOT.y, SPOT.z, false, false, false, false)
    -- wait for the ground there: without its collision the vehicles just hang where they were created
    local found, gz = false, 0.0
    local tg = GetGameTimer()
    while GetGameTimer() - tg < 15000 do
        RequestCollisionAtCoord(SPOT.x, SPOT.y, SPOT.z)
        -- מחפשים את הקרקע מגובה 100 מטר כלפי מטה
        found, gz = GetGroundZFor_3dCoord(SPOT.x, SPOT.y, 100.0, false)
        if found and HasCollisionLoadedAroundEntity(ped) then break end
        Wait(250)
    end
    Wait(1000)
    -- גיבוי: גובה הקרקע לפי השחקן שעומד עליה (מרכז השחקן כמטר מעל הקרקע). רק אם הגובה הגיוני
    ped = PlayerPedId()
    local pc = GetEntityCoords(ped)
    print(('EATTEST INFO ped z=%.3f groundSearch found=%s gz=%.3f'):format(pc.z, tostring(found), gz or -1))
    if not found then
        local ok2, gz2 = GetGroundZFor_3dCoord(pc.x, pc.y, pc.z + 1.0, false)
        if ok2 then found, gz = true, gz2
        elseif pc.z > 5.0 then found, gz = true, pc.z - 1.0
        else gz = SPOT.z end
    end
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
    local veh = CreateVehicle(hash, SPOT.x, SPOT.y, (found and gz or SPOT.z) + 0.7, SPOT.w, true, false)
    SetEntityLoadCollisionFlag(veh, true)
    SetVehicleOnGroundProperly(veh)
    ActivatePhysics(veh)
    SetVehicleDirtLevel(veh, 0.0)
    SetModelAsNoLongerNeeded(hash)
    Wait(4000)
    print(('EATTEST INFO seats=%d maxPassengers=%d driverSeatFree=%s'):format(GetVehicleModelNumberOfSeats(hash),
        GetVehicleMaxNumberOfPassengers(veh), tostring(IsVehicleSeatFree(veh, -1))))
    local c = GetEntityCoords(veh)
    print(('EATTEST INFO vehicle=%d pos=%.2f,%.2f,%.2f class=%d'):format(veh, c.x, c.y, c.z, GetVehicleClass(veh)))
    print(('EATTEST INFO ground found=%s gz=%.3f'):format(tostring(found), gz or -1))
    measure('onebike', veh)
    local cmp = compare_vehicle(veh)

    ped = PlayerPedId()

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

    -- אותם צילומים לאופניים המקוריות של המשחק, באותם תנאים, להשוואה
    if cmp and DoesEntityExist(cmp) then
        view(cmp, cam, 'cmp_side', 3.3, 0.0, 0.05, 0.0, 0.0, 0.05, 40.0)
        view(cmp, cam, 'cmp_front34', 2.2, 2.3, 0.55, 0.0, 0.1, 0.05, 45.0)
        view(cmp, cam, 'cmp_wheelf', 1.25, 0.85, -0.15, 0.0, 0.76, -0.23, 40.0)
        DeleteVehicle(cmp)
    end

    -- rider
    ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    local pp = GetOffsetFromEntityInWorldCoords(veh, 1.0, 0.0, 0.0)
    SetEntityCoords(ped, pp.x, pp.y, pp.z, false, false, false, false)
    Wait(500)
    SetPedIntoVehicle(ped, veh, -1)
    Wait(1500)
    if not IsPedInVehicle(ped, veh, false) then
        -- דרך נוספת להושיב: הושבה ישירה בכיסא הנהג
        TaskWarpPedIntoVehicle(ped, veh, -1)
        Wait(1500)
    end
    print(('EATTEST INFO rider in bike=%s'):format(tostring(IsPedInVehicle(ped, veh, false))))
    measure('onebike_ridden', veh)
    view(veh, cam, 'rider', 2.7, -0.8, 0.55, 0.0, 0.0, 0.45, 50.0)
    view(veh, cam, 'rider_front34', 2.2, 2.4, 0.7, 0.0, 0.1, 0.4, 48.0)

    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    hideHud = false
    print('EATTEST DONE')
end)
