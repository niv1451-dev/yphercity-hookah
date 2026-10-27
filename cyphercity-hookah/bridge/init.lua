-- Bridge core: resource detection shared by client and server.
-- Each adapter (framework, inventory, target, notifications, banking) decides
-- what to use through these helpers. Nothing here guesses an API: adapters only
-- run code for a system after confirming its resource is actually started.

Bridge = {
    framework = nil,    -- 'esx' | 'qbcore' | 'qbox' | 'standalone'
    inventory = nil,    -- 'none' | 'ox_inventory' | 'qb-inventory' | 'esx'
    target = nil,       -- 'ox_target' | 'qb-target' | 'standalone'
    notify = nil,       -- 'ox_lib' | 'framework' | 'nui'
    ready = false,
    problems = {},
}

local IS_SERVER = IsDuplicityVersion()

function Bridge.ResourceName(key)
    return (Config.ResourceNames or {})[key] or key
end

function Bridge.State(key)
    return GetResourceState(Bridge.ResourceName(key))
end

function Bridge.IsStarted(key)
    return Bridge.State(key) == 'started'
end

-- "present" means the resource exists on this server even if it is still starting.
function Bridge.IsPresent(key)
    local state = Bridge.State(key)
    return state ~= 'missing' and state ~= 'unknown' and state ~= nil
end

-- Waits (up to `seconds`) for a resource that exists but has not finished starting.
function Bridge.WaitForStarted(key, seconds)
    local deadline = GetGameTimer() + (seconds or 15) * 1000
    while Bridge.State(key) ~= 'started' and GetGameTimer() < deadline do
        local state = Bridge.State(key)
        if state == 'missing' or state == 'stopped' then break end
        Wait(250)
    end
    return Bridge.State(key) == 'started'
end

function Bridge.AddProblem(message)
    Bridge.problems[#Bridge.problems + 1] = message
end

local FRAMEWORK_PRIORITY = { 'qbox', 'qbcore', 'esx' }

-- Resolves the framework to use. Qbox is checked first because qbx_core can also
-- expose a qb-core compatibility layer.
function Bridge.ResolveFramework()
    local wanted = Config.Framework or 'auto'
    if wanted ~= 'auto' then
        if wanted == 'standalone' then return 'standalone' end
        local key = wanted
        if not Bridge.IsPresent(key) then
            return nil, ('Config.Framework = "%s" but resource "%s" was not found on the server'):format(wanted, Bridge.ResourceName(key))
        end
        if not Bridge.WaitForStarted(key, Config.FrameworkWaitSeconds) then
            return nil, ('Resource "%s" exists but is not started (state: %s). Make sure it is ensured BEFORE cyphercity-hookah in server.cfg'):format(Bridge.ResourceName(key), Bridge.State(key))
        end
        return wanted
    end

    for _, key in ipairs(FRAMEWORK_PRIORITY) do
        if Bridge.IsPresent(key) then
            if Bridge.WaitForStarted(key, Config.FrameworkWaitSeconds) then
                return key
            end
            return nil, ('Framework resource "%s" exists but did not start (state: %s). Ensure it before cyphercity-hookah, or set Config.Framework manually'):format(Bridge.ResourceName(key), Bridge.State(key))
        end
    end
    return 'standalone', nil, true
end

function Bridge.ResolveTarget()
    local wanted = Config.Target or 'auto'
    if wanted == 'standalone' then return 'standalone' end
    if wanted ~= 'auto' then
        local key = wanted == 'qb-target' and 'qb_target' or wanted
        if Bridge.WaitForStarted(key, 10) then return wanted end
        Bridge.AddProblem(('Config.Target = "%s" but "%s" is not started — falling back to the built-in E-key interaction'):format(wanted, Bridge.ResourceName(key)))
        return 'standalone'
    end
    if Bridge.IsStarted('ox_target') then return 'ox_target' end
    if Bridge.IsStarted('qb_target') then return 'qb-target' end
    return 'standalone'
end

function Bridge.ResolveInventory()
    local wanted = Config.Inventory or 'none'
    if wanted == 'none' then return 'none' end
    if wanted == 'auto' then
        if Bridge.IsStarted('ox_inventory') then return 'ox_inventory' end
        if Bridge.IsStarted('qb_inventory') then return 'qb-inventory' end
        if Bridge.framework == 'esx' then return 'esx' end
        return 'none'
    end
    if wanted == 'esx' then
        if Bridge.framework == 'esx' then return 'esx' end
        Bridge.AddProblem('Config.Inventory = "esx" requires the ESX framework — using catalog-only mode')
        return 'none'
    end
    local key = wanted == 'qb-inventory' and 'qb_inventory' or wanted
    if Bridge.WaitForStarted(key, 10) then return wanted end
    Bridge.AddProblem(('Config.Inventory = "%s" but "%s" is not started — using catalog-only mode'):format(wanted, Bridge.ResourceName(key)))
    return 'none'
end

function Bridge.ResolveNotify()
    local wanted = Config.Notify or 'auto'
    if wanted == 'nui' then return 'nui' end
    if wanted == 'ox_lib' then
        if Bridge.IsStarted('ox_lib') then return 'ox_lib' end
        return 'nui'
    end
    if wanted == 'framework' then
        if Bridge.framework and Bridge.framework ~= 'standalone' then return 'framework' end
        return 'nui'
    end
    if Bridge.IsStarted('ox_lib') then return 'ox_lib' end
    if Bridge.framework and Bridge.framework ~= 'standalone' then return 'framework' end
    return 'nui'
end

function Bridge.Print(level, message)
    local colors = { info = '^5', warn = '^3', error = '^1', ok = '^2' }
    print(('%s[cyphercity-hookah]^7 %s'):format(colors[level] or '^7', message))
end

Bridge.IS_SERVER = IS_SERVER
