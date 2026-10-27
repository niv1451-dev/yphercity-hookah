-- All interaction points of the lounge (hostess, waiters, tables, staff point).
-- canInteract only hides options that make no sense right now; the server
-- re-validates every action anyway.

Interactions = {
    handles = {},
}

local function me() return State.me or {} end

local function hasPerm(perm)
    for _, p in ipairs(me().perms or {}) do
        if p == perm then return true end
    end
    return false
end

local function isStaff() return me().staffRole ~= nil end

local function invitedTo(tableId)
    for _, invite in ipairs(me().invites or {}) do
        if invite.tableId == tableId then return true end
    end
    return false
end

local function publicTable(tableId)
    for _, t in ipairs(State.tables or {}) do
        if t.id == tableId then return t end
    end
    return nil
end

local function hasBill()
    local bill = me().bill or {}
    return (bill.personal or 0) > 0 or (bill.table or 0) > 0
end

local function callWaiter()
    local result = UI.Decorate(Callback.Await('callWaiter', {}))
    Notify.Send(result.message, result.ok and 'success' or 'error')
end

local function add(handle)
    if handle then Interactions.handles[#Interactions.handles + 1] = handle end
end

local function registerHostess()
    local entry = Peds.hostess
    if not entry then return end
    local distance = Config.Hostess.interactDistance or 2.0
    add(Target.AddEntity(entry.ped, {
        {
            name = 'cch_host_talk',
            label = L('target_talk_host'),
            icon = 'fa-solid fa-user-tie',
            distance = distance,
            onSelect = function() UI.Open('host') end,
        },
        {
            name = 'cch_host_staff',
            label = L('target_host_staff'),
            icon = 'fa-solid fa-clipboard-list',
            distance = distance,
            canInteract = function() return hasPerm('view_tables') end,
            onSelect = function() Client.OpenStaff() end,
        },
    }))
end

local function registerWaiters()
    local distance = Config.WaiterBehaviour.interactDistance or 2.0
    for index, entry in pairs(Peds.waiters) do
        add(Target.AddEntity(entry.ped, {
            {
                name = 'cch_waiter_order_' .. index,
                label = L('target_order'),
                icon = 'fa-solid fa-utensils',
                distance = distance,
                onSelect = function() UI.Open('menu') end,
            },
            {
                name = 'cch_waiter_orders_' .. index,
                label = L('target_my_orders'),
                icon = 'fa-solid fa-list-check',
                distance = distance,
                canInteract = function() return me().tableId ~= nil or #(me().orders or {}) > 0 or #(me().served or {}) > 0 end,
                onSelect = function() UI.Open('orders') end,
            },
            {
                name = 'cch_waiter_bill_' .. index,
                label = L('target_bill'),
                icon = 'fa-solid fa-receipt',
                distance = distance,
                canInteract = hasBill,
                onSelect = function() UI.Open('bill', { mode = 'personal' }) end,
            },
        }))
    end
end

local function registerTables()
    local radius = Config.TableSettings.interactRadius or 1.8
    for _, def in ipairs(Config.Tables or {}) do
        local id = def.id
        local center = vec3(def.center.x, def.center.y, ClientUtil.FloorZ(def.center) + 1.0)
        add(Target.AddZone('cch_table_' .. id, center, radius, {
            {
                name = 'cch_table_sit_' .. id,
                label = L('target_sit'),
                icon = 'fa-solid fa-chair',
                distance = radius + 0.5,
                canInteract = function()
                    if Seat.current then return false end
                    if me().tableId == id then return true end
                    if me().tableId then return false end
                    if invitedTo(id) then return true end
                    local t = publicTable(id)
                    return Config.TableSettings.allowFreeJoin and t ~= nil and t.status == 'occupied' and t.members < t.capacity
                end,
                onSelect = function() Seat.RequestSit(id) end,
            },
            {
                name = 'cch_table_stand_' .. id,
                label = L('target_stand'),
                icon = 'fa-solid fa-person-walking',
                distance = radius + 0.5,
                canInteract = function() return Seat.current ~= nil and Seat.current.tableId == id end,
                onSelect = function() Seat.Stand() end,
            },
            {
                name = 'cch_table_menu_' .. id,
                label = L('target_table_menu'),
                icon = 'fa-solid fa-book-open',
                distance = radius + 0.5,
                canInteract = function() return me().tableId == id end,
                onSelect = function() UI.Open('menu') end,
            },
            {
                name = 'cch_table_waiter_' .. id,
                label = L('target_call_waiter'),
                icon = 'fa-solid fa-bell-concierge',
                distance = radius + 0.5,
                canInteract = function() return me().tableId == id end,
                onSelect = callWaiter,
            },
            {
                name = 'cch_table_bill_' .. id,
                label = L('target_bill'),
                icon = 'fa-solid fa-receipt',
                distance = radius + 0.5,
                canInteract = function() return me().tableId == id and hasBill() end,
                onSelect = function() UI.Open('bill', { mode = me().isOwner and 'table' or 'personal' }) end,
            },
            {
                name = 'cch_table_leave_' .. id,
                label = L('target_leave'),
                icon = 'fa-solid fa-door-open',
                distance = radius + 0.5,
                canInteract = function() return me().tableId == id end,
                onSelect = function() Seat.Leave() end,
            },
        }))
    end
end

local function registerStaffPoint()
    local point = Config.Staff.managementPoint
    if not point or not point.coords then return end
    local coords = vec3(point.coords.x, point.coords.y, ClientUtil.FloorZ(point.coords) + 1.0)
    add(Target.AddZone('cch_staff_point', coords, point.radius or 1.2, {
        {
            name = 'cch_staff_panel',
            label = L('target_staff_panel'),
            icon = 'fa-solid fa-cash-register',
            distance = (point.radius or 1.2) + 0.5,
            canInteract = isStaff,
            onSelect = function() Client.OpenStaff() end,
        },
    }))
end

function Interactions.Register()
    if #Interactions.handles > 0 then return end
    registerHostess()
    registerWaiters()
    registerTables()
    registerStaffPoint()
end

function Interactions.Unregister()
    for _, handle in ipairs(Interactions.handles) do Target.Remove(handle) end
    Interactions.handles = {}
end
