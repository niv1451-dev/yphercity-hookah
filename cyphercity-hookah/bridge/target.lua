-- Interaction bridge (client only): ox_target, qb-target or a built-in
-- standalone mode (walk up → "[E]" prompt drawn in NUI → context menu when a
-- spot has several options). Options use one generic format:
--   { name, label, icon, distance, canInteract = function() return bool end, onSelect = function() end }

Target = {
    mode = 'standalone',
    active = false,
    contextOptions = nil,
}

local points = {}       -- standalone registry
local pointId = 0
local promptKey = nil
local INTERACT_KEY = 38 -- INPUT_PICKUP (E)

local function canUse(option)
    if option.canInteract == nil then return true end
    local ok, result = pcall(option.canInteract)
    return ok and result == true
end

local function maxDistance(options, fallback)
    local best = fallback or 2.0
    for _, option in ipairs(options) do
        if option.distance and option.distance > best then best = option.distance end
    end
    return best
end

local function runOption(option)
    CreateThread(function()
        local ok, err = pcall(option.onSelect)
        if not ok then print(('^1[cyphercity-hookah]^7 interaction "%s" failed: %s'):format(option.name or '?', tostring(err))) end
    end)
end

-- ox_target -------------------------------------------------------------------
local function oxOptions(options)
    local list = {}
    for _, option in ipairs(options) do
        list[#list + 1] = {
            name = option.name,
            label = option.label,
            icon = option.icon,
            distance = option.distance or 2.0,
            canInteract = function() return canUse(option) end,
            onSelect = function() runOption(option) end,
        }
    end
    return list
end

local function optionNames(options)
    local names = {}
    for _, option in ipairs(options) do names[#names + 1] = option.name end
    return names
end

-- qb-target -------------------------------------------------------------------
local function qbOptions(options)
    local list = {}
    for _, option in ipairs(options) do
        list[#list + 1] = {
            icon = option.icon,
            label = option.label,
            canInteract = function() return canUse(option) end,
            action = function() runOption(option) end,
        }
    end
    return list
end

local function optionLabels(options)
    local labels = {}
    for _, option in ipairs(options) do labels[#labels + 1] = option.label end
    return labels
end

-- API -------------------------------------------------------------------------
function Target.Init(mode)
    Target.mode = mode or 'standalone'
end

function Target.AddEntity(entity, options)
    if Target.mode == 'ox_target' then
        exports[Bridge.ResourceName('ox_target')]:addLocalEntity(entity, oxOptions(options))
        return { kind = 'entity', entity = entity, options = options }
    elseif Target.mode == 'qb-target' then
        exports[Bridge.ResourceName('qb_target')]:AddTargetEntity(entity, {
            options = qbOptions(options),
            distance = maxDistance(options),
        })
        return { kind = 'entity', entity = entity, options = options }
    end
    pointId = pointId + 1
    points[pointId] = { entity = entity, options = options, range = maxDistance(options) }
    return { kind = 'entity', entity = entity, options = options, id = pointId }
end

function Target.AddZone(name, coords, radius, options)
    if Target.mode == 'ox_target' then
        local id = exports[Bridge.ResourceName('ox_target')]:addSphereZone({
            coords = coords,
            radius = radius,
            debug = Config.Debug,
            name = name,
            options = oxOptions(options),
        })
        return { kind = 'zone', zoneId = id, name = name }
    elseif Target.mode == 'qb-target' then
        exports[Bridge.ResourceName('qb_target')]:AddCircleZone(name, coords, radius, {
            name = name,
            debugPoly = Config.Debug,
            useZ = true,
        }, {
            options = qbOptions(options),
            distance = maxDistance(options, radius),
        })
        return { kind = 'zone', name = name }
    end
    pointId = pointId + 1
    points[pointId] = { coords = coords, options = options, range = radius }
    return { kind = 'zone', name = name, id = pointId }
end

function Target.Remove(handle)
    if not handle then return end
    if handle.id then
        points[handle.id] = nil
        return
    end
    local ok, err = pcall(function()
        if handle.kind == 'entity' then
            if Target.mode == 'ox_target' then
                exports[Bridge.ResourceName('ox_target')]:removeLocalEntity(handle.entity, optionNames(handle.options))
            elseif Target.mode == 'qb-target' then
                exports[Bridge.ResourceName('qb_target')]:RemoveTargetEntity(handle.entity, optionLabels(handle.options))
            end
        elseif handle.kind == 'zone' then
            if Target.mode == 'ox_target' then
                exports[Bridge.ResourceName('ox_target')]:removeZone(handle.zoneId, true)
            elseif Target.mode == 'qb-target' then
                exports[Bridge.ResourceName('qb_target')]:RemoveZone(handle.name)
            end
        end
    end)
    if not ok and Config.Debug then
        print(('^3[cyphercity-hookah]^7 target removal failed: %s'):format(tostring(err)))
    end
end

-- Standalone prompt loop ---------------------------------------------------------
local function setPrompt(key, label, count)
    if key == promptKey then return end
    promptKey = key
    if key then
        SendNUIMessage({ action = 'prompt', data = { show = true, key = 'E', label = label, more = count > 1 } })
    else
        SendNUIMessage({ action = 'prompt', data = { show = false } })
    end
end

function Target.SetActive(active)
    Target.active = active
    if not active then setPrompt(nil) end
end

function Target.OpenContext(options)
    Target.contextOptions = options
    local list = {}
    for index, option in ipairs(options) do
        list[#list + 1] = { index = index, label = option.label, name = option.name }
    end
    setPrompt(nil)
    UI.OpenContext(list)
end

function Target.SelectContext(index)
    local options = Target.contextOptions
    Target.contextOptions = nil
    local option = options and options[index]
    if option and canUse(option) then runOption(option) end
end

CreateThread(function()
    while true do
        local sleep = 600
        if Target.mode == 'standalone' and Target.active and not UI.IsOpen() then
            local ped = PlayerPedId()
            local position = GetEntityCoords(ped)
            local best, bestDistance, bestOptions, bestId
            for id, point in pairs(points) do
                local coords = point.coords
                if point.entity then
                    coords = DoesEntityExist(point.entity) and GetEntityCoords(point.entity) or nil
                end
                if coords then
                    local distance = #(position - coords)
                    if distance < 12.0 and sleep > 150 then sleep = 150 end
                    if distance <= point.range and (not bestDistance or distance < bestDistance) then
                        local available = {}
                        for _, option in ipairs(point.options) do
                            if (not option.distance or distance <= option.distance + 0.25) and canUse(option) then
                                available[#available + 1] = option
                            end
                        end
                        if #available > 0 then
                            best, bestDistance, bestOptions, bestId = point, distance, available, id
                        end
                    end
                end
            end

            if best then
                sleep = 0
                local label = #bestOptions == 1 and bestOptions[1].label or L('prompt_more_options')
                setPrompt(bestId .. ':' .. #bestOptions .. ':' .. label, label, #bestOptions)
                if IsControlJustReleased(0, INTERACT_KEY) then
                    if #bestOptions == 1 then
                        runOption(bestOptions[1])
                    else
                        Target.OpenContext(bestOptions)
                    end
                    setPrompt(nil)
                end
            else
                setPrompt(nil)
            end
        elseif promptKey then
            setPrompt(nil)
        end
        Wait(sleep)
    end
end)
