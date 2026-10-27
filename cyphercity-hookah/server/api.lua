-- Every client → server request goes through these callbacks. Each one checks
-- types, distance, permissions and state on the server; the bridge already
-- applied rate limiting before the handler runs.

local function fail(code, ...)
    return { ok = false, code = code or 'internal_error', args = { ... } }
end

local function success(data, message)
    return { ok = true, data = data, message = message }
end

local function reserveSeconds()
    return Config.TableSettings.reserveTimeout or 180
end

local function accountList()
    local list = {}
    for _, account in ipairs(Config.Payments.accounts or {}) do
        list[#list + 1] = { id = account, label = L('account_' .. account) }
    end
    return list
end

-- Customer ------------------------------------------------------------------------

Callback.Register('bootstrap', function(src)
    return success({
        catalog = Catalog.ForNui(),
        settings = {
            framework = Bridge.framework,
            moneyMode = Payments.MoneyMode(),
            standaloneFallback = Server.standaloneFallback,
            timing = Config.Payments.timing,
            accounts = accountList(),
            tips = (Config.Payments.tips and Config.Payments.tips.enabled) and Config.Payments.tips.options or { 0 },
            servicePercent = Config.Payments.serviceChargePercent or 0,
            allowTableBill = Config.Payments.allowTableBill,
            tableBillPayer = Config.Payments.tableBillPayer,
            maxPartySize = Config.TableSettings.maxPartySize or 6,
            hookahRequireSeated = Config.Hookah.requireSeated ~= false,
            allowWithoutTable = Config.Orders.allowWithoutTable == true,
            maxQtyPerLine = Config.Orders.maxQtyPerLine,
            maxItemsPerOrder = Config.Orders.maxItemsPerOrder,
            ordersMode = Config.Orders.mode,
            flavorChange = Config.Hookah.flavorChange,
            coalRefresh = Config.Hookah.coalRefresh,
            stockEnabled = Config.Stock.enabled,
        },
        tables = Tables.PublicList(),
        hookahs = Hookah.PublicState(),
        me = Sync.BuildPlayerState(src),
        layout = Setup.Payload(),
    })
end, 'getState')

Callback.Register('getState', function(src)
    return success(Sync.BuildPlayerState(src))
end)

Callback.Register('requestTable', function(src, payload)
    local ok, code = Business.CanServe(src)
    if not ok then return fail(code) end
    if not Security.IsNear(src, Config.Hostess.coords, Config.Hostess.interactDistance or 2.0) then return fail('too_far') end
    local assigned, result, arg = Tables.RequestTable(src, payload.partySize)
    if not assigned then return fail(result, arg) end
    return success(
        { tableId = result.id, label = result.label, holdFor = reserveSeconds() },
        L('table_assigned', result.label, Utils.FormatDuration(reserveSeconds()))
    )
end)

Callback.Register('sit', function(src, payload)
    local t = Tables.Get(payload.tableId)
    if not t then return fail('table_not_found') end
    local current = Tables.Of(src)
    if not current then
        local ok, code = Business.CanServe(src)
        if not ok then return fail(code) end
    end
    if not Security.IsNear(src, t.center, Config.TableSettings.interactRadius or 1.8) then return fail('too_far') end
    local seated, seat, arg = Tables.Sit(src, t.id)
    if not seated then return fail(seat, arg) end
    return success({ tableId = t.id, seat = seat }, L('sat_down', t.label))
end)

Callback.Register('stand', function(src)
    local ok, code = Tables.Stand(src)
    if not ok then return fail(code) end
    return success()
end, 'sit')

Callback.Register('leaveTable', function(src)
    local ok, result, arg = Tables.Leave(src)
    if not ok then return fail(result, arg) end
    return success(nil, L('left_table', result.label))
end, 'sit')

Callback.Register('nearbyPlayers', function(src)
    local t = Tables.Of(src)
    if not (t and t.owner == src) and not Staff.Can(src, 'seat_guest') then return fail('not_table_owner') end
    return success(Tables.NearbyPlayers(src))
end, 'invite')

Callback.Register('invite', function(src, payload)
    local ok, result = Tables.Invite(src, payload.target)
    if not ok then return fail(result) end
    return success(nil, L('invite_sent', result))
end)

Callback.Register('placeOrder', function(src, payload)
    local ok, result, arg1, arg2 = Orders.Create(src, payload)
    if not ok then return fail(result, arg1, arg2) end
    local paid = result.paymentStatus == 'paid'
    return success(
        { id = result.id, total = result.subtotal, paid = paid },
        L(paid and 'order_placed_paid' or 'order_placed', result.id, Utils.FormatMoney(result.subtotal))
    )
end)

Callback.Register('cancelOrder', function(src, payload)
    local ok, code = Orders.CustomerCancel(src, payload.orderId)
    if not ok then return fail(code) end
    return success()
end)

Callback.Register('getBill', function(src, payload)
    local ok, result = Payments.GetBill(src, payload)
    if not ok then return fail(result) end
    return success(result)
end)

Callback.Register('pay', function(src, payload)
    local ok, result, arg = Payments.Pay(src, payload)
    if not ok then return fail(result, arg) end
    local message = result.free and L('payment_success_free') or L('payment_success', Utils.FormatMoney(result.total))
    return success(result, message)
end)

Callback.Register('consume', function(src, payload)
    local ok, code = Orders.Consume(src, payload.itemId)
    if not ok then return fail(code) end
    return success()
end)

local HOOKAH_ACTIONS = {
    use = function(src, payload) return Hookah.Use(src, payload.sessionId) end,
    release = function(src, payload) return Hookah.Release(src, payload.sessionId) end,
    flavor = function(src, payload) return Hookah.ChangeFlavor(src, payload.sessionId, payload.flavors, payload.account) end,
    coals = function(src, payload) return Hookah.RefreshCoals(src, payload.sessionId, payload.account) end,
    ['end'] = function(src, payload) return Hookah.End(src, payload.sessionId) end,
}

Callback.Register('hookahAction', function(src, payload)
    local handler = HOOKAH_ACTIONS[payload.action]
    if not handler then return fail('invalid_request') end
    local ok, result, arg = handler(src, payload)
    if not ok then return fail(result, arg) end
    return success(nil, type(result) == 'string' and result or nil)
end)

Callback.Register('callWaiter', function(src)
    local t = Tables.Of(src)
    if not t then return fail('no_table') end
    if not Security.IsNear(src, t.center, Config.Venue.radius) then return fail('too_far') end
    Staff.NotifyAll('view_orders', L('staff_waiter_call', t.label), 'info')
    TriggerClientEvent('cyphercity-hookah:client:waiterServe', -1, t.id)
    Logger.Info('table', ('%s called a waiter to %s'):format(Security.Describe(src), t.label), { table = t.id })
    return success(nil, L('waiter_called'))
end)

-- Staff ------------------------------------------------------------------------------

local function staffGate(src)
    local role, reason = Staff.GetRole(src)
    if not role then
        if reason == 'off_duty' then return nil, fail('off_duty') end
        Security.Flag(src, 'staff_panel_denied')
        return nil, fail('no_permission')
    end
    if Config.Staff.panelRequiresVenue and not Security.InVenue(src) then
        return nil, fail('staff_panel_not_in_venue')
    end
    return role
end

Callback.Register('staffOpen', function(src)
    local role, err = staffGate(src)
    if not role then return err end
    Sync.Subscribe(src)
    return success(Sync.BuildStaffState(src))
end, 'staffAction')

Callback.Register('staffClose', function(src)
    Sync.Unsubscribe(src)
    return success()
end, 'staffAction')

local STAFF_ACTIONS = {
    orderStatus = function(src, payload)
        return Orders.StaffSetStatus(src, payload.orderId, payload.status)
    end,
    order = function(src, payload)
        return Orders.CreateForTable(src, payload)
    end,
    orderCancel = function(src, payload)
        return Orders.StaffCancel(src, payload.orderId, payload.reason)
    end,
    table = function(src, payload)
        return Tables.StaffAction(src, payload.tableId, payload.op, { name = payload.name, target = payload.target })
    end,
    business = function(src, payload)
        return Business.SetOpen(src, payload.open)
    end,
    restock = function(src, payload)
        return Orders.Restock(src, payload.productId)
    end,
    requestPayment = function(src, payload)
        return Payments.RequestPayment(src, payload.tableId)
    end,
    sales = function(src)
        if not Staff.Require(src, 'view_sales') then return false, 'no_permission' end
        return true, Persistence.Report(7)
    end,
    logs = function(src, payload)
        if not Staff.Require(src, 'view_logs') then return false, 'no_permission' end
        local category = type(payload.category) == 'string' and payload.category or nil
        return true, Logger.Recent(80, category)
    end,
    nearby = function(src)
        if not Staff.Require(src, 'seat_guest') then return false, 'no_permission' end
        return true, Tables.NearbyPlayers(src)
    end,
}

Callback.Register('staffAction', function(src, payload)
    local role, err = staffGate(src)
    if not role then return err end
    local handler = STAFF_ACTIONS[payload.action]
    if not handler then return fail('invalid_request') end
    local ok, result, arg = handler(src, payload)
    if not ok then return fail(result, arg) end
    Sync.Staff()
    if type(result) == 'string' then return success(nil, result) end
    return success(result)
end)

Callback.Register('devAllowed', function(src)
    return success({ allowed = Config.Debug == true or Setup.IsAdmin(src) })
end, 'getState')
