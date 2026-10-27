-- Hookah sessions. A session is the world object created when a hookah order is
-- served: it belongs to a table (and a spot next to it), so everyone seated at
-- that table can share it, but only one person can use the hose at a time.
-- Product (menu entry) → order line → session (world object) are kept separate.

Hookah = {
    sessions = {},
}

local nextId = 0
local lastPuff = {} -- [src] = os.time() of the last puff

local function now() return Utils.Now() end

local function cfg() return Config.Hookah end

function Hookah.ForTable(tableId)
    local list = {}
    for _, session in pairs(Hookah.sessions) do
        if session.tableId == tableId then list[#list + 1] = session end
    end
    table.sort(list, function(a, b) return a.spot < b.spot end)
    return list
end

function Hookah.SpotCount(tableId)
    local t = Tables.Get(tableId)
    return t and t.hookahSpots or 0
end

local function freeSpot(tableId)
    local used = {}
    for _, session in pairs(Hookah.sessions) do
        if session.tableId == tableId then used[session.spot] = true end
    end
    for spot = 1, Hookah.SpotCount(tableId) do
        if not used[spot] then return spot end
    end
    return nil
end

function Hookah.Create(tableId, ownerSrc, product, flavors)
    local spot = freeSpot(tableId)
    if not spot then
        Logger.Warn('hookah', ('No free hookah spot at table %s for %s'):format(tostring(tableId), product.id))
        return nil
    end
    nextId = nextId + 1
    local session = {
        id = nextId,
        tableId = tableId,
        spot = spot,
        typeId = product.id,
        label = product.label,
        prop = product.prop,
        flavors = flavors,
        flavorLabels = Catalog.FlavorLabels(flavors),
        owner = ownerSrc,
        startedAt = now(),
        expiresAt = now() + product.duration,
        refreshes = 0,
        activeUser = nil,
        activeUntil = 0,
    }
    Hookah.sessions[session.id] = session
    Logger.Info('hookah', ('Hookah #%d (%s) served to table %s'):format(session.id, product.id, tostring(tableId)), { flavors = table.concat(flavors, ',') })
    Sync.Hookahs(tableId)
    return session
end

local function remove(session, reason)
    Hookah.sessions[session.id] = nil
    Logger.Info('hookah', ('Hookah #%d removed (%s)'):format(session.id, reason or '-'), { table = session.tableId })
    Sync.Hookahs(session.tableId)
end

-- Validates that `src` may act on the session.
local function access(src, sessionId, needSeat)
    local session = Hookah.sessions[Utils.ToInt(sessionId) or -1]
    if not session then return nil, 'hookah_not_found' end
    if now() >= session.expiresAt then return nil, 'hookah_not_found' end
    local t, member = Tables.Of(src)
    if not t or t.id ~= session.tableId then return nil, 'hookah_not_yours' end
    if needSeat and cfg().requireSeated and not member.seat then return nil, 'not_seated' end
    if not Security.IsNear(src, t.center, Config.TableSettings.interactRadius + 2.0) then return nil, 'too_far' end
    return session, nil, t
end

function Hookah.Use(src, sessionId)
    local session, err = access(src, sessionId, true)
    if not session then return false, err end
    local current = now()
    if session.activeUser and session.activeUser ~= src and current < session.activeUntil then
        return false, 'hookah_in_use'
    end
    local duration = cfg().useDuration or 7
    local last = lastPuff[src]
    if last and current - last < duration + (cfg().puffCooldown or 3) then
        return false, 'hookah_cooldown'
    end
    lastPuff[src] = current
    session.activeUser = src
    session.activeUntil = current + duration
    TriggerClientEvent('cyphercity-hookah:client:hookahSmoke', src, session.id, duration * 1000)
    TriggerClientEvent('cyphercity-hookah:client:hookahPuff', -1, src, session.tableId)
    Sync.Hookahs(session.tableId)
    return true
end

function Hookah.Release(src, sessionId)
    local session = Hookah.sessions[Utils.ToInt(sessionId) or -1]
    if session and session.activeUser == src then
        session.activeUser = nil
        session.activeUntil = 0
        Sync.Hookahs(session.tableId)
    end
    return true
end

function Hookah.ReleaseUser(src)
    for _, session in pairs(Hookah.sessions) do
        if session.activeUser == src then
            session.activeUser = nil
            session.activeUntil = 0
            Sync.Hookahs(session.tableId)
        end
    end
end

function Hookah.ChangeFlavor(src, sessionId, flavors, account)
    local settings = cfg().flavorChange or {}
    if not settings.enabled then return false, 'hookah_feature_disabled' end
    local session, err, t = access(src, sessionId, false)
    if not session then return false, err end
    local product = Catalog.Get(session.typeId)
    if not product then return false, 'hookah_not_found' end
    local clean, flavorErr = Catalog.ValidateFlavors(product, flavors)
    if not clean then return false, flavorErr end

    local labels = Catalog.FlavorLabels(clean)
    local price = (settings.price or 0)
    for _, flavorId in ipairs(clean) do price = price + Catalog.flavorById[flavorId].price end
    local ok, code = Orders.CreateServiceCharge(src, t, L('hookah_flavor_change_line', table.concat(labels, ' + ')), price, account)
    if not ok then return false, code end

    session.flavors = clean
    session.flavorLabels = labels
    if settings.refreshDuration then
        session.expiresAt = now() + product.duration
    end
    Logger.Info('hookah', ('Hookah #%d flavour changed to %s by %s'):format(session.id, table.concat(clean, ','), Security.Describe(src)))
    Sync.Hookahs(session.tableId)
    return true, L('hookah_flavor_changed', table.concat(labels, ' + '))
end

function Hookah.RefreshCoals(src, sessionId, account)
    local settings = cfg().coalRefresh or {}
    if not settings.enabled then return false, 'hookah_feature_disabled' end
    local session, err, t = access(src, sessionId, false)
    if not session then return false, err end
    if session.refreshes >= (settings.maxRefreshes or 3) then return false, 'hookah_max_refresh' end
    local ok, code = Orders.CreateServiceCharge(src, t, L('hookah_coal_line'), settings.price or 0, account)
    if not ok then return false, code end
    session.refreshes = session.refreshes + 1
    session.expiresAt = session.expiresAt + (settings.extendSeconds or 600)
    Sync.Hookahs(session.tableId)
    return true, L('hookah_coals_refreshed')
end

function Hookah.End(src, sessionId)
    local session, err, t = access(src, sessionId, false)
    if not session then return false, err end
    if session.owner ~= src and t.owner ~= src then return false, 'not_table_owner' end
    remove(session, 'ended_by_' .. tostring(src))
    return true, L('hookah_ended')
end

function Hookah.RemoveByTable(tableId, reason)
    for _, session in pairs(Hookah.sessions) do
        if session.tableId == tableId then remove(session, reason) end
    end
end

function Hookah.Tick()
    local current = now()
    for _, session in pairs(Hookah.sessions) do
        if current >= session.expiresAt then
            for _, src in ipairs(Tables.MemberIds(session.tableId)) do
                Notify.Player(src, L('hookah_expired', (Tables.Get(session.tableId) or {}).label or ''), 'info')
            end
            remove(session, 'expired')
        elseif session.activeUser and current >= session.activeUntil then
            session.activeUser = nil
            session.activeUntil = 0
            Sync.Hookahs(session.tableId)
        end
    end
end

function Hookah.OnDropped(src)
    lastPuff[src] = nil
    Hookah.ReleaseUser(src)
end

function Hookah.View(session)
    local current = now()
    return {
        id = session.id,
        tableId = session.tableId,
        spot = session.spot,
        typeId = session.typeId,
        label = session.label,
        prop = session.prop,
        flavors = session.flavors,
        flavorLabels = session.flavorLabels,
        remaining = math.max(0, session.expiresAt - current),
        total = math.max(1, session.expiresAt - session.startedAt),
        refreshes = session.refreshes,
        activeUser = (session.activeUser and current < session.activeUntil) and session.activeUser or nil,
        owner = session.owner,
    }
end

function Hookah.PublicState()
    local list = {}
    for _, session in pairs(Hookah.sessions) do
        list[#list + 1] = Hookah.View(session)
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end
