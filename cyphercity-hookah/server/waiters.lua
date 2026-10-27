-- NPC waiter visits. A guest presses "call a waiter": the NPC waiter walks to
-- the table, stands next to the guests with a notepad and "writes down" what
-- each of them picks in the menu. The order itself is the normal menu order
-- (priced and checked by the server); this module only keeps track of the
-- visit, so every client shows the same waiter, and ends it once every guest
-- has ordered or passed, left the table, or the waiter waited long enough.

WaiterVisits = {
    byTable = {},   -- [tableId] = { id, tableId, session, caller, pending = { [src] = true }, taken, waiter, expires }
}

local nextId = 0

local function settings()
    return Config.WaiterBehaviour.takeOrder or {}
end

function WaiterVisits.Enabled()
    return settings().enabled ~= false
end

-- Name of the NPC waiter who serves a table (Config.Waiters or the in-game layout).
function WaiterVisits.WaiterName(tableId)
    local index
    for _, def in ipairs(Config.Tables or {}) do
        if def.id == tableId then index = def.waiter break end
    end
    if not index then
        for i, waiter in ipairs(Config.Waiters or {}) do
            if Utils.Contains(waiter.tables or {}, tableId) then index = i break end
        end
    end
    local waiter = (Config.Waiters or {})[index or 1]
    return (waiter and waiter.name) or L('waiter_default_name')
end

local function finish(visit, reason)
    WaiterVisits.byTable[visit.tableId] = nil
    TriggerClientEvent('cyphercity-hookah:client:waiterVisitEnd', -1, visit.tableId, visit.id)
    Sync.Table(visit.tableId)
    Logger.Debug('table', ('Waiter visit #%d at table %s ended (%s, %d order(s))'):format(visit.id, tostring(visit.tableId), reason, visit.taken))
end

-- Starts a visit (or returns the one already on its way). Returns visit, alreadyComing.
function WaiterVisits.Call(src, t)
    local visit = WaiterVisits.byTable[t.id]
    if visit then return visit, true end
    nextId = nextId + 1
    local members, pending = {}, {}
    for _, id in ipairs(Tables.MemberIds(t.id)) do
        members[#members + 1] = id
        pending[id] = true
    end
    local _, member = Tables.Of(src)
    local wait = settings().waitSeconds or 60
    local walk = (Config.WaiterBehaviour.walkTimeout or 20000) / 1000
    visit = {
        id = nextId,
        tableId = t.id,
        session = t.session,
        caller = src,
        pending = pending,
        taken = 0,
        waiter = WaiterVisits.WaiterName(t.id),
        -- room for the walk there (twice, in case the waiter is still busy at another table) and the wait
        expires = Utils.Now() + walk * 2 + wait,
    }
    WaiterVisits.byTable[t.id] = visit
    TriggerClientEvent('cyphercity-hookah:client:waiterVisit', -1, t.id, {
        id = visit.id,
        members = members,
        seat = member and member.seat or nil,
        waiter = visit.waiter,
        wait = wait,
    })
    Sync.Table(t.id)
    return visit, false
end

local function done(visit, src)
    visit.pending[src] = nil
    if next(visit.pending) == nil then
        finish(visit, 'everyone ordered')
    else
        Sync.Player(src)
    end
end

-- The guest closed the menu the waiter opened without ordering ("nothing for me").
function WaiterVisits.Pass(src)
    local t = Tables.Of(src)
    local visit = t and WaiterVisits.byTable[t.id]
    if not visit or not visit.pending[src] then return false end
    done(visit, src)
    return true
end

-- Called after a guest's order was created. Returns the waiter's name when the
-- waiter was standing at the guest's table for them (the order was "written down").
function WaiterVisits.OnOrder(src, order)
    local visit = order.tableId and WaiterVisits.byTable[order.tableId]
    if not visit or not visit.pending[src] then return nil end
    visit.taken = visit.taken + 1
    done(visit, src)
    return visit.waiter
end

-- For the player state: the waiter is at the guest's table waiting for their order.
function WaiterVisits.ForPlayer(src, t)
    local visit = t and WaiterVisits.byTable[t.id]
    if not visit or not visit.pending[src] then return nil end
    return { id = visit.id, waiter = visit.waiter }
end

function WaiterVisits.Tick()
    local current = Utils.Now()
    for tableId, visit in pairs(WaiterVisits.byTable) do
        local t = Tables.Get(tableId)
        if not t or t.status ~= 'occupied' or t.session ~= visit.session then
            finish(visit, 'table released')
        elseif current >= visit.expires then
            finish(visit, 'timeout')
        else
            -- guests who left the table do not keep the waiter waiting
            for src in pairs(visit.pending) do
                if Tables.Of(src) ~= t then visit.pending[src] = nil end
            end
            if next(visit.pending) == nil then finish(visit, 'guests left') end
        end
    end
end
