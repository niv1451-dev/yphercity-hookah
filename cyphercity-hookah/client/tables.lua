-- Seating. The server decides which seat a player gets; the client only plays
-- the sitting scenario at that seat and reports when the player stands up.

Seat = {
    current = nil, -- { tableId, seat }
}

local SIT_SCENARIO = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER'
Seat.SCENARIO = SIT_SCENARIO
local guideThread = false

function Seat.Coords(tableId, seatIndex)
    local def = Client.TableDef(tableId)
    local seat = def and def.seats and def.seats[seatIndex]
    if not seat then return nil end
    -- seatZ: per-table height correction (couches, bar stools), set in config or with /hookahsetup
    local z = ClientUtil.FloorZ(seat) + (Config.Furniture.seatZOffset or 0.5) + (def.seatZ or 0.0)
    return vec4(seat.x, seat.y, z, seat.w)
end

local function playSit(coords)
    local ped = PlayerPedId()
    TaskStartScenarioAtPosition(ped, SIT_SCENARIO, coords.x, coords.y, coords.z, coords.w, -1, true, true)
end

-- Re-applies the sitting scenario (used after an upper-body animation).
function Seat.Resume()
    if not Seat.current then return end
    local coords = Seat.Coords(Seat.current.tableId, Seat.current.seat)
    if coords then playSit(coords) end
end

local function monitor()
    CreateThread(function()
        Wait(4000) -- let the enter animation finish
        while Seat.current do
            local ped = PlayerPedId()
            local coords = Seat.Coords(Seat.current.tableId, Seat.current.seat)
            local busy = Consume.active or HookahClient.smoking
            if coords and not busy and not IsPedUsingScenario(ped, SIT_SCENARIO) then
                local distance = #(GetEntityCoords(ped) - vec3(coords.x, coords.y, coords.z))
                if distance > 1.5 or IsEntityDead(ped) then
                    Seat.current = nil
                    Callback.Await('stand', {})
                    break
                end
            end
            Wait(1000)
        end
    end)
end

function Seat.SitAt(tableId, seatIndex)
    local coords = Seat.Coords(tableId, seatIndex)
    if not coords then return end
    Seat.current = { tableId = tableId, seat = seatIndex }
    playSit(coords)
    monitor()
end

function Seat.RequestSit(tableId)
    if Seat.current then return end
    if not tableId then
        tableId = State.me and State.me.tableId
        if not tableId then
            Notify.Send(L('no_table'), 'error')
            return
        end
    end
    local result = UI.Decorate(Callback.Await('sit', { tableId = tableId }))
    if not result.ok then
        Notify.Send(result.message, 'error')
        return
    end
    Notify.Send(result.message, 'success')
    Seat.SitAt(result.data.tableId, result.data.seat)
end

function Seat.StandLocal()
    if not Seat.current then return end
    Seat.current = nil
    ClearPedTasks(PlayerPedId())
end

function Seat.Stand()
    if not Seat.current then return end
    Seat.StandLocal()
    local result = UI.Decorate(Callback.Await('stand', {}))
    if result.ok then Notify.Send(L('stood_up'), 'info') end
end

function Seat.Leave()
    local result = UI.Decorate(Callback.Await('leaveTable', {}))
    if not result.ok then
        Notify.Send(result.message, 'error')
        if result.code == 'unpaid_bill_leave' then UI.Open('bill', { mode = 'personal' }) end
        return
    end
    Seat.StandLocal()
    Notify.Send(result.message, 'success')
end

-- Keeps the local seat in line with what the server says.
function Seat.OnState(previous, state)
    if Seat.current and (not state.seat or state.tableId ~= Seat.current.tableId) then
        Seat.StandLocal()
    end
    if previous and previous.tableId and not state.tableId then
        Seat.StandLocal()
    end
end

RegisterNetEvent('cyphercity-hookah:client:forceStand', function()
    Seat.StandLocal()
end)

-- Gold marker above the table the hostess just assigned.
function Seat.Guide(tableId)
    local def = Client.TableDef(tableId)
    if not def or guideThread then return end
    guideThread = true
    Notify.Send(L('guide_to_table'), 'info')
    CreateThread(function()
        local deadline = GetGameTimer() + (Config.Hostess.guideSeconds or 25) * 1000
        local z = ClientUtil.FloorZ(def.center) + 1.6
        while GetGameTimer() < deadline and not Seat.current and State.inVenue do
            DrawMarker(2, def.center.x, def.center.y, z, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                0.35, 0.35, 0.35, 212, 175, 95, 200, true, true, 2, false, nil, nil, false)
            Wait(0)
        end
        guideThread = false
    end)
end
