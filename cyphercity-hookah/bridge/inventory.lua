-- Inventory bridge (server only). Default is 'none' = catalog-only mode: the
-- lounge sells and serves products without creating any inventory items.
-- Adapters follow the current public exports of each inventory:
--   ox_inventory : Items, GetItemCount, CanCarryItem, AddItem, RemoveItem
--   qb-inventory : GetItemCount, CanAddItem, AddItem, RemoveItem (+ QBCore.Shared.Items)
--   esx          : ESX.GetItemLabel, xPlayer.getInventoryItem / canCarryItem / addInventoryItem / removeInventoryItem

Inventory = { name = 'none' }

local adapters = {}

adapters.none = {
    exists = function() return false end,
}

adapters.ox_inventory = {
    exists = function(item)
        return exports[Bridge.ResourceName('ox_inventory')]:Items(item) ~= nil
    end,
    count = function(src, item)
        return exports[Bridge.ResourceName('ox_inventory')]:GetItemCount(src, item) or 0
    end,
    canCarry = function(src, item, count)
        return exports[Bridge.ResourceName('ox_inventory')]:CanCarryItem(src, item, count) == true
    end,
    add = function(src, item, count)
        local success = exports[Bridge.ResourceName('ox_inventory')]:AddItem(src, item, count)
        return success == true
    end,
    remove = function(src, item, count)
        local success = exports[Bridge.ResourceName('ox_inventory')]:RemoveItem(src, item, count)
        return success == true
    end,
}

adapters['qb-inventory'] = {
    exists = function(item)
        local core = Framework.object
        if Bridge.framework == 'qbcore' and core and core.Shared and core.Shared.Items then
            return core.Shared.Items[item:lower()] ~= nil
        end
        local ok, data = pcall(function()
            return exports[Bridge.ResourceName('qbcore')]:GetShared('Items', item:lower())
        end)
        return ok and data ~= nil
    end,
    count = function(src, item)
        return exports[Bridge.ResourceName('qb_inventory')]:GetItemCount(src, item) or 0
    end,
    canCarry = function(src, item, count)
        local ok = exports[Bridge.ResourceName('qb_inventory')]:CanAddItem(src, item, count)
        return ok == true
    end,
    add = function(src, item, count)
        return exports[Bridge.ResourceName('qb_inventory')]:AddItem(src, item, count, nil, nil, 'cyphercity-hookah') == true
    end,
    remove = function(src, item, count)
        return exports[Bridge.ResourceName('qb_inventory')]:RemoveItem(src, item, count, nil, 'cyphercity-hookah') == true
    end,
}

adapters.esx = {
    exists = function(item)
        return Framework.object and Framework.object.GetItemLabel(item) ~= nil
    end,
    count = function(src, item)
        local player = Framework.GetPlayer(src)
        local data = player and player.getInventoryItem(item)
        return data and data.count or 0
    end,
    canCarry = function(src, item, count)
        local player = Framework.GetPlayer(src)
        return player ~= nil and player.canCarryItem(item, count) == true
    end,
    add = function(src, item, count)
        local player = Framework.GetPlayer(src)
        if not player then return false end
        local result = player.addInventoryItem(item, count)
        return result ~= false
    end,
    remove = function(src, item, count)
        local player = Framework.GetPlayer(src)
        if not player then return false end
        local result = player.removeInventoryItem(item, count)
        return result ~= false
    end,
}

local adapter = adapters.none
local existsCache = {}

function Inventory.Init(name)
    adapter = adapters[name] or adapters.none
    Inventory.name = adapters[name] and name or 'none'
    existsCache = {}
    return true
end

function Inventory.Active()
    return Inventory.name ~= 'none'
end

local function safe(fn, ...)
    if not fn then return false, nil end
    local ok, result = pcall(fn, ...)
    if not ok then
        Logger.Warn('system', ('Inventory adapter "%s" error: %s'):format(Inventory.name, tostring(result)))
        return false, nil
    end
    return true, result
end

function Inventory.ItemExists(item)
    if not Inventory.Active() or type(item) ~= 'string' then return false end
    if existsCache[item] == nil then
        local ok, result = safe(adapter.exists, item)
        existsCache[item] = ok and result == true
    end
    return existsCache[item]
end

function Inventory.GetCount(src, item)
    local ok, result = safe(adapter.count, src, item)
    return ok and tonumber(result) or 0
end

function Inventory.CanCarry(src, item, count)
    local ok, result = safe(adapter.canCarry, src, item, count)
    return ok and result == true
end

function Inventory.Add(src, item, count)
    local ok, result = safe(adapter.add, src, item, count)
    return ok and result == true
end

function Inventory.Remove(src, item, count)
    local ok, result = safe(adapter.remove, src, item, count)
    return ok and result == true
end

-- Checks every inventory item referenced in the menu once at start-up and returns
-- a list of warnings for the ones that do not exist (they are then ignored).
function Inventory.ValidateCatalog()
    local warnings = {}
    for _, product in ipairs(Catalog.products) do
        local inv = product.inventory
        if inv then
            for _, kind in ipairs({ 'give', 'require' }) do
                local entry = inv[kind]
                if entry then
                    if not Inventory.Active() then
                        entry.disabled = true
                    elseif not Inventory.ItemExists(entry.name) then
                        entry.disabled = true
                        warnings[#warnings + 1] = ('Menu item "%s": inventory item "%s" (%s) does not exist in %s — ignored'):format(product.id, entry.name, kind, Inventory.name)
                    else
                        entry.disabled = false
                    end
                end
            end
        end
    end
    return warnings
end
