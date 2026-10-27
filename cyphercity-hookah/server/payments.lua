-- Bills and payments. Flow:
--   1. getBill  → the server collects the unpaid orders, prices them and issues a
--                 single-use token bound to that player and that exact bill.
--   2. pay      → the token is consumed immediately (replays fail), the bill is
--                 recomputed and must match, orders are locked as "processing",
--                 money is removed through the verified framework adapter, and only
--                 then are the orders marked paid. Any failure unlocks them unpaid.

Payments = {}

local tokens = {}   -- [token] = { src, mode, ids, subtotal, expiresAt }
local paying = {}   -- [src] = true while a charge is running
local counter = 0

local function now() return Utils.Now() end

-- 'money' = real framework money, 'free' = standalone without money (bills close
-- without a charge and are clearly marked), 'disabled' = ordering blocked.
function Payments.MoneyMode()
    if Framework.supportsMoney then return 'money' end
    if Config.Standalone.allowFreeOrders then return 'free' end
    return 'disabled'
end

function Payments.OrderingAllowed()
    return Payments.MoneyMode() ~= 'disabled'
end

local function validAccount(account)
    return type(account) == 'string' and Utils.Contains(Config.Payments.accounts or {}, account)
end

local function accountLabel(account)
    return L('account_' .. tostring(account))
end

local function newToken()
    counter = counter + 1
    return ('%08x%08x%06x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), counter % 0xffffff)
end

local function collect(src, mode)
    if mode == 'table' then
        if not Config.Payments.allowTableBill then return nil, 'invalid_request' end
        local t = Tables.Of(src)
        if not t then return nil, 'no_table' end
        if Config.Payments.tableBillPayer ~= 'any_member' and t.owner ~= src then
            return nil, 'not_table_payer'
        end
        return Orders.UnpaidForTable(t.id), t
    end
    return Orders.UnpaidFor(src), Tables.Of(src)
end

local function summarize(orders)
    local subtotal, ids = 0, {}
    for _, order in ipairs(orders) do
        subtotal = subtotal + order.subtotal
        ids[#ids + 1] = order.id
    end
    table.sort(ids)
    return subtotal, table.concat(ids, ',')
end

local function tipOptions()
    local tips = Config.Payments.tips or {}
    if not tips.enabled then return { 0 } end
    return tips.options or { 0 }
end

function Payments.GetBill(src, payload)
    local mode = payload.mode == 'table' and 'table' or 'personal'
    local orders, tOrCode = collect(src, mode)
    if not orders then return false, tOrCode end
    local t = tOrCode

    for token, entry in pairs(tokens) do
        if entry.src == src then tokens[token] = nil end
    end

    local moneyMode = Payments.MoneyMode()
    local bill = {
        mode = mode,
        tableLabel = t and t.label or nil,
        moneyMode = moneyMode,
        canPayTable = Config.Payments.allowTableBill and t ~= nil
            and (Config.Payments.tableBillPayer == 'any_member' or t.owner == src),
        servicePercent = Config.Payments.serviceChargePercent or 0,
        tips = tipOptions(),
        accounts = {},
        orders = {},
        subtotal = 0,
        service = 0,
        empty = #orders == 0,
    }
    for _, account in ipairs(Config.Payments.accounts or {}) do
        bill.accounts[#bill.accounts + 1] = { id = account, label = accountLabel(account), balance = Framework.GetBalance(src, account) }
    end
    if bill.empty then return true, bill end

    local subtotal, ids = summarize(orders)
    for _, order in ipairs(orders) do bill.orders[#bill.orders + 1] = Orders.View(order, src) end
    bill.subtotal = subtotal
    bill.service = Utils.Percent(subtotal, bill.servicePercent)

    local token = newToken()
    tokens[token] = { src = src, mode = mode, ids = ids, subtotal = subtotal, expiresAt = now() + (Config.Payments.tokenTTL or 120) }
    bill.token = token
    return true, bill
end

function Payments.Pay(src, payload)
    local token = payload.token
    if type(token) ~= 'string' or #token > 40 then return false, 'token_invalid' end
    local entry = tokens[token]
    if not entry then return false, 'token_invalid' end
    if entry.src ~= src then
        Security.Flag(src, 'payment_token_foreign')
        return false, 'token_invalid'
    end
    tokens[token] = nil -- single use
    if now() > entry.expiresAt then return false, 'token_invalid' end
    if paying[src] then return false, 'payment_in_progress' end

    local moneyMode = Payments.MoneyMode()
    if moneyMode == 'disabled' then return false, 'payments_disabled' end
    local account = payload.account
    if moneyMode == 'money' and not validAccount(account) then return false, 'account_invalid' end
    local tipPercent = Utils.ToInt(payload.tip) or 0
    if not Utils.Contains(tipOptions(), tipPercent) then return false, 'tip_invalid' end
    if not Security.InVenue(src) then return false, 'not_in_venue' end

    local orders, tOrCode = collect(src, entry.mode)
    if not orders then return false, tOrCode end
    if #orders == 0 then return false, 'nothing_to_pay' end
    local subtotal, ids = summarize(orders)
    if subtotal ~= entry.subtotal or ids ~= entry.ids then return false, 'bill_changed' end

    local service = Utils.Percent(subtotal, Config.Payments.serviceChargePercent or 0)
    local tip = Utils.Percent(subtotal, tipPercent)
    local total = subtotal + service + tip

    -- lock
    paying[src] = true
    for _, order in ipairs(orders) do order.paymentStatus = 'processing' end

    local ok, reason = true, nil
    if moneyMode == 'money' and total > 0 then
        ok, reason = Framework.RemoveMoney(src, account, total, 'cyphercity-hookah bill')
    end

    if not ok then
        for _, order in ipairs(orders) do order.paymentStatus = 'unpaid' end
        paying[src] = nil
        Logger.Warn('payment', ('Payment failed for %s: %s (%s)'):format(Security.Describe(src), Utils.FormatMoney(total), tostring(reason)), {
            player = src, amount = total, account = account, reason = reason,
        })
        for _, order in ipairs(orders) do Sync.Order(order) end
        if reason == 'insufficient_funds' then return false, 'insufficient_funds', accountLabel(account) end
        return false, 'payment_failed'
    end

    local paymentId = newToken()
    local identifier = Framework.GetIdentifier(src)
    -- service and tip are split across the orders so a later refund returns the right share
    local serviceLeft, tipLeft = service, tip
    for index, order in ipairs(orders) do
        local last = index == #orders
        local serviceShare = last and serviceLeft or (subtotal > 0 and math.floor(service * order.subtotal / subtotal) or 0)
        local tipShare = last and tipLeft or (subtotal > 0 and math.floor(tip * order.subtotal / subtotal) or 0)
        serviceLeft, tipLeft = serviceLeft - serviceShare, tipLeft - tipShare
        order.paymentStatus = 'paid'
        order.paidAt = now()
        order.paidBy = src
        order.paidByIdentifier = identifier
        order.paidAccount = moneyMode == 'money' and account or nil
        order.paidAmount = order.subtotal
        order.paidService = serviceShare
        order.paidTip = tipShare
        order.paymentId = paymentId
        order.free = moneyMode == 'free'
        order.updatedAt = now()
    end
    paying[src] = nil
    for _, order in ipairs(orders) do Orders.OnPaid(order) end

    local free = moneyMode == 'free'
    Persistence.RecordSale(orders, free and 0 or (subtotal + service), free and 0 or tip)
    if not free and total > 0 then Banking.Deposit(total, 'cyphercity-hookah bill') end

    Logger.Info('payment', ('%s paid %s (%s) for %d order(s) [%s]'):format(
        Security.Describe(src), Utils.FormatMoney(total), free and 'no charge' or accountLabel(account), #orders, entry.mode
    ), { player = src, amount = total, tip = tip, service = service, orders = ids, payment = paymentId })

    for _, order in ipairs(orders) do
        Sync.Order(order)
        if order.src ~= src and GetPlayerName(order.src) then Sync.Player(order.src) end
    end
    return true, {
        total = total, subtotal = subtotal, service = service, tip = tip,
        account = account, accountLabel = account and accountLabel(account) or nil,
        free = free, orders = #orders, paymentId = paymentId,
    }
end

-- Immediate charge used by "pay on order" and service charges.
-- Returns true, nil, nil, info — or false, code, arg.
function Payments.ChargeDirect(src, account, amount, reason)
    local moneyMode = Payments.MoneyMode()
    if moneyMode == 'disabled' then return false, 'payments_disabled' end
    amount = Utils.ToInt(amount) or 0
    if moneyMode == 'free' or amount <= 0 then
        return true, nil, nil, { id = newToken(), free = moneyMode == 'free' }
    end
    if not validAccount(account) then return false, 'account_invalid' end
    if paying[src] then return false, 'payment_in_progress' end

    paying[src] = true
    local ok, why = Framework.RemoveMoney(src, account, amount, 'cyphercity-hookah ' .. tostring(reason))
    paying[src] = nil
    if not ok then
        Logger.Warn('payment', ('Direct charge failed for %s: %s (%s)'):format(Security.Describe(src), Utils.FormatMoney(amount), tostring(why)), { player = src, amount = amount })
        if why == 'insufficient_funds' then return false, 'insufficient_funds', accountLabel(account) end
        return false, 'payment_failed'
    end
    Banking.Deposit(amount, 'cyphercity-hookah ' .. tostring(reason))
    Logger.Info('payment', ('%s paid %s (%s, %s)'):format(Security.Describe(src), Utils.FormatMoney(amount), accountLabel(account), tostring(reason)), { player = src, amount = amount })
    return true, nil, nil, { id = newToken(), free = false, account = account }
end

-- Refunds a paid order that was cancelled before being served (staff only).
-- The payer gets back the order price plus its share of service and tip; the
-- sale is removed from the stats and taken back out of the society account.
-- Returns the refunded amount (0 when nothing was charged or the payer is offline).
function Payments.Refund(order)
    order.paymentStatus = 'refunded'
    if order.free or not order.paidAccount or not order.paidAmount or order.paidAmount <= 0 then return 0 end
    local amount = order.paidAmount + (order.paidService or 0) + (order.paidTip or 0)
    local payer = order.paidBy
    if payer and GetPlayerName(payer) and Framework.GetIdentifier(payer) == order.paidByIdentifier
        and Framework.AddMoney(payer, order.paidAccount, amount, 'cyphercity-hookah refund') then
        Persistence.RecordRefund(order, order.paidAmount + (order.paidService or 0), order.paidTip or 0)
        Banking.Withdraw(amount, 'cyphercity-hookah refund #' .. order.id)
        Logger.Info('payment', ('Refunded %s for order #%d to %s'):format(Utils.FormatMoney(amount), order.id, Security.Describe(payer)), { order = order.id, amount = amount })
        return amount
    end
    order.paymentStatus = 'refund_pending'
    Logger.Warn('payment', ('Refund of %s for order #%d could not be paid automatically (payer offline) — refund manually'):format(
        Utils.FormatMoney(amount), order.id
    ), { order = order.id, identifier = order.paidByIdentifier, amount = amount, account = order.paidAccount })
    return 0
end

-- Cashier action: pop the bill open on the table host's screen.
function Payments.RequestPayment(staffSrc, tableId)
    if not Staff.Require(staffSrc, 'request_payment') then return false, 'no_permission' end
    local t = Tables.Get(tableId)
    if not t or not t.owner then return false, 'table_not_found' end
    if Orders.UnpaidTotalForTable(t.id) <= 0 then return false, 'nothing_to_pay' end
    local mode = Config.Payments.allowTableBill and 'table' or 'personal'
    TriggerClientEvent('cyphercity-hookah:client:openBill', t.owner, mode)
    Notify.Player(t.owner, L('payment_requested', Framework.GetCharName(staffSrc)), 'info')
    Logger.Info('staff', ('%s requested payment from %s'):format(Security.Describe(staffSrc), t.label), { table = t.id })
    return true, L('staff_payment_sent', t.ownerName or t.label)
end

function Payments.OnDropped(src)
    paying[src] = nil
    for token, entry in pairs(tokens) do
        if entry.src == src then tokens[token] = nil end
    end
end
