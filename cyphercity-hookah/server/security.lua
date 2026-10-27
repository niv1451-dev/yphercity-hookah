-- Server-side protections: rate limiting, replay protection, distance checks
-- and logging of suspicious requests. Nothing a client sends is trusted.

Security = {
    oneSync = true,
}

local hits = {}         -- [src][key] = { timestamps }
local violations = {}   -- [src] = count
local recentRequests = {} -- [src] = { list = {}, set = {} }
local flaggedRate = {}  -- [src][key] = last flag time (avoid log spam)

function Security.Init()
    local mode = GetConvar('onesync', 'off')
    Security.oneSync = mode ~= 'off' and mode ~= 'false'
    if not Security.oneSync then
        Bridge.Print('warn', 'OneSync is OFF: server-side distance checks are disabled. Enable OneSync (txAdmin → Settings → FXServer) for full protection.')
    end
end

function Security.RateLimit(src, key)
    local rules = Config.Security.rateLimits
    local rule = rules[key] or rules.default
    local now = GetGameTimer()
    local window = rule.window * 1000

    hits[src] = hits[src] or {}
    local list = hits[src][key]
    if not list then
        list = {}
        hits[src][key] = list
    end
    while list[1] and now - list[1] > window do
        table.remove(list, 1)
    end
    if #list >= rule.limit then
        flaggedRate[src] = flaggedRate[src] or {}
        local last = flaggedRate[src][key]
        if not last or now - last > window then
            flaggedRate[src][key] = now
            Logger.Warn('security', ('Rate limit hit: %s (%s)'):format(key, Security.Describe(src)), { player = src, action = key })
        end
        return false
    end
    list[#list + 1] = now
    return true
end

-- Replay protection for requests that carry a client-generated id (orders).
function Security.CheckRequestId(src, requestId)
    if type(requestId) ~= 'string' or #requestId < 6 or #requestId > 64 then return false end
    local entry = recentRequests[src]
    if not entry then
        entry = { list = {}, set = {} }
        recentRequests[src] = entry
    end
    if entry.set[requestId] then return false end
    entry.set[requestId] = true
    entry.list[#entry.list + 1] = requestId
    if #entry.list > 40 then
        local old = table.remove(entry.list, 1)
        entry.set[old] = nil
    end
    return true
end

function Security.Describe(src)
    local name = GetPlayerName(src) or '?'
    return ('%s [%s]'):format(name, tostring(src))
end

-- Records a suspicious / unauthorised attempt. Optional automatic kick.
function Security.Flag(src, reason, data)
    violations[src] = (violations[src] or 0) + 1
    local details = data or {}
    details.player = src
    details.identifier = Framework.name and Framework.GetIdentifier(src) or nil
    details.violations = violations[src]
    Logger.Warn('security', ('Unauthorised / invalid action "%s" by %s'):format(reason, Security.Describe(src)), details)

    local limit = Config.Security.violationsBeforeKick or 0
    if limit > 0 and violations[src] >= limit then
        Logger.Warn('security', ('Dropping %s after %d violations'):format(Security.Describe(src), violations[src]))
        DropPlayer(src, 'CypherCity Hookah: too many invalid requests')
    end
end

function Security.GetCoords(src)
    if not Security.oneSync then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

-- True when the player is within `distance` (+ tolerance) of `coords`.
-- Without OneSync the server cannot see positions, so the check is skipped.
function Security.IsNear(src, coords, distance)
    if not Security.oneSync then return true end
    local position = Security.GetCoords(src)
    if not position then return false end
    return Utils.WithinRange(position, coords, distance + (Config.Security.interactTolerance or 3.0), 8.0)
end

function Security.InVenue(src)
    return Security.IsNear(src, Config.Venue.center, Config.Venue.radius)
end

function Security.DistanceBetweenPlayers(a, b)
    if not Security.oneSync then return 0 end
    local pa, pb = Security.GetCoords(a), Security.GetCoords(b)
    if not pa or not pb then return math.huge end
    return #(pa - pb)
end

function Security.OnDropped(src)
    hits[src] = nil
    violations[src] = nil
    recentRequests[src] = nil
    flaggedRate[src] = nil
end
