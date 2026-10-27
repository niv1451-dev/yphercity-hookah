-- NUI bridge: opens/closes panels, owns NUI focus and forwards NUI requests to
-- the server. The NUI is display only — every action is validated server-side.

UI = {
    open = false,
    panel = nil,
    ready = false,
    contextOpen = false,
}

function UI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function UI.IsOpen()
    return UI.open or UI.contextOpen
end

-- Adds a localized message to failed (and some successful) server responses.
function UI.Decorate(result)
    if type(result) ~= 'table' then
        return { ok = false, code = 'internal_error', message = L('internal_error') }
    end
    if not result.ok and not result.message then
        result.message = L(result.code or 'internal_error', table.unpack(result.args or {}))
    end
    return result
end

function UI.SendInit()
    if not UI.ready or not State.bootstrapped then return end
    UI.Send('init', {
        locale = Config.Locale,
        currency = Config.Currency,
        business = { name = Config.Business.name, label = Config.Business.label, hostess = Config.Hostess.name },
        catalog = State.catalog,
        settings = State.settings,
        tables = State.tables,
        me = State.me,
        debug = Config.Debug,
    })
end

function UI.Open(panel, context)
    if not State.bootstrapped then
        Client.Bootstrap()
        if not State.bootstrapped then
            Notify.Send(L('not_ready'), 'error')
            return
        end
    end
    UI.open = true
    UI.contextOpen = false
    UI.panel = panel
    SetNuiFocus(true, true)
    UI.Send('open', { panel = panel, context = context or {}, me = State.me, tables = State.tables })
end

function UI.Close()
    if UI.panel == 'staff' then
        CreateThread(function() Callback.Await('staffClose', {}) end)
    end
    UI.open = false
    UI.contextOpen = false
    UI.panel = nil
    SetNuiFocus(false, false)
    UI.Send('close')
end

function UI.OpenContext(options)
    UI.contextOpen = true
    SetNuiFocus(true, true)
    UI.Send('context', { options = options })
end

RegisterNUICallback('ready', function(_, cb)
    UI.ready = true
    cb({ ok = true })
    UI.SendInit()
end)

RegisterNUICallback('close', function(_, cb)
    UI.Close()
    cb({ ok = true })
end)

RegisterNUICallback('switchPanel', function(data, cb)
    if type(data) == 'table' and type(data.panel) == 'string' then
        if UI.panel == 'staff' and data.panel ~= 'staff' then
            CreateThread(function() Callback.Await('staffClose', {}) end)
        end
        UI.panel = data.panel
    end
    cb({ ok = true })
end)

RegisterNUICallback('contextSelect', function(data, cb)
    UI.contextOpen = false
    if not UI.open then SetNuiFocus(false, false) end
    cb({ ok = true })
    Target.SelectContext(type(data) == 'table' and tonumber(data.index) or nil)
end)

RegisterNUICallback('contextClose', function(_, cb)
    UI.contextOpen = false
    Target.contextOptions = nil
    if not UI.open then SetNuiFocus(false, false) end
    cb({ ok = true })
end)

RegisterNUICallback('copyDone', function(_, cb)
    cb({ ok = true })
end)

-- Requests forwarded as-is to the server (the server validates everything).
local FORWARD = {
    'getState', 'requestTable', 'leaveTable', 'nearbyPlayers', 'invite',
    'placeOrder', 'cancelOrder', 'getBill', 'pay', 'consume', 'callWaiter',
    'staffAction',
}

for _, name in ipairs(FORWARD) do
    RegisterNUICallback(name, function(data, cb)
        local result = UI.Decorate(Callback.Await(name, type(data) == 'table' and data or {}))
        cb(result)
        if name == 'leaveTable' and result.ok then Seat.StandLocal() end
        if name == 'consume' and result.ok then UI.Close() end
    end)
end

RegisterNUICallback('staffOpen', function(_, cb)
    local result = UI.Decorate(Callback.Await('staffOpen', {}))
    if result.ok then
        State.staff = result.data
        UI.panel = 'staff'
    end
    cb(result)
end)

RegisterNUICallback('hookahAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local result = UI.Decorate(Callback.Await('hookahAction', data))
    cb(result)
    if result.ok and data.action == 'use' then UI.Close() end
end)

-- The menu "sit" button: walks the player through the same flow as the target.
RegisterNUICallback('sit', function(data, cb)
    data = type(data) == 'table' and data or {}
    cb({ ok = true })
    UI.Close()
    Seat.RequestSit(tonumber(data.tableId))
end)
