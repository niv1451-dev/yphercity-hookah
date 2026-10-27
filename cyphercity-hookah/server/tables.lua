-- Table state machine: free → reserved → occupied → cleaning → free.
-- The FiveM server runs Lua on a single thread and none of these functions
-- yield, so every check-then-assign below is atomic: two players asking for the
-- last table at the same moment are handled one after the other, and the second
-- request sees the table as taken.

Tables = {
    list = {},
    byId = {},
}

local memberOf = {}     -- [src] = tableId
local invites = {}      -- [src] = { [tableId] = { expires, session, from } }
local settings

local function now() return Utils.Now() end

local function sortedMembers(t)
    local list = {}
    for _, src in ipairs(t.memberOrder) do
        if t.members[src] then list[#list + 1] = src end
    end
    return list
end

-- Static part of a table, built from a Config.Tables entry (nil + error when invalid).
local function buildTable(def, index, byId, errors)
    local id = Utils.ToInt(def.id)
    if not id then
        errors[#errors + 1] = ('Config.Tables[%d] has no numeric id'):format(index)
    elseif byId[id] then
        errors[#errors + 1] = ('Duplicate table id %d'):format(id)
    elseif type(def.seats) ~= 'table' or #def.seats == 0 then
        errors[#errors + 1] = ('Table %d has no seats'):format(id)
    elseif not def.center then
        errors[#errors + 1] = ('Table %d has no center'):format(id)
    else
        local capacity = Utils.ToInt(def.capacity) or #def.seats
        if capacity > #def.seats then
            errors[#errors + 1] = ('Table %d: capacity %d is larger than its %d seats — using %d'):format(id, capacity, #def.seats, #def.seats)
            capacity = #def.seats
        end
        return {
            id = id,
            label = def.label or ('#' .. id),
            capacity = math.max(1, capacity),
            vip = def.vip == true,
            center = def.center,
            hookahSpots = #(def.hookahSpots or {}),
            seatCount = #def.seats,
            signature = Layout.Signature(def),
        }
    end
    return nil
end

local function newTable(static, session)
    static.status = 'free'
    static.owner = nil
    static.ownerName = nil
    static.members = {}
    static.memberOrder = {}
    static.seats = {}
    static.partySize = 0
    static.session = session or 0  -- increases every time a new party gets the table
    static.updatedAt = now()
    return static
end

-- Last session number of tables that were removed by a layout edit, so a table
-- that comes back under the same id never mixes its parties with old orders.
local retiredSessions = {}

function Tables.Init()
    settings = Config.TableSettings
    Tables.list, Tables.byId = {}, {}
    memberOf, invites = {}, {}
    local errors = {}

    for index, def in ipairs(Config.Tables or {}) do
        local static = buildTable(def, index, Tables.byId, errors)
        if static then
            local t = newTable(static, retiredSessions[static.id])
            Tables.list[#Tables.list + 1] = t
            Tables.byId[t.id] = t
        end
    end
    return errors
end

-- Tables that are in use (anything but free) and would be changed or removed
-- if Config.Tables became `defs`. Their parties must never be disturbed.
function Tables.LayoutConflicts(defs)
    local byId = {}
    for _, def in ipairs(defs or {}) do byId[Utils.ToInt(def.id) or -1] = def end
    local conflicts = {}
    for _, t in ipairs(Tables.list) do
        if t.status ~= 'free' then
            local def = byId[t.id]
            if not def or Layout.Signature(def) ~= t.signature then conflicts[#conflicts + 1] = t.label end
        end
    end
    return conflicts
end

-- Rebuilds the table list after the layout changed. Tables that keep their id
-- keep their state (party, session, status); only labels, VIP and positions are
-- refreshed. Callers check Tables.LayoutConflicts first, so tables in use are
-- never changed here.
function Tables.Reload()
    local previous = Tables.byId
    local list, byId, errors = {}, {}, {}
    for index, def in ipairs(Config.Tables or {}) do
        local static = buildTable(def, index, byId, errors)
        if static then
            local t = previous[static.id]
            if t then
                for key, value in pairs(static) do t[key] = value end
            else
                t = newTable(static, retiredSessions[static.id])
            end
            list[#list + 1] = t
            byId[t.id] = t
        end
    end
    for id, t in pairs(previous) do
        if not byId[id] then
            retiredSessions[id] = t.session
            Hookah.RemoveByTable(id, 'layout_changed')
            for _, entry in pairs(invites) do entry[id] = nil end
        end
    end
    Tables.list, Tables.byId = list, byId
    Sync.Tables()
    return errors
end

function Tables.Get(id)
    return Tables.byId[Utils.ToInt(id) or -1]
end

function Tables.Of(src)
    local id = memberOf[src]
    if not id then return nil end
    local t = Tables.byId[id]
    return t, t and t.members[src]
end

function Tables.MemberCount(t)
    return Utils.Count(t.members)
end

function Tables.SeatedCount(t)
    return Utils.Count(t.seats)
end

function Tables.IsSeated(src)
    local t, member = Tables.Of(src)
    return t ~= nil and member ~= nil and member.seat ~= nil, t
end

function Tables.IsOwner(src)
    local t = Tables.Of(src)
    return t ~= nil and t.owner == src
end

local function setStatus(t, status, reason, by)
    if t.status == status then return end
    local old = t.status
    t.status = status
    t.updatedAt = now()
    Logger.Info('table', ('%s: %s → %s (%s)'):format(t.label, old, status, reason or '-'), { table = t.id, by = by })
    Sync.Tables()
end

local function addMember(t, src)
    t.members[src] = {
        joinedAt = now(),
        name = Framework.GetCharName(src),
        identifier = Framework.GetIdentifier(src),
    }
    t.memberOrder[#t.memberOrder + 1] = src
    memberOf[src] = t.id
    invites[src] = nil
    Sync.Table(t.id)
end

local function removeMember(t, src)
    local member = t.members[src]
    if member and member.seat then t.seats[member.seat] = nil end
    t.members[src] = nil
    for i = #t.memberOrder, 1, -1 do
        if t.memberOrder[i] == src then table.remove(t.memberOrder, i) end
    end
    memberOf[src] = nil
    Sync.Player(src)
    Sync.Table(t.id)
end

local function setOwner(t, src)
    t.owner = src
    if src then
        local member = t.members[src]
        t.ownerName = member and member.name or Framework.GetCharName(src)
    else
        t.ownerName = nil
    end
end

local function freeSeat(t)
    for i = 1, t.seatCount do
        if t.seats[i] == nil then return i end
    end
    return nil
end

-- Chooses the smallest free table that fits the party (VIP tables last).
local function pickTable(partySize)
    local best
    for _, t in ipairs(Tables.list) do
        if t.status == 'free' and t.capacity >= partySize then
            if not best
                or (best.vip and not t.vip)
                or (best.vip == t.vip and t.capacity < best.capacity) then
                best = t
            end
        end
    end
    return best
end

function Tables.RequestTable(src, partySize)
    local current = Tables.Of(src)
    if current then return false, 'already_has_table', current.label end
    partySize = Utils.ToInt(partySize)
    if not partySize or partySize < 1 or partySize > (settings.maxPartySize or 6) then
        return false, 'party_size_invalid'
    end
    local t = pickTable(partySize)
    if not t then return false, 'no_free_table' end

    t.partySize = partySize
    t.session = t.session + 1
    t.reservedFor = nil
    t.reservedUntil = now() + (settings.reserveTimeout or 180)
    addMember(t, src)
    setOwner(t, src)
    setStatus(t, 'reserved', 'hostess', src)
    Logger.Info('table', ('%s assigned to %s (party of %d)'):format(t.label, Security.Describe(src), partySize), { table = t.id, player = src })
    return true, t
end

function Tables.Sit(src, tableId)
    local t = Tables.Get(tableId)
    if not t then return false, 'table_not_found' end
    local currentId = memberOf[src]
    if currentId and currentId ~= t.id then
        return false, 'already_has_table', Tables.byId[currentId].label
    end

    if not currentId then
        if (t.status ~= 'occupied' and t.status ~= 'reserved') or not t.owner then
            return false, 'table_unavailable'
        end
        local invite = invites[src] and invites[src][t.id]
        local validInvite = invite and invite.expires > now() and invite.session == t.session
        if not settings.allowFreeJoin and not validInvite then
            return false, 'not_your_table'
        end
        if Tables.MemberCount(t) >= t.capacity then return false, 'table_full' end
        addMember(t, src)
    end

    local member = t.members[src]
    if member.seat then return true, member.seat, t end
    local seat = freeSeat(t)
    if not seat then return false, 'table_full' end
    member.seat = seat
    t.seats[seat] = src
    if t.status == 'reserved' then
        t.reservedUntil = nil
        t.openedAt = now()
        setStatus(t, 'occupied', 'seated', src)
    end
    Sync.Table(t.id)
    return true, seat, t
end

function Tables.Stand(src)
    local t, member = Tables.Of(src)
    if not t then return false, 'no_table' end
    if member.seat then
        t.seats[member.seat] = nil
        member.seat = nil
        Sync.Table(t.id)
    end
    return true
end

-- Full reset of a table. Callers decide what happens to unpaid orders first.
function Tables.Release(t, reason, by)
    for _, src in ipairs(sortedMembers(t)) do
        Orders.ClearServed(src)
        removeMember(t, src)
        TriggerClientEvent('cyphercity-hookah:client:forceStand', src)
        Notify.Player(src, L('table_released_notice', t.label), 'info')
    end
    Hookah.RemoveByTable(t.id, reason)
    Orders.OnTableReleased(t.id, t.session, reason)
    for _, entry in pairs(invites) do entry[t.id] = nil end
    setOwner(t, nil)
    t.members, t.memberOrder, t.seats = {}, {}, {}
    t.partySize = 0
    t.reservedUntil, t.reservedFor, t.openedAt = nil, nil, nil
    local cleaning = settings.cleaningTime or 0
    if cleaning > 0 then
        t.cleaningUntil = now() + cleaning
        setStatus(t, 'cleaning', reason, by)
    else
        t.cleaningUntil = nil
        setStatus(t, 'free', reason, by)
    end
    Sync.Table(t.id)
end

-- opts.force = skip the unpaid-bill check (disconnects, staff, walkouts)
function Tables.Leave(src, opts)
    opts = opts or {}
    local t = Tables.Of(src)
    if not t then return false, 'no_table' end
    if not opts.force and Config.Payments.requireBillBeforeLeave then
        local unpaid = Orders.UnpaidTotalFor(src)
        if unpaid > 0 then return false, 'unpaid_bill_leave', Utils.FormatMoney(unpaid) end
    end

    local name = t.members[src] and t.members[src].name or GetPlayerName(src) or '?'
    Orders.ClearServed(src)
    Hookah.ReleaseUser(src)
    removeMember(t, src)
    Logger.Info('table', ('%s left %s (%s)'):format(Security.Describe(src), t.label, opts.reason or 'leave'), { table = t.id, player = src })

    local remaining = sortedMembers(t)
    if #remaining == 0 then
        Tables.Release(t, opts.reason or 'empty', src)
        return true, t
    end

    if t.owner == src then
        local anyUnpaid = false
        for _, other in ipairs(remaining) do
            if Orders.UnpaidTotalFor(other) > 0 then anyUnpaid = true break end
        end
        if settings.ownerDropBehaviour == 'release' and not anyUnpaid then
            Tables.Release(t, 'owner_left', src)
            return true, t
        end
        setOwner(t, remaining[1])
        Notify.Player(remaining[1], L('ownership_transferred', t.label), 'info')
        Logger.Info('table', ('%s ownership transferred to %s'):format(t.label, Security.Describe(remaining[1])), { table = t.id })
    end
    for _, other in ipairs(remaining) do
        Notify.Player(other, L('member_left', name), 'info')
    end
    Sync.Table(t.id)
    return true, t
end

function Tables.NearbyPlayers(src, distance)
    local list = {}
    distance = distance or settings.inviteDistance or 8.0
    for _, id in ipairs(GetPlayers()) do
        local other = tonumber(id)
        if other and other ~= src and not memberOf[other] then
            if Security.DistanceBetweenPlayers(src, other) <= distance then
                list[#list + 1] = { id = other, name = Framework.GetCharName(other) }
            end
        end
    end
    return list
end

function Tables.Invite(src, target)
    local t = Tables.Of(src)
    if not t then return false, 'no_table' end
    if t.owner ~= src then return false, 'not_table_owner' end
    target = Utils.ToInt(target)
    if not target or target == src or not GetPlayerName(target) then return false, 'invite_invalid' end
    if memberOf[target] then return false, 'invite_invalid' end
    if Security.DistanceBetweenPlayers(src, target) > (settings.inviteDistance or 8.0) then
        return false, 'player_not_nearby'
    end
    if Tables.MemberCount(t) >= t.capacity then return false, 'table_full' end
    invites[target] = invites[target] or {}
    invites[target][t.id] = { expires = now() + 300, session = t.session, from = Framework.GetCharName(src) }
    Notify.Player(target, L('invite_received', Framework.GetCharName(src), t.label), 'info')
    Sync.Player(target)
    Logger.Info('table', ('%s invited %s to %s'):format(Security.Describe(src), Security.Describe(target), t.label), { table = t.id })
    return true, Framework.GetCharName(target)
end

function Tables.InvitesFor(src)
    local list = {}
    local entry = invites[src]
    if not entry then return list end
    local current = now()
    for tableId, invite in pairs(entry) do
        local t = Tables.byId[tableId]
        if invite.expires > current and t and t.owner and invite.session == t.session then
            list[#list + 1] = { tableId = tableId, label = t.label, from = invite.from, expiresIn = invite.expires - current }
        end
    end
    return list
end

-- Staff operations ---------------------------------------------------------------
function Tables.StaffAction(staffSrc, tableId, op, data)
    local t = Tables.Get(tableId)
    if not t then return false, 'table_not_found' end
    data = data or {}

    if op == 'clean' then
        if not Staff.Require(staffSrc, 'clean_table') then return false, 'no_permission' end
        if t.status ~= 'cleaning' then return false, 'table_unavailable' end
        t.cleaningUntil = nil
        setStatus(t, 'free', 'cleaned', staffSrc)
    elseif op == 'release' then
        if not Staff.Require(staffSrc, 'release_table') then return false, 'no_permission' end
        if t.status == 'free' then return false, 'table_unavailable' end
        for _, src in ipairs(sortedMembers(t)) do
            Orders.VoidFor(src, 'staff_release', t.id)
        end
        Tables.Release(t, 'staff_release', staffSrc)
    elseif op == 'reserve' then
        if not Staff.Require(staffSrc, 'reserve_table') then return false, 'no_permission' end
        if t.status ~= 'free' then return false, 'table_unavailable' end
        t.reservedFor = Utils.SanitizeString(data.name, 32)
        if not t.reservedFor or t.reservedFor == '' then t.reservedFor = '-' end
        t.reservedUntil = now() + (settings.staffReserveMinutes or 30) * 60
        setStatus(t, 'reserved', 'staff_reserve', staffSrc)
    elseif op == 'unreserve' then
        if not Staff.Require(staffSrc, 'reserve_table') then return false, 'no_permission' end
        if t.status ~= 'reserved' or t.owner then return false, 'table_unavailable' end
        t.reservedFor, t.reservedUntil = nil, nil
        setStatus(t, 'free', 'staff_unreserve', staffSrc)
    elseif op == 'seat_guest' then
        if not Staff.Require(staffSrc, 'seat_guest') then return false, 'no_permission' end
        local target = Utils.ToInt(data.target)
        if not target or not GetPlayerName(target) or memberOf[target] then return false, 'invite_invalid' end
        if Security.DistanceBetweenPlayers(staffSrc, target) > (settings.inviteDistance or 8.0) then
            return false, 'player_not_nearby'
        end
        if t.status ~= 'free' and not (t.status == 'reserved' and not t.owner) then
            return false, 'table_unavailable'
        end
        t.reservedFor = nil
        t.partySize = t.capacity
        t.session = t.session + 1
        t.reservedUntil = now() + (settings.reserveTimeout or 180)
        addMember(t, target)
        setOwner(t, target)
        setStatus(t, 'reserved', 'staff_seat', staffSrc)
        Notify.Player(target, L('table_assigned', t.label, Utils.FormatDuration(settings.reserveTimeout or 180)), 'success')
        TriggerClientEvent('cyphercity-hookah:client:tableAssigned', target, t.id)
        return true, L('staff_guest_seated', Framework.GetCharName(target), t.label)
    else
        return false, 'invalid_request'
    end
    Logger.Info('staff', ('%s: %s on %s'):format(Security.Describe(staffSrc), op, t.label), { table = t.id, op = op })
    return true, L('staff_table_updated', t.label, L('status_' .. t.status))
end

-- Periodic housekeeping ------------------------------------------------------------
local awayCheckAt = 0

function Tables.Tick()
    local current = now()
    for _, t in ipairs(Tables.list) do
        if t.status == 'reserved' and t.reservedUntil and current >= t.reservedUntil then
            if t.owner then
                Notify.Player(t.owner, L('table_reserve_expired', t.label), 'error')
                Tables.Release(t, 'reserve_expired')
            else
                t.reservedFor, t.reservedUntil = nil, nil
                setStatus(t, 'free', 'reserve_expired')
            end
        elseif t.status == 'cleaning' and t.cleaningUntil and current >= t.cleaningUntil then
            t.cleaningUntil = nil
            setStatus(t, 'free', 'cleaned_auto')
        end
    end

    -- expire old invites
    for src, entry in pairs(invites) do
        for tableId, invite in pairs(entry) do
            local t = Tables.byId[tableId]
            if invite.expires <= current or not t or invite.session ~= t.session then entry[tableId] = nil end
        end
        if not next(entry) then invites[src] = nil end
    end

    if current < awayCheckAt or not Security.oneSync then return end
    awayCheckAt = current + 5
    local awayTimeout = settings.awayTimeout or 120
    for _, t in ipairs(Tables.list) do
        for _, src in ipairs(sortedMembers(t)) do
            local member = t.members[src]
            -- a release earlier in this loop can empty the table
            if member then
                local position = Security.GetCoords(src)
                local away = position and not Utils.WithinRange(position, Config.Venue.center, Security.AwayDistance(), 30.0)
                if not away then
                    member.awaySince = nil
                else
                    member.awaySince = member.awaySince or current
                    -- players with an open bill are handled by Orders.TickWalkouts (warning, grace, void + log)
                    if current - member.awaySince >= awayTimeout and Orders.UnpaidTotalFor(src) <= 0 then
                        Notify.Player(src, L('removed_from_table_away', t.label), 'info')
                        Tables.Leave(src, { force = true, reason = 'away' })
                    end
                end
            end
        end
    end
end

-- Unpaid orders are voided (and logged) by Orders.OnDropped, which runs first.
function Tables.OnDropped(src)
    invites[src] = nil
    if Tables.Of(src) then
        Tables.Leave(src, { force = true, reason = 'disconnect' })
    end
end

-- Views -----------------------------------------------------------------------------
function Tables.PublicList()
    local list = {}
    for _, t in ipairs(Tables.list) do
        local seats = {}
        for i = 1, t.seatCount do
            seats[i] = t.seats[i] ~= nil
        end
        list[#list + 1] = {
            id = t.id,
            label = t.label,
            capacity = t.capacity,
            status = t.status,
            vip = t.vip,
            members = Tables.MemberCount(t),
            seated = Tables.SeatedCount(t),
            occupiedSeats = seats,
        }
    end
    return list
end

function Tables.StaffList()
    local list = {}
    local current = now()
    for _, t in ipairs(Tables.list) do
        local members = {}
        for _, src in ipairs(sortedMembers(t)) do
            local member = t.members[src]
            members[#members + 1] = {
                id = src,
                name = member.name,
                seated = member.seat ~= nil,
                owner = t.owner == src,
                unpaid = Orders.UnpaidTotalFor(src),
                away = member.awaySince ~= nil,
            }
        end
        list[#list + 1] = {
            id = t.id,
            label = t.label,
            capacity = t.capacity,
            vip = t.vip,
            status = t.status,
            owner = t.ownerName,
            members = members,
            unpaid = Orders.UnpaidTotalForTable(t.id),
            reservedFor = t.reservedFor,
            timer = (t.reservedUntil and t.reservedUntil - current) or (t.cleaningUntil and t.cleaningUntil - current) or nil,
            openFor = t.openedAt and (current - t.openedAt) or nil,
            hookahs = #Hookah.ForTable(t.id),
        }
    end
    return list
end

function Tables.Session(tableId)
    local t = Tables.byId[tableId]
    return t and t.session or nil
end

function Tables.MemberIds(tableId)
    local t = Tables.byId[tableId]
    return t and sortedMembers(t) or {}
end
