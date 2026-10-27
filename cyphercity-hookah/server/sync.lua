-- Batched state pushes to clients. Modules only mark things as dirty; a single
-- loop flushes at most every 250 ms so a burst of changes becomes one message.

Sync = {}

local dirtyTables = false
local dirtyHookahs = false
local dirtyStaff = false
local dirtyPlayers = {}
local staffSubscribers = {} -- [src] = expiresAt (os.time) — staff with the panel open

function Sync.Tables()
    dirtyTables = true
    dirtyStaff = true
end

function Sync.Player(src)
    if src then dirtyPlayers[src] = true end
end

function Sync.Staff()
    dirtyStaff = true
end

function Sync.Table(tableId)
    for _, src in ipairs(Tables.MemberIds(tableId)) do dirtyPlayers[src] = true end
    Sync.Tables()
end

function Sync.Hookahs(tableId)
    dirtyHookahs = true
    dirtyStaff = true
    if tableId then
        for _, src in ipairs(Tables.MemberIds(tableId)) do dirtyPlayers[src] = true end
    end
end

function Sync.Order(order)
    dirtyPlayers[order.src] = true
    if order.tableId then
        for _, src in ipairs(Tables.MemberIds(order.tableId)) do dirtyPlayers[src] = true end
    end
    dirtyStaff = true
end

function Sync.Subscribe(src)
    staffSubscribers[src] = Utils.Now() + 900
end

function Sync.Unsubscribe(src)
    staffSubscribers[src] = nil
end

function Sync.BuildPlayerState(src)
    local t, member = Tables.Of(src)
    local role = Staff.GetRole(src)
    local state = {
        serverId = src,
        tableId = t and t.id or nil,
        tableLabel = t and t.label or nil,
        tableStatus = t and t.status or nil,
        seat = member and member.seat or nil,
        isOwner = t ~= nil and t.owner == src,
        reservedFor = t and t.reservedUntil and math.max(0, t.reservedUntil - Utils.Now()) or nil,
        members = {},
        invites = Tables.InvitesFor(src),
        orders = Orders.ForPlayer(src),
        served = Orders.ServedList(src),
        hookahs = {},
        bill = {
            personal = Orders.UnpaidTotalFor(src),
            table = t and Orders.UnpaidTotalForTable(t.id) or 0,
        },
        staffRole = role,
        perms = Staff.PermissionList(role),
        businessOpen = Business.IsOpen(),
        waiterVisit = WaiterVisits.ForPlayer(src, t),
    }
    if t then
        for _, id in ipairs(Tables.MemberIds(t.id)) do
            local m = t.members[id]
            state.members[#state.members + 1] = { id = id, name = m.name, seated = m.seat ~= nil, owner = t.owner == id, me = id == src }
        end
        for _, session in ipairs(Hookah.ForTable(t.id)) do
            state.hookahs[#state.hookahs + 1] = Hookah.View(session)
        end
    end
    return state
end

function Sync.BuildStaffState(src)
    local role = Staff.GetRole(src)
    if not role then return nil end
    local state = {
        role = role,
        perms = Staff.PermissionList(role),
        businessOpen = Business.IsOpen(),
        businessManualOpen = Business.manualOpen,
        mode = Config.Orders.mode,
        tables = Staff.RoleHas(role, 'view_tables') and Tables.StaffList() or {},
        orders = Staff.RoleHas(role, 'view_orders') and Orders.StaffList() or {},
        stock = Staff.RoleHas(role, 'manage_stock') and Orders.StockList() or nil,
    }
    return state
end

function Sync.Flush()
    if dirtyTables then
        dirtyTables = false
        TriggerClientEvent('cyphercity-hookah:client:tables', -1, Tables.PublicList())
    end
    if dirtyHookahs then
        dirtyHookahs = false
        TriggerClientEvent('cyphercity-hookah:client:hookahs', -1, Hookah.PublicState())
    end
    if next(dirtyPlayers) then
        local players = dirtyPlayers
        dirtyPlayers = {}
        for src in pairs(players) do
            if GetPlayerName(src) then
                TriggerClientEvent('cyphercity-hookah:client:playerState', src, Sync.BuildPlayerState(src))
            end
        end
    end
    if dirtyStaff then
        dirtyStaff = false
        local current = Utils.Now()
        for src, expires in pairs(staffSubscribers) do
            if expires < current or not GetPlayerName(src) then
                staffSubscribers[src] = nil
            else
                local state = Sync.BuildStaffState(src)
                if state then
                    TriggerClientEvent('cyphercity-hookah:client:staffState', src, state)
                else
                    staffSubscribers[src] = nil
                end
            end
        end
    end
end

function Sync.OnDropped(src)
    dirtyPlayers[src] = nil
    staffSubscribers[src] = nil
end
