-- Optional furniture (tables + chairs) for locations without an MLO. Local
-- objects, created when the player approaches and deleted when they leave.

Furniture = {
    objects = {},
}

local function place(hash, x, y, z, heading)
    local object = CreateObject(hash, x, y, z, false, false, false)
    if not object or object == 0 then return nil end
    SetEntityHeading(object, heading or 0.0)
    if Config.Venue.snapToGround then PlaceObjectOnGroundProperly(object) end
    FreezeEntityPosition(object, true)
    Furniture.objects[#Furniture.objects + 1] = object
    return object
end

function Furniture.Spawn()
    local settings = Config.Furniture
    if not settings or not settings.enabled or #Furniture.objects > 0 then return end
    local tableHash = ClientUtil.LoadModel(settings.tableModel)
    local chairHash = ClientUtil.LoadModel(settings.chairModel)

    for _, def in ipairs(Config.Tables or {}) do
        if tableHash and def.center then
            place(tableHash, def.center.x, def.center.y, ClientUtil.FloorZ(def.center), 0.0)
        end
        if chairHash then
            for _, seat in ipairs(def.seats or {}) do
                place(chairHash, seat.x, seat.y, ClientUtil.FloorZ(seat), (seat.w + (settings.chairHeadingOffset or 180.0)) % 360.0)
            end
        end
    end
    if tableHash then SetModelAsNoLongerNeeded(tableHash) end
    if chairHash then SetModelAsNoLongerNeeded(chairHash) end
end

function Furniture.Despawn()
    for _, object in ipairs(Furniture.objects) do
        if DoesEntityExist(object) then DeleteEntity(object) end
    end
    Furniture.objects = {}
end
