-- Staff roles and permissions. Roles are resolved on the server from (in order):
-- ACE permissions, ServerConfig.StaffIdentifiers, then the framework job + grade.
-- A client can never grant itself a role: every staff action re-checks here.

Staff = {}

local ROLE_ORDER = { 'manager', 'cashier', 'waiter', 'host' }
local permissionSets = {}
local dutyCache = { at = 0, count = 0 }

function Staff.Init()
    permissionSets = {}
    for role, list in pairs(Config.Staff.permissions or {}) do
        local set = {}
        for _, perm in ipairs(list) do set[perm] = true end
        permissionSets[role] = set
    end
end

local function roleFromGrade(grade)
    local roles = Config.Staff.gradeRoles or {}
    if roles[grade] then return roles[grade] end
    local bestGrade
    for g in pairs(roles) do
        if g <= grade and (not bestGrade or g > bestGrade) then bestGrade = g end
    end
    return bestGrade and roles[bestGrade] or nil
end

local function roleFromIdentifiers(src)
    local list = ServerConfig.StaffIdentifiers or {}
    if not next(list) then return nil end
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        if list[identifier] then return list[identifier] end
    end
    return nil
end

-- Returns role name or nil (+ reason when the player has the job but is off duty).
function Staff.GetRole(src)
    if not src or src <= 0 then return nil end
    for _, role in ipairs(ROLE_ORDER) do
        local ace = (Config.Staff.ace or {})[role]
        if ace and IsPlayerAceAllowed(src, ace) then return role end
    end

    local byIdentifier = roleFromIdentifiers(src)
    if byIdentifier and permissionSets[byIdentifier] then return byIdentifier end

    local job = Framework.GetJob(src)
    if not job or job.name ~= Config.Business.job then return nil end
    if Config.Staff.requireOnDuty and job.onDuty == false then return nil, 'off_duty' end
    if Config.Staff.bossIsManager and job.isBoss then return 'manager' end
    return roleFromGrade(job.grade)
end

function Staff.RoleHas(role, permission)
    local set = role and permissionSets[role]
    if not set then return false end
    return set['*'] == true or set[permission] == true
end

function Staff.Can(src, permission)
    return Staff.RoleHas(Staff.GetRole(src), permission)
end

local ALL_PERMISSIONS = {
    'view_tables', 'reserve_table', 'clean_table', 'seat_guest', 'release_table',
    'view_orders', 'update_order', 'cancel_order', 'request_payment',
    'view_sales', 'manage_stock', 'toggle_business', 'view_logs',
}

function Staff.PermissionList(role)
    local list = {}
    for _, perm in ipairs(ALL_PERMISSIONS) do
        if Staff.RoleHas(role, perm) then list[#list + 1] = perm end
    end
    return list
end

-- Checks a permission and records the attempt when it fails.
function Staff.Require(src, permission)
    if Staff.Can(src, permission) then return true end
    Security.Flag(src, 'staff_permission_denied', { permission = permission })
    return false
end

function Staff.OnlineStaff()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local role = src and Staff.GetRole(src)
        if role then list[#list + 1] = { src = src, role = role } end
    end
    return list
end

-- Cached for a few seconds because the order loop asks every second.
function Staff.OnDutyCount()
    local now = GetGameTimer()
    if now - dutyCache.at > 5000 then
        local count = 0
        for _, member in ipairs(Staff.OnlineStaff()) do
            if Staff.RoleHas(member.role, 'update_order') then count = count + 1 end
        end
        dutyCache = { at = now, count = count }
    end
    return dutyCache.count
end

function Staff.InvalidateCache()
    dutyCache.at = 0
end

function Staff.NotifyAll(permission, message, kind)
    for _, member in ipairs(Staff.OnlineStaff()) do
        if Staff.RoleHas(member.role, permission) then
            Notify.Player(member.src, message, kind or 'info')
        end
    end
end
