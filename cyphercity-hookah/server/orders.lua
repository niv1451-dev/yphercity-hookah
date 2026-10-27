-- Orders: validation, pricing, status flow (new → preparing → serving → completed),
-- the automatic NPC kitchen, delivery and items "on the table".
-- Clients only ever send product ids, quantities and flavour ids — every price
-- below comes from the server's catalog.

Orders = {
    byId = {},
}

local nextId = 0
local served = {}          -- [src] = { [productId] = count }
local lastOrderAt = {}     -- [src] = os.time()
local stock = {}           -- [productId] = remaining (only when Config.Stock.enabled)
local busy = {}            -- [src] = true while an order is being charged
local consumingUntil = {}  -- [src] = GetGameTimer() deadline

local ACTIVE = { new = true, preparing = true, serving = true }
local FLOW = { 'new', 'preparing', 'serving', 'completed' }
local FLOW_INDEX = { new = 1, preparing = 2, serving = 3, completed = 4 }
local KITCHEN = { kind = 'kitchen', name = 'kitchen' }

local function now() return Utils.Now() end

local function isUnpaid(order)
    return order.paymentStatus == 'unpaid' and order.status ~= 'cancelled'
end

local function isOnline(src, identifier)
    if not src or not GetPlayerName(src) then return false end
    return identifier == nil or Framework.GetIdentifier(src) == identifier
end

function Orders.Init()
    Orders.byId = {}
    stock = {}
    if Config.Stock.enabled then
        for _, product in ipairs(Catalog.products) do
            stock[product.id] = Utils.ToInt(product.stock) or Config.Stock.defaultStock or 50
        end
    end
end

function Orders.StockOf(productId)
    if not Config.Stock.enabled then return nil end
    return stock[productId] or 0
end

local function prepTimeOf(lines)
    local longest = 0
    for _, line in ipairs(lines) do
        local product = Catalog.Get(line.id)
        local prep = (product and product.prepTime) or Config.Orders.defaultPrepTime or 20
        if prep > longest then longest = prep end
    end
    return math.max(1, math.floor(longest))
end

-- Validates and prices the raw lines sent by a client.
-- Returns lines, subtotal, hookahCount — or nil, errorCode, errorArg.
function Orders.NormalizeLines(raw)
    -- cheap length check first, so an oversized payload is rejected before it is walked
    if type(raw) ~= 'table' or #raw == 0 then return nil, 'order_empty' end
    if #raw > (Config.Orders.maxLinesPerOrder or 15) then return nil, 'too_many_lines' end
    if not Utils.IsArray(raw) then return nil, 'order_invalid' end

    local merged, keys = {}, {}
    local totalQty = 0
    for _, entry in ipairs(raw) do
        if type(entry) ~= 'table' then return nil, 'order_invalid' end
        local product = Catalog.Get(entry.id)
        if not product then return nil, 'order_invalid' end
        if not product.enabled then return nil, 'item_unavailable', product.label end
        local qty = Utils.ToInt(entry.qty)
        if not qty or qty < 1 or qty > 100 then return nil, 'qty_invalid' end
        local flavors, flavorErr = Catalog.ValidateFlavors(product, entry.flavors)
        if not flavors then return nil, flavorErr end

        local sorted = { table.unpack(flavors) }
        table.sort(sorted)
        local key = product.id .. '|' .. table.concat(sorted, ',')
        if merged[key] then
            merged[key].qty = merged[key].qty + qty
        else
            merged[key] = { product = product, flavors = flavors, qty = qty }
            keys[#keys + 1] = key
        end
        totalQty = totalQty + qty
    end

    local maxItems = Config.Orders.maxItemsPerOrder or 25
    if totalQty > maxItems then return nil, 'too_many_items', maxItems end

    local perProduct = {}
    for _, key in ipairs(keys) do
        local entry = merged[key]
        perProduct[entry.product.id] = (perProduct[entry.product.id] or 0) + entry.qty
    end
    for productId, qty in pairs(perProduct) do
        local product = Catalog.Get(productId)
        if qty > Catalog.MaxQty(product) then return nil, 'qty_invalid' end
        if Config.Stock.enabled and (stock[productId] or 0) < qty then
            return nil, 'out_of_stock', product.label
        end
    end

    local lines, subtotal, hookahs = {}, 0, 0
    for _, key in ipairs(keys) do
        local entry = merged[key]
        local product = entry.product
        local unitPrice = Catalog.UnitPrice(product, entry.flavors)
        local line = {
            id = product.id,
            kind = product.kind,
            label = product.label,
            qty = entry.qty,
            unitPrice = unitPrice,
            total = unitPrice * entry.qty,
            flavors = entry.flavors,
            flavorLabels = Catalog.FlavorLabels(entry.flavors),
        }
        lines[#lines + 1] = line
        subtotal = subtotal + line.total
        if product.kind == 'hookah' then hookahs = hookahs + entry.qty end
    end
    return lines, subtotal, hookahs
end

function Orders.ActiveCount(src)
    local count = 0
    for _, order in pairs(Orders.byId) do
        if order.src == src and order.kind == 'order' and ACTIVE[order.status] then count = count + 1 end
    end
    return count
end

function Orders.PendingHookahs(tableId)
    local count = 0
    for _, order in pairs(Orders.byId) do
        if order.tableId == tableId and ACTIVE[order.status] then
            for _, line in ipairs(order.lines) do
                if line.kind == 'hookah' then count = count + line.qty end
            end
        end
    end
    return count
end

function Orders.UnpaidFor(src)
    local list = {}
    for _, order in pairs(Orders.byId) do
        if order.src == src and isUnpaid(order) then list[#list + 1] = order end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function Orders.UnpaidForTable(tableId)
    local list = {}
    for _, order in pairs(Orders.byId) do
        if order.tableId == tableId and isUnpaid(order) then list[#list + 1] = order end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function sum(list)
    local total = 0
    for _, order in ipairs(list) do total = total + order.subtotal end
    return total
end

function Orders.UnpaidTotalFor(src) return sum(Orders.UnpaidFor(src)) end
function Orders.UnpaidTotalForTable(tableId) return sum(Orders.UnpaidForTable(tableId)) end

local function newOrder(src, t, kind, lines, subtotal)
    nextId = nextId + 1
    local order = {
        id = nextId,
        kind = kind,
        tableId = t and t.id or nil,
        tableLabel = t and t.label or nil,
        src = src,
        identifier = Framework.GetIdentifier(src),
        customer = Framework.GetCharName(src),
        lines = lines,
        subtotal = subtotal,
        status = kind == 'service' and 'completed' or 'new',
        paymentStatus = 'unpaid',
        createdAt = now(),
        updatedAt = now(),
        auto = false,
        history = { { status = kind == 'service' and 'completed' or 'new', at = now(), by = 'customer' } },
    }
    Orders.byId[order.id] = order
    return order
end

local function markPaid(order, src, info, amount)
    order.paymentStatus = 'paid'
    order.paidAt = now()
    order.paidBy = src
    order.paidByIdentifier = Framework.GetIdentifier(src)
    order.paidAccount = info and info.account or nil
    order.paidAmount = amount
    order.paymentId = info and info.id or nil
    order.free = info and info.free or false
end

local function openBillAllowed(src, t, extra)
    local limit = Config.Orders.maxOpenBillPerTable or 2500
    local open = t and Orders.UnpaidTotalForTable(t.id) or Orders.UnpaidTotalFor(src)
    return open + extra <= limit, limit
end

function Orders.Create(src, payload)
    if not Security.CheckRequestId(src, payload.requestId) then return false, 'duplicate_request' end
    local allowed, code = Business.CanServe(src)
    if not allowed then return false, code end
    if not Payments.OrderingAllowed() then return false, 'payments_disabled' end
    if busy[src] then return false, 'busy' end
    local last = lastOrderAt[src]
    if last and now() - last < (Config.Orders.cooldownSeconds or 5) then return false, 'order_cooldown' end
    if not Security.InVenue(src) then return false, 'not_in_venue' end

    local t = Tables.Of(src)
    if t then
        if t.status ~= 'occupied' then return false, 'not_seated' end
    elseif not Config.Orders.allowWithoutTable then
        return false, 'need_table'
    end

    local maxActive = Config.Orders.maxActiveOrdersPerPlayer or 3
    if Orders.ActiveCount(src) >= maxActive then return false, 'too_many_active_orders', maxActive end

    local lines, subtotal, hookahs = Orders.NormalizeLines(payload.lines)
    if not lines then
        -- on failure NormalizeLines returns nil, errorCode, errorArg
        return false, subtotal, hookahs
    end

    if hookahs > 0 then
        if not t then return false, 'hookah_needs_table' end
        local spots = Hookah.SpotCount(t.id)
        if #Hookah.ForTable(t.id) + Orders.PendingHookahs(t.id) + hookahs > spots then
            return false, 'hookah_no_spot', spots
        end
    end

    -- optional inventory requirements (ignored in catalog-only mode)
    local toRemove = {}
    for _, line in ipairs(lines) do
        local product = Catalog.Get(line.id)
        local need = product.inventory and product.inventory.require
        if need and not need.disabled then
            local count = need.count * line.qty
            if Inventory.GetCount(src, need.name) < count then
                return false, 'missing_required_item', product.label, need.label or need.name
            end
            if need.remove then toRemove[#toRemove + 1] = { name = need.name, count = count } end
        end
    end

    local paymentInfo
    if Config.Payments.timing == 'on_order' then
        busy[src] = true
        local paid, payCode, payArg, info = Payments.ChargeDirect(src, payload.account, subtotal, 'order')
        busy[src] = nil
        if not paid then return false, payCode, payArg end
        paymentInfo = info
    else
        local ok, limit = openBillAllowed(src, t, subtotal)
        if not ok then return false, 'open_bill_limit', Utils.FormatMoney(limit) end
    end

    -- commit (nothing below yields)
    for _, item in ipairs(toRemove) do
        if not Inventory.Remove(src, item.name, item.count) then
            Logger.Warn('order', ('Could not remove required item %s x%d from %s'):format(item.name, item.count, Security.Describe(src)))
        end
    end
    if Config.Stock.enabled then
        for _, line in ipairs(lines) do stock[line.id] = (stock[line.id] or 0) - line.qty end
    end

    local order = newOrder(src, t, 'order', lines, subtotal)
    if paymentInfo then
        markPaid(order, src, paymentInfo, subtotal)
        Persistence.RecordSale({ order }, paymentInfo.free and 0 or subtotal, 0)
    end
    lastOrderAt[src] = now()

    Logger.Info('order', ('Order #%d by %s at %s: %s'):format(order.id, Security.Describe(src), order.tableLabel or 'bar', Utils.FormatMoney(subtotal)), {
        order = order.id, total = subtotal, lines = #lines, paid = order.paymentStatus == 'paid',
    })
    Staff.NotifyAll('view_orders', L('staff_new_order', order.id, order.tableLabel or '-'), 'info')
    Sync.Order(order)
    return true, order
end

-- Service charges (flavour change, coal refresh) are recorded as completed
-- "service" orders so they show on the same bill.
function Orders.CreateServiceCharge(src, t, label, amount, account)
    if not Payments.OrderingAllowed() then return false, 'payments_disabled' end
    amount = Utils.ToInt(amount) or 0
    local lines = { { id = 'service', kind = 'service', label = label, qty = 1, unitPrice = amount, total = amount, flavors = {}, flavorLabels = {} } }
    local info
    if Config.Payments.timing == 'on_order' or amount == 0 then
        local paid, code, arg, payInfo = Payments.ChargeDirect(src, account, amount, 'service')
        if not paid then return false, code, arg end
        info = payInfo
    else
        local ok, limit = openBillAllowed(src, t, amount)
        if not ok then return false, 'open_bill_limit', Utils.FormatMoney(limit) end
    end
    local order = newOrder(src, t, 'service', lines, amount)
    if info then
        markPaid(order, src, info, amount)
        Persistence.RecordSale({ order }, info.free and 0 or amount, 0)
    end
    Logger.Info('order', ('Service charge #%d "%s" %s for %s'):format(order.id, label, Utils.FormatMoney(amount), Security.Describe(src)))
    Sync.Order(order)
    return true, order
end

-- Delivery ----------------------------------------------------------------------
function Orders.Deliver(order)
    local src = order.src
    local online = isOnline(src, order.identifier)
    local servedLabels, receivedLabels = {}, {}

    for _, line in ipairs(order.lines) do
        local product = Catalog.Get(line.id)
        if line.kind == 'hookah' then
            local t = order.tableId and Tables.Get(order.tableId)
            if product and t and t.status == 'occupied' then
                for _ = 1, line.qty do
                    local session = Hookah.Create(t.id, src, product, line.flavors)
                    if session and online then
                        Notify.Player(src, L('hookah_served', product.label, table.concat(line.flavorLabels, ' + ')), 'success')
                    end
                end
            end
        elseif line.kind == 'item' and product and online then
            local give = product.inventory and product.inventory.give
            local delivered = false
            if give and not give.disabled and Inventory.Active() then
                local count = give.count * line.qty
                if Inventory.CanCarry(src, give.name, count) and Inventory.Add(src, give.name, count) then
                    delivered = true
                    receivedLabels[#receivedLabels + 1] = ('%s x%d'):format(product.label, line.qty)
                else
                    Notify.Player(src, L('inventory_full_fallback', product.label), 'info')
                end
            end
            if not delivered then
                served[src] = served[src] or {}
                served[src][line.id] = (served[src][line.id] or 0) + line.qty
                servedLabels[#servedLabels + 1] = ('%s x%d'):format(product.label, line.qty)
            end
        end
    end

    if online then
        if #receivedLabels > 0 then Notify.Player(src, L('received_items', table.concat(receivedLabels, ', ')), 'success') end
        if #servedLabels > 0 then Notify.Player(src, L('served_to_table', table.concat(servedLabels, ', ')), 'success') end
        Sync.Player(src)
    end
end

-- Status flow ---------------------------------------------------------------------
local STATUS_MESSAGE = { preparing = 'order_preparing', serving = 'order_serving', completed = 'order_completed' }

local function advance(order, status, actor)
    local current = now()
    order.status = status
    order.updatedAt = current
    order.history[#order.history + 1] = { status = status, at = current, by = actor.name }

    if status == 'preparing' then
        order.acceptedAt = current
        order.readyAt = current + prepTimeOf(order.lines)
        if actor.kind == 'staff' then
            order.handler = actor.src
            order.handlerName = actor.name
            order.auto = false
        end
    elseif status == 'serving' then
        order.servingAt = current
        if order.tableId then
            TriggerClientEvent('cyphercity-hookah:client:waiterServe', -1, order.tableId)
        end
    elseif status == 'completed' then
        order.completedAt = current
        Orders.Deliver(order)
    end

    if STATUS_MESSAGE[status] and isOnline(order.src, order.identifier) then
        Notify.Player(order.src, L(STATUS_MESSAGE[status], order.id), status == 'completed' and 'success' or 'info')
    end
    Logger.Info('order', ('Order #%d → %s (%s)'):format(order.id, status, actor.name), { order = order.id })
    Sync.Order(order)
end

function Orders.StaffSetStatus(staffSrc, orderId, status)
    if not Staff.Require(staffSrc, 'update_order') then return false, 'no_permission' end
    local order = Orders.byId[Utils.ToInt(orderId) or -1]
    if not order or order.kind ~= 'order' then return false, 'order_not_found' end
    local from, to = FLOW_INDEX[order.status], FLOW_INDEX[status]
    if not ACTIVE[order.status] or not to or to <= from then return false, 'order_bad_transition' end

    local actor = { kind = 'staff', src = staffSrc, name = Framework.GetCharName(staffSrc) }
    for index = from + 1, to do
        advance(order, FLOW[index], actor)
    end
    Logger.Info('staff', ('%s set order #%d to %s'):format(Security.Describe(staffSrc), order.id, status))
    return true, L('staff_order_updated', order.id, status)
end

local function cancel(order, by, reason)
    order.status = 'cancelled'
    order.cancelReason = reason
    order.updatedAt = now()
    order.history[#order.history + 1] = { status = 'cancelled', at = now(), by = by }
    if Config.Stock.enabled then
        for _, line in ipairs(order.lines) do
            if stock[line.id] then stock[line.id] = stock[line.id] + line.qty end
        end
    end
    local refunded
    if order.paymentStatus == 'unpaid' then
        order.paymentStatus = 'void'
    elseif order.paymentStatus == 'paid' then
        refunded = Payments.Refund(order)
    end
    if isOnline(order.src, order.identifier) then
        if refunded and refunded > 0 then
            Notify.Player(order.src, L('order_refunded', order.id, Utils.FormatMoney(refunded)), 'info')
        else
            Notify.Player(order.src, L('order_cancelled', order.id), 'info')
        end
    end
    Logger.Info('order', ('Order #%d cancelled by %s (%s)'):format(order.id, tostring(by), reason or '-'), { order = order.id, payment = order.paymentStatus })
    Sync.Order(order)
end

function Orders.CustomerCancel(src, orderId)
    local order = Orders.byId[Utils.ToInt(orderId) or -1]
    if not order or order.src ~= src then return false, 'order_not_found' end
    if not Config.Orders.customerCancelWhileNew or order.status ~= 'new' or order.kind ~= 'order' then
        return false, 'order_cannot_cancel'
    end
    if order.paymentStatus == 'processing' then return false, 'payment_in_progress' end
    cancel(order, 'customer', 'customer_cancel')
    return true
end

function Orders.StaffCancel(staffSrc, orderId, reason)
    if not Staff.Require(staffSrc, 'cancel_order') then return false, 'no_permission' end
    local order = Orders.byId[Utils.ToInt(orderId) or -1]
    if not order then return false, 'order_not_found' end
    if order.paymentStatus == 'processing' then return false, 'payment_in_progress' end
    if ACTIVE[order.status] then
        cancel(order, Framework.GetCharName(staffSrc), Utils.SanitizeString(reason, 60) or 'staff')
    elseif isUnpaid(order) then
        -- already served but unpaid (e.g. a comped item): void the charge
        order.paymentStatus = 'void'
        order.voidReason = 'staff'
        order.updatedAt = now()
        Sync.Order(order)
    else
        return false, 'order_cannot_cancel'
    end
    Logger.Info('staff', ('%s cancelled/voided order #%d'):format(Security.Describe(staffSrc), order.id), { order = order.id })
    return true, L('order_cancelled', order.id)
end

-- Voids every unpaid order of a player (disconnect, walkout, released table).
function Orders.VoidFor(src, reason)
    for _, order in ipairs(Orders.UnpaidFor(src)) do
        if ACTIVE[order.status] then
            cancel(order, 'system', reason)
        else
            order.paymentStatus = 'void'
            order.voidReason = reason
            order.updatedAt = now()
            Logger.Warn('payment', ('Order #%d voided unpaid (%s)'):format(order.id, reason), { order = order.id, amount = order.subtotal, identifier = order.identifier })
            Sync.Order(order)
        end
    end
end

function Orders.OnTableReleased(tableId, reason)
    for _, order in pairs(Orders.byId) do
        if order.tableId == tableId and order.paymentStatus ~= 'processing' then
            if ACTIVE[order.status] then
                cancel(order, 'system', reason)
            elseif isUnpaid(order) then
                order.paymentStatus = 'void'
                order.voidReason = reason
                order.updatedAt = now()
                Logger.Warn('payment', ('Order #%d voided on table release (%s)'):format(order.id, reason or '-'), { order = order.id, amount = order.subtotal })
            end
        end
    end
end

-- Items on the table --------------------------------------------------------------
function Orders.Consume(src, productId)
    local product = Catalog.Get(productId)
    if not product or product.kind ~= 'item' then return false, 'consume_none' end
    local entry = served[src]
    local count = entry and entry[product.id] or 0
    if count <= 0 then return false, 'consume_none' end
    if not Security.InVenue(src) then return false, 'not_in_venue' end
    local clock = GetGameTimer()
    if consumingUntil[src] and clock < consumingUntil[src] then return false, 'consume_busy' end

    local profile = Config.ConsumeProfiles[product.consume] or {}
    consumingUntil[src] = clock + (profile.duration or 4000)
    entry[product.id] = count > 1 and count - 1 or nil
    TriggerClientEvent('cyphercity-hookah:client:consume', src, product.id, product.consume)
    if Config.Status.enabled then
        local needs = (Config.Status.profiles or {})[product.consume]
        if needs then Framework.AddNeeds(src, needs) end
    end
    Sync.Player(src)
    return true
end

function Orders.ServedList(src)
    local list = {}
    for productId, count in pairs(served[src] or {}) do
        local product = Catalog.Get(productId)
        if product then
            list[#list + 1] = { id = productId, label = product.label, count = count, image = product.image, consume = product.consume }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

function Orders.ClearServed(src)
    if served[src] then
        served[src] = nil
        Sync.Player(src)
    end
end

-- Kitchen loop ---------------------------------------------------------------------
function Orders.Tick()
    local current = now()
    local mode = Config.Orders.mode or 'hybrid'
    local grace = Config.Orders.hybridStaffGrace or 60
    local staffCount

    for id, order in pairs(Orders.byId) do
        if order.kind == 'order' and ACTIVE[order.status] then
            if order.handler and not Staff.RoleHas(Staff.GetRole(order.handler), 'update_order') then
                order.handler = nil
                order.auto = true
            end
            if mode == 'hybrid' and not order.auto then
                -- a staff member accepted it but stopped progressing it: the kitchen takes over
                if (order.status == 'preparing' and current >= (order.readyAt or current) + grace * 2)
                    or (order.status == 'serving' and current >= (order.servingAt or current) + (Config.Orders.serveTime or 10) + grace) then
                    order.auto = true
                end
            end

            if order.status == 'new' then
                local auto = mode == 'auto'
                if mode == 'hybrid' then
                    staffCount = staffCount or Staff.OnDutyCount()
                    auto = staffCount == 0 or current - order.createdAt >= grace
                end
                if auto and current - order.createdAt >= (Config.Orders.autoAcceptDelay or 5) then
                    order.auto = true
                    advance(order, 'preparing', KITCHEN)
                end
            elseif order.status == 'preparing' and order.auto and current >= order.readyAt then
                advance(order, 'serving', KITCHEN)
            elseif order.status == 'serving' and order.auto and current >= order.servingAt + (Config.Orders.serveTime or 10) then
                advance(order, 'completed', KITCHEN)
            end
        elseif not ACTIVE[order.status] and order.paymentStatus ~= 'unpaid' and order.paymentStatus ~= 'processing'
            and current - order.updatedAt > (Config.Orders.keepFinishedFor or 900) then
            Orders.byId[id] = nil
        end
    end
end

function Orders.OnDropped(src)
    local unpaid = Orders.UnpaidTotalFor(src)
    if unpaid > 0 then
        Logger.Warn('security', ('Disconnected with an unpaid bill of %s: %s'):format(unpaid, Security.Describe(src)), {
            player = src, identifier = Framework.GetIdentifier(src), amount = unpaid,
        })
        Orders.VoidFor(src, 'disconnect')
    end
    served[src] = nil
    lastOrderAt[src] = nil
    busy[src] = nil
    consumingUntil[src] = nil
end

-- Stock -----------------------------------------------------------------------------
function Orders.Restock(staffSrc, productId)
    if not Staff.Require(staffSrc, 'manage_stock') then return false, 'no_permission' end
    if not Config.Stock.enabled then return false, 'invalid_request' end
    local amount = Config.Stock.restockAmount or 50
    if productId then
        if not Catalog.Get(productId) then return false, 'invalid_request' end
        stock[productId] = (stock[productId] or 0) + amount
    else
        for _, product in ipairs(Catalog.products) do
            stock[product.id] = (stock[product.id] or 0) + amount
        end
    end
    Logger.Info('staff', ('%s restocked %s'):format(Security.Describe(staffSrc), productId or 'all'))
    Sync.Staff()
    return true, L('staff_restocked')
end

function Orders.StockList()
    if not Config.Stock.enabled then return nil end
    local list = {}
    for _, product in ipairs(Catalog.products) do
        list[#list + 1] = { id = product.id, label = product.label, stock = stock[product.id] or 0 }
    end
    return list
end

-- Views -------------------------------------------------------------------------------
function Orders.View(order, viewer)
    local current = now()
    return {
        id = order.id,
        kind = order.kind,
        tableId = order.tableId,
        tableLabel = order.tableLabel,
        customer = order.customer,
        mine = viewer ~= nil and order.src == viewer,
        lines = order.lines,
        subtotal = order.subtotal,
        status = order.status,
        paymentStatus = order.paymentStatus,
        free = order.free,
        age = current - order.createdAt,
        eta = order.readyAt and math.max(0, order.readyAt - current) or nil,
        auto = order.auto,
        handler = order.handlerName,
    }
end

function Orders.ForPlayer(src)
    local t = Tables.Of(src)
    local list = {}
    for _, order in pairs(Orders.byId) do
        local relevant = order.src == src or (t and order.tableId == t.id)
        if relevant and (ACTIVE[order.status] or isUnpaid(order) or now() - order.updatedAt < 600) then
            list[#list + 1] = Orders.View(order, src)
        end
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    return list
end

function Orders.StaffList()
    local list = {}
    for _, order in pairs(Orders.byId) do
        if ACTIVE[order.status] or isUnpaid(order) then
            list[#list + 1] = Orders.View(order)
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end
