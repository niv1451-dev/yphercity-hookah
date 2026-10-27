-- Setup helpers.
--   /hookahcoords  → prints your position as vec4(...) / vec3(...) in the F8
--                    console and copies it to the clipboard, ready for config.lua.
-- Debug drawing (Config.Debug = true) shows every seat, hookah spot and NPC post.

local function format(n) return ('%.2f'):format(n) end

RegisterCommand(Config.DevCommands.coords or 'hookahcoords', function()
    local result = Callback.Await('devAllowed', {})
    if not (result.ok and result.data and result.data.allowed) then
        Notify.Send(L('dev_not_allowed'), 'error')
        return
    end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local v4 = ('vec4(%s, %s, %s, %s)'):format(format(c.x), format(c.y), format(c.z), format(heading))
    local v3 = ('vec3(%s, %s, %s)'):format(format(c.x), format(c.y), format(c.z))
    print('^2[cyphercity-hookah]^7 ' .. v4)
    print('^2[cyphercity-hookah]^7 ' .. v3)
    UI.Send('clipboard', { text = v4 })
    Notify.Send(L('dev_coords_copied'), 'success')
end, false)

if Config.Debug then
    -- marker positions are resolved every few seconds; drawing happens every frame
    local markers, resolvedAt = {}, 0
    local function resolve()
        markers = {}
        local radius = (Config.TableSettings.interactRadius or 1.8) * 2
        for _, def in ipairs(Config.Tables or {}) do
            markers[#markers + 1] = { 1, def.center.x, def.center.y, ClientUtil.FloorZ(def.center), radius, 0.15, 212, 175, 95, 60 }
            for _, seat in ipairs(def.seats or {}) do
                markers[#markers + 1] = { 28, seat.x, seat.y, ClientUtil.FloorZ(seat) + (Config.Furniture.seatZOffset or 0.5), 0.15, 0.15, 90, 200, 120, 160 }
            end
            for _, spot in ipairs(def.hookahSpots or {}) do
                markers[#markers + 1] = { 28, spot.x, spot.y, ClientUtil.FloorZ(spot) + 0.1, 0.15, 0.15, 200, 120, 220, 160 }
            end
        end
        resolvedAt = GetGameTimer()
    end

    CreateThread(function()
        while true do
            if State.inVenue then
                if GetGameTimer() - resolvedAt > 3000 then resolve() end
                for _, m in ipairs(markers) do
                    DrawMarker(m[1], m[2], m[3], m[4], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, m[5], m[5], m[6],
                        m[7], m[8], m[9], m[10], false, false, 2, false, nil, nil, false)
                end
                Wait(0)
            else
                Wait(1500)
            end
        end
    end)
end
