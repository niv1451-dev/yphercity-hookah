-- Server logic tests. Each scenario boots a fresh copy of the resource inside
-- the FiveM mock with a fake framework (ESX / QBCore / Qbox / standalone).

local H = HARNESS

local function product(id) return Catalog.Get(id) end

local function lastNotify(src)
    local list = MOCK.EventsFor('cyphercity-hookah:client:notify', src)
    local event = list[#list]
    return event and event.args[1]
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Shared scenarios, executed once per framework
-- ═════════════════════════════════════════════════════════════════════════════

local function frameworkSuite(kind)
    local money = kind ~= 'standalone'
    H.Section(('Framework: %s'):format(kind))

    H.Test(kind .. ': boots and detects the framework', function()
        H.BootServer({ framework = kind })
        H.True(Server.ready, 'server ready')
        H.Eq(Bridge.framework, kind, 'framework')
        H.Eq(Payments.MoneyMode(), money and 'money' or 'free', 'money mode')
        H.Eq(#Catalog.errors, 0, 'catalog errors')
        H.Eq(Server.standaloneFallback, kind == 'standalone', 'standalone fallback flag')
    end)

    H.Test(kind .. ': hostess assigns the smallest free table and blocks double requests', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Far(1)
        H.Fails(MOCK.Call(1, 'requestTable', { partySize = 2 }), 'too_far', 'far from hostess')
        H.AtHostess(1)
        for _, bad in ipairs({ 0, 99, 2.5, 'x' }) do
            MOCK.Advance(16000) -- requestTable rate limit window
            H.Fails(MOCK.Call(1, 'requestTable', { partySize = bad }), 'party_size_invalid', 'party ' .. tostring(bad))
        end
        local r = H.Ok(MOCK.Call(1, 'requestTable', { partySize = 2 }))
        H.Eq(r.data.tableId, 1, 'first table')
        H.Eq(Tables.Get(1).status, 'reserved', 'status')
        H.Fails(MOCK.Call(1, 'requestTable', { partySize = 2 }), 'already_has_table', 'second request')
    end)

    H.Test(kind .. ': last free table goes to exactly one of two simultaneous requests', function()
        H.BootServer({ framework = kind })
        for id = 1, 7 do H.Player({ id = id }) H.AtHostess(id) end
        for id = 1, 5 do H.Ok(MOCK.Call(id, 'requestTable', { partySize = 2 })) end
        local a = MOCK.Call(6, 'requestTable', { partySize = 2 })
        local b = MOCK.Call(7, 'requestTable', { partySize = 2 })
        H.True((a.ok and not b.ok) or (b.ok and not a.ok), 'exactly one succeeds')
        H.Eq((a.ok and b or a).code, 'no_free_table', 'loser code')
        H.Eq((a.ok and a or b).data.tableId, 6, 'VIP table used last')
    end)

    H.Test(kind .. ': seating, invitations and capacity', function()
        H.BootServer({ framework = kind })
        for id = 1, 6 do H.Player({ id = id }) end
        local tableId = H.Seat(1)
        H.Eq(Tables.Get(tableId).status, 'occupied', 'occupied after sitting')
        H.AtTable(3, tableId)
        H.Fails(MOCK.Call(3, 'sit', { tableId = tableId }), 'not_your_table', 'stranger')
        H.AtTable(2, tableId)
        H.Ok(MOCK.Call(1, 'invite', { target = 2 }), 'invite')
        H.Fails(MOCK.Call(2, 'invite', { target = 3 }), 'no_table', 'guest without a table cannot invite')
        H.Ok(MOCK.Call(2, 'sit', { tableId = tableId }), 'invited guest sits')
        H.Fails(MOCK.Call(2, 'invite', { target = 3 }), 'not_table_owner', 'guest invites')
        H.Far(4)
        H.Fails(MOCK.Call(1, 'invite', { target = 4 }), 'player_not_nearby', 'far player')
        MOCK.Advance(21000) -- invite rate limit window
        for _, id in ipairs({ 3, 4 }) do
            H.AtTable(id, tableId)
            H.Ok(MOCK.Call(1, 'invite', { target = id }))
            H.Ok(MOCK.Call(id, 'sit', { tableId = tableId }))
        end
        H.AtTable(5, tableId)
        MOCK.Advance(21000)
        H.Fails(MOCK.Call(1, 'invite', { target = 5 }), 'table_full', 'capacity reached')
        H.Eq(Tables.SeatedCount(Tables.Get(tableId)), 4, 'four seated')
    end)

    H.Test(kind .. ': order validation rejects bad input', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 2 })
        H.AtTable(2, 1)
        H.Fails(H.Order(2, { { id = 'fries', qty = 1 } }), 'need_table', 'no table')
        H.Seat(1)
        H.Fails(H.Order(1, {}), 'order_empty', 'empty')
        H.Fails(H.Order(1, 'fries'), 'order_empty', 'not a list')
        H.Fails(H.Order(1, { { id = 'gold_bar', qty = 1 } }), 'order_invalid', 'unknown item')
        H.Fails(H.Order(1, { { id = 'falafel', qty = 1 } }), 'item_unavailable', 'disabled item')
        for _, qty in ipairs({ 0, -1, 1.5, '2', 1e9 }) do
            H.Fails(H.Order(1, { { id = 'fries', qty = qty } }), 'qty_invalid', 'qty ' .. tostring(qty))
        end
        H.Fails(H.Order(1, { { id = 'tea_kettle', qty = 4 } }), 'qty_invalid', 'per-item maxQty')
        local many = {}
        for i = 1, 16 do many[i] = { id = 'water', qty = 1 } end
        H.Fails(H.Order(1, many), 'too_many_lines', 'too many lines')
        local units = {}
        for _, id in ipairs({ 'fries', 'water', 'cola' }) do units[#units + 1] = { id = id, qty = 9 } end
        H.Fails(H.Order(1, units), 'too_many_items', 'too many units')
        H.Fails(H.Order(1, { { id = 'hookah_classic', qty = 1 } }), 'flavor_invalid', 'hookah without flavour')
        H.Fails(H.Order(1, { { id = 'hookah_classic', qty = 1, flavors = { 'peach', 'mango' } } }), 'flavor_invalid', 'two flavours on a single')
        H.Fails(H.Order(1, { { id = 'hookah_mix', qty = 1, flavors = { 'peach', 'peach' } } }), 'flavor_invalid', 'duplicate flavours')
        H.Fails(H.Order(1, { { id = 'hookah_fruit', qty = 1, flavors = { 'double_apple' } } }), 'flavor_invalid', 'flavour not allowed for type')
        H.Fails(H.Order(1, { { id = 'hookah_mix', qty = 1, flavors = { 'peach', 'nope' } } }), 'flavor_invalid', 'unknown flavour')
        H.Fails(H.Order(1, { { id = 'fries', qty = 1, flavors = { 'peach' } } }), 'flavor_invalid', 'flavour on food')
    end)

    H.Test(kind .. ': the server prices the order (client prices are ignored)', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Seat(1)
        local r = H.Ok(H.Order(1, {
            { id = 'fries', qty = 2, price = 1, total = 1 },
            { id = 'hookah_mix', qty = 1, flavors = { 'peach', 'cola_ice' }, price = 0 },
        }, { total = 1, subtotal = 1 }))
        local expected = product('fries').price * 2 + product('hookah_mix').price + Catalog.flavorById.peach.price + Catalog.flavorById.cola_ice.price
        H.Eq(r.data.total, expected, 'server total')
        H.Eq(Orders.byId[r.data.id].subtotal, expected, 'stored subtotal')
    end)

    H.Test(kind .. ': replayed requests, cooldown, closed lounge and venue checks', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Seat(1)
        MOCK.Advance(6000)
        local payload = { lines = { { id = 'water', qty = 1 } }, requestId = 'fixed-request-1' }
        H.Ok(MOCK.Call(1, 'placeOrder', payload))
        MOCK.Advance(11000)
        H.Fails(MOCK.Call(1, 'placeOrder', payload), 'duplicate_request', 'replay')
        H.Fails(MOCK.Call(1, 'placeOrder', { lines = payload.lines }), 'duplicate_request', 'missing request id')
        MOCK.Advance(11000) -- placeOrder rate limit window
        H.Ok(MOCK.Call(1, 'placeOrder', { lines = payload.lines, requestId = 'fixed-request-2' }))
        H.Fails(MOCK.Call(1, 'placeOrder', { lines = payload.lines, requestId = 'fixed-request-3' }), 'order_cooldown', 'cooldown')
        Business.manualOpen = false
        H.Fails(H.Order(1, { { id = 'water', qty = 1 } }), 'business_closed', 'closed')
        Business.manualOpen = true
        H.Far(1)
        H.Fails(H.Order(1, { { id = 'water', qty = 1 } }), 'not_in_venue', 'outside venue')
    end)

    H.Test(kind .. ': reserved (not yet seated) table cannot order and expires', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.AtHostess(1)
        H.Ok(MOCK.Call(1, 'requestTable', { partySize = 2 }))
        H.Fails(H.Order(1, { { id = 'water', qty = 1 } }), 'not_seated', 'reserved table')
        MOCK.Advance((Config.TableSettings.reserveTimeout + 2) * 1000)
        H.True(Tables.Of(1) == nil, 'player removed after reserve timeout')
        H.True(Tables.Get(1).status ~= 'reserved', 'table no longer reserved')
    end)

    H.Test(kind .. ': kitchen flow new → preparing → serving → completed, items on the table, consumption', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'fries', qty = 2 } }))
        local order = Orders.byId[r.data.id]
        H.True(H.RunUntil(function() return order.status == 'preparing' end, 10000), 'preparing')
        H.True(H.RunUntil(function() return order.status == 'serving' end, 60000), 'serving')
        H.True(#MOCK.EventsFor('cyphercity-hookah:client:waiterServe', -1) > 0, 'waiter walk broadcast')
        H.True(H.RunUntil(function() return order.status == 'completed' end, 30000), 'completed')
        local served = Orders.ServedList(1)
        H.Eq(#served, 1, 'one served product')
        H.Eq(served[1].count, 2, 'served count')
        H.Ok(MOCK.Call(1, 'consume', { itemId = 'fries' }))
        H.True(#MOCK.EventsFor('cyphercity-hookah:client:consume', 1) == 1, 'consume animation event')
        H.Fails(MOCK.Call(1, 'consume', { itemId = 'fries' }), 'consume_busy', 'still eating')
        MOCK.Advance(6000)
        H.Ok(MOCK.Call(1, 'consume', { itemId = 'fries' }))
        MOCK.Advance(6000)
        H.Fails(MOCK.Call(1, 'consume', { itemId = 'fries' }), 'consume_none', 'nothing left')
        H.Fails(MOCK.Call(1, 'consume', { itemId = 'whiskey' }), 'consume_none', 'never served')
    end)

    H.Test(kind .. ': customer can cancel only a new order', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 2 })
        H.Seat(1)
        H.Seat(2)
        local r = H.Ok(H.Order(1, { { id = 'water', qty = 1 } }))
        H.Fails(MOCK.Call(2, 'cancelOrder', { orderId = r.data.id }), 'order_not_found', 'someone else')
        local r2 = H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }))
        H.Ok(MOCK.Call(1, 'cancelOrder', { orderId = r2.data.id }))
        H.Eq(Orders.byId[r2.data.id].paymentStatus, 'void', 'void after cancel')
        local order = Orders.byId[r.data.id]
        H.RunUntil(function() return order.status ~= 'new' end, 20000)
        H.Fails(MOCK.Call(1, 'cancelOrder', { orderId = r.data.id }), 'order_cannot_cancel', 'already preparing')
    end)

    H.Test(kind .. ': hookah sessions — shared table use, exclusive hose, flavour change, coals, expiry', function()
        H.BootServer({ framework = kind })
        for id = 1, 3 do H.Player({ id = id }) end
        local tableId = H.Seat(1)
        H.AtTable(2, tableId)
        H.Ok(MOCK.Call(1, 'invite', { target = 2 }))
        H.Ok(MOCK.Call(2, 'sit', { tableId = tableId }))
        local r = H.Ok(H.Order(1, { { id = 'hookah_classic', qty = 2, flavors = { 'grape_mint' } } }))
        H.Fails(H.Order(1, { { id = 'hookah_ice', qty = 1, flavors = { 'lemon_mint' } } }), 'hookah_no_spot', 'table spots')
        local order = Orders.byId[r.data.id]
        H.True(H.RunUntil(function() return order.status == 'completed' end, 120000), 'served')
        local sessions = Hookah.ForTable(tableId)
        H.Eq(#sessions, 2, 'two hookahs at the table')
        local id = sessions[1].id
        H.Ok(MOCK.Call(1, 'hookahAction', { action = 'use', sessionId = id }), 'owner smokes')
        H.True(#MOCK.EventsFor('cyphercity-hookah:client:hookahSmoke', 1) == 1, 'smoke event')
        H.Fails(MOCK.Call(2, 'hookahAction', { action = 'use', sessionId = id }), 'hookah_in_use', 'second user blocked')
        H.Ok(MOCK.Call(2, 'hookahAction', { action = 'use', sessionId = sessions[2].id }), 'other hookah is free')
        H.Fails(MOCK.Call(1, 'hookahAction', { action = 'use', sessionId = id }), 'hookah_cooldown', 'puff cooldown')
        MOCK.Advance((Config.Hookah.useDuration + Config.Hookah.puffCooldown + 1) * 1000)
        H.Eq(Hookah.sessions[id].activeUser, nil, 'hose released after the puff')
        H.Ok(MOCK.Call(2, 'hookahAction', { action = 'use', sessionId = id }), 'free again for the next person')
    end)

    H.Test(kind .. ': hookah access rules and paid services', function()
        H.BootServer({ framework = kind })
        for id = 1, 3 do H.Player({ id = id }) end
        local tableId = H.Seat(1)
        H.Seat(3)
        local r = H.Ok(H.Order(1, { { id = 'hookah_mix', qty = 1, flavors = { 'peach', 'mango' } } }))
        local order = Orders.byId[r.data.id]
        H.RunUntil(function() return order.status == 'completed' end, 120000)
        local session = Hookah.ForTable(tableId)[1]
        H.Fails(MOCK.Call(3, 'hookahAction', { action = 'use', sessionId = session.id }), 'hookah_not_yours', 'other table')
        H.Fails(MOCK.Call(1, 'hookahAction', { action = 'flavor', sessionId = session.id, flavors = { 'a', 'b', 'c' } }), 'flavor_invalid', 'bad flavour change')
        local before = Orders.UnpaidTotalFor(1)
        H.Ok(MOCK.Call(1, 'hookahAction', { action = 'flavor', sessionId = session.id, flavors = { 'blueberry' } }))
        local expected = Config.Hookah.flavorChange.price + Catalog.flavorById.blueberry.price
        if Config.Payments.timing == 'on_bill' then
            H.Eq(Orders.UnpaidTotalFor(1) - before, expected, 'flavour change added to bill')
        end
        H.Eq(session.flavors[1], 'blueberry', 'flavour updated')
        H.Eq(session.refreshes, 1, 'a flavour change that restarts the timer counts as a refresh')
        local expires = session.expiresAt
        H.Ok(MOCK.Call(1, 'hookahAction', { action = 'coals', sessionId = session.id }))
        H.Eq(session.expiresAt, expires + Config.Hookah.coalRefresh.extendSeconds, 'coals extend time')
        for _ = 3, Config.Hookah.coalRefresh.maxRefreshes do H.Ok(MOCK.Call(1, 'hookahAction', { action = 'coals', sessionId = session.id })) end
        H.Fails(MOCK.Call(1, 'hookahAction', { action = 'coals', sessionId = session.id }), 'hookah_max_refresh', 'max refresh')
        H.Fails(MOCK.Call(1, 'hookahAction', { action = 'teleport', sessionId = session.id }), 'invalid_request', 'unknown action')
        H.Ok(MOCK.Call(1, 'hookahAction', { action = 'end', sessionId = session.id }))
        H.Eq(#Hookah.ForTable(tableId), 0, 'ended')
    end)

    H.Test(kind .. ': hookah expires on its own', function()
        H.BootServer({ framework = kind, config = function(c) c.Hookah.Types[1].duration = 60 end })
        H.Player({ id = 1 })
        local tableId = H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'hookah_classic', qty = 1, flavors = { 'watermelon' } } }))
        local order = Orders.byId[r.data.id]
        H.RunUntil(function() return order.status == 'completed' end, 120000)
        H.Eq(#Hookah.ForTable(tableId), 1, 'served')
        MOCK.Advance(62000)
        H.Eq(#Hookah.ForTable(tableId), 0, 'expired')
    end)

    H.Test(kind .. ': bill → pay flow, tips, replay protection and bill changes', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1, cash = 1000, bank = 5000 })
        H.Player({ id = 2 })
        H.Seat(1)
        H.Seat(2)
        H.Ok(H.Order(1, { { id = 'fries', qty = 2 }, { id = 'beer_draft', qty = 1 } }))
        local subtotal = product('fries').price * 2 + product('beer_draft').price
        local bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        H.Eq(bill.subtotal, subtotal, 'bill subtotal')
        H.True(type(bill.token) == 'string', 'token issued')

        H.Fails(MOCK.Call(2, 'pay', { token = bill.token, account = 'cash', tip = 0 }), 'token_invalid', 'foreign token')
        H.True(H.LogContains('payment_token_foreign'), 'foreign token logged')
        bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        H.Fails(MOCK.Call(1, 'pay', { token = bill.token, account = 'cash', tip = 7 }), 'tip_invalid', 'unknown tip')
        bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        if money then
            H.Fails(MOCK.Call(1, 'pay', { token = bill.token, account = 'crypto', tip = 0 }), 'account_invalid', 'unknown account')
            bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        end

        -- bill changes between viewing and paying
        MOCK.Advance(11000) -- stay inside the pay / getBill rate limits
        H.Ok(H.Order(1, { { id = 'water', qty = 1 } }))
        H.Fails(MOCK.Call(1, 'pay', { token = bill.token, account = 'cash', tip = 0 }), 'bill_changed', 'stale bill')
        subtotal = subtotal + product('water').price

        MOCK.Advance(11000)
        if money then
            H.SetBalance(1, 'cash', 5)
            bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
            H.Fails(MOCK.Call(1, 'pay', { token = bill.token, account = 'cash', tip = 0 }), 'insufficient_funds', 'not enough cash')
            H.Eq(Orders.UnpaidTotalFor(1), subtotal, 'still unpaid after failure')
            H.Eq(H.Balance(1, 'cash'), 5, 'nothing charged')
        end

        MOCK.Advance(11000)
        bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        local tip = math.floor(subtotal * 10 / 100 + 0.5)
        local bank = H.Balance(1, 'bank')
        local paid = H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'bank', tip = 10 })).data
        if money then
            H.Eq(paid.total, subtotal + tip, 'total with tip')
            H.Eq(H.Balance(1, 'bank'), bank - subtotal - tip, 'bank charged exactly once')
        else
            H.True(paid.free, 'standalone bill is free')
        end
        H.Eq(Orders.UnpaidTotalFor(1), 0, 'nothing left to pay')
        H.Fails(MOCK.Call(1, 'pay', { token = bill.token, account = 'bank', tip = 10 }), 'token_invalid', 'replayed token')
        if money then H.Eq(H.Balance(1, 'bank'), bank - subtotal - tip, 'no double charge') end
        local empty = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        H.True(empty.empty, 'empty bill afterwards')
    end)

    H.Test(kind .. ': table bill — only the host pays for everyone', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 2 })
        local tableId = H.Seat(1)
        H.AtTable(2, tableId)
        H.Ok(MOCK.Call(1, 'invite', { target = 2 }))
        H.Ok(MOCK.Call(2, 'sit', { tableId = tableId }))
        H.Ok(H.Order(1, { { id = 'tea_nana', qty = 2 } }))
        H.Ok(H.Order(2, { { id = 'whiskey', qty = 1 } }))
        H.Fails(MOCK.Call(2, 'getBill', { mode = 'table' }), 'not_table_payer', 'guest table bill')
        local bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'table' })).data
        H.Eq(bill.subtotal, product('tea_nana').price * 2 + product('whiskey').price, 'whole table')
        H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'cash', tip = 0 }))
        H.Eq(Orders.UnpaidTotalFor(2), 0, 'guest covered')
        H.Eq(Orders.UnpaidTotalForTable(tableId), 0, 'table settled')
    end)

    H.Test(kind .. ': leaving requires a settled bill; table goes to cleaning then free', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        local tableId = H.Seat(1)
        H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }))
        H.Fails(MOCK.Call(1, 'leaveTable', {}), 'unpaid_bill_leave', 'unpaid')
        local bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'cash', tip = 0 }))
        H.Ok(MOCK.Call(1, 'leaveTable', {}))
        H.Eq(Tables.Get(tableId).status, 'cleaning', 'cleaning')
        MOCK.Advance((Config.TableSettings.cleaningTime + 1) * 1000)
        H.Eq(Tables.Get(tableId).status, 'free', 'free after cleaning')
    end)

    H.Test(kind .. ': ownership transfers when the host leaves', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 2 })
        local tableId = H.Seat(1)
        H.AtTable(2, tableId)
        H.Ok(MOCK.Call(1, 'invite', { target = 2 }))
        H.Ok(MOCK.Call(2, 'sit', { tableId = tableId }))
        H.Ok(MOCK.Call(1, 'leaveTable', {}))
        H.Eq(Tables.Get(tableId).owner, 2, 'guest is the new host')
        H.Eq(Tables.Get(tableId).status, 'occupied', 'table stays occupied')
    end)

    H.Test(kind .. ': disconnect with an open bill voids it, logs it and frees the table', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        local tableId = H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'wings_bbq', qty = 1 } }))
        MOCK.RemovePlayer(1)
        H.Eq(Orders.byId[r.data.id].paymentStatus, 'void', 'order voided')
        H.True(H.LogContains('Left with an unpaid bill'), 'walkout logged')
        H.True(Tables.Get(tableId).status == 'cleaning' or Tables.Get(tableId).status == 'free', 'table released')
    end)

    H.Test(kind .. ': walking away — removed without a bill, voided after the grace period with one', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 2 })
        H.Seat(1)
        H.Seat(2)
        H.Ok(H.Order(2, { { id = 'beer_bottle', qty = 1 } }))
        H.Far(1)
        H.Far(2)
        local s = Config.TableSettings
        MOCK.Advance((s.awayTimeout + 10) * 1000)
        H.True(Tables.Of(1) == nil, 'player without a bill removed')
        H.True(Tables.Of(2) ~= nil, 'player with a bill kept during grace')
        MOCK.Advance((s.walkoutGrace + 10) * 1000)
        H.True(Tables.Of(2) == nil, 'removed after grace')
        H.Eq(Orders.UnpaidTotalFor(2), 0, 'bill voided')
        H.True(H.LogContains('Walkout'), 'walkout logged')
    end)

    H.Test(kind .. ': security — unknown callbacks, bad payloads, rate limits, handler errors', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Fails(MOCK.Call(1, 'giveMeMoney', {}), 'invalid_request', 'unknown callback')
        H.True(H.LogContains('callback_unknown'), 'unknown callback logged')
        MOCK.nextRequest = MOCK.nextRequest + 1
        local id = MOCK.nextRequest
        MOCK.FromClient(1, 'cyphercity-hookah:cb:request', 'getState', id, 'not-a-table')
        local reply = MOCK.EventsFor('cyphercity-hookah:cb:response', 1)
        H.Eq(reply[#reply].args[2].code, 'invalid_request', 'string payload')
        local limited = false
        for _ = 1, 12 do
            local r = MOCK.Call(1, 'getBill', { mode = 'personal' })
            if r and r.code == 'rate_limited' then limited = true break end
        end
        H.True(limited, 'getBill rate limited')
        local original = Payments.GetBill
        Payments.GetBill = function() error('boom') end
        MOCK.Advance(11000)
        H.Fails(MOCK.Call(1, 'getBill', {}), 'internal_error', 'handler error is contained')
        Payments.GetBill = original
    end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Framework-specific behaviour
-- ═════════════════════════════════════════════════════════════════════════════

local function staffSuite(kind)
    H.Section(('Staff & permissions: %s'):format(kind))

    H.Test(kind .. ': roles come from the job grade; clients cannot grant themselves access', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 10, job = 'hookah', grade = 1, onduty = true })
        H.Player({ id = 11 })
        H.Player({ id = 12, job = 'hookah', grade = 3, isboss = kind ~= 'esx', gradeName = 'boss' })
        H.Player({ id = 13, job = 'hookah', grade = 1, onduty = false })
        for _, id in ipairs({ 10, 11, 12, 13 }) do H.AtHostess(id) end
        H.Eq(Staff.GetRole(10), 'waiter', 'grade 1 → waiter')
        H.Eq(Staff.GetRole(12), 'manager', 'grade 3 → manager')
        H.Fails(MOCK.Call(11, 'staffOpen', {}), 'no_permission', 'customer opens the staff panel')
        H.True(H.LogContains('staff_panel_denied'), 'denied attempt logged')
        H.Fails(MOCK.Call(11, 'staffAction', { action = 'business', open = false }), 'no_permission', 'customer closes the lounge')
        H.Fails(MOCK.Call(13, 'staffOpen', {}), 'off_duty', 'off duty')
        H.Ok(MOCK.Call(10, 'staffOpen', {}), 'waiter panel')

        H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }))
        H.Ok(MOCK.Call(10, 'staffAction', { action = 'orderStatus', orderId = r.data.id, status = 'preparing' }), 'waiter accepts')
        H.Eq(Orders.byId[r.data.id].handler, 10, 'handler recorded')
        H.Fails(MOCK.Call(10, 'staffAction', { action = 'orderStatus', orderId = r.data.id, status = 'new' }), 'order_bad_transition', 'backwards')
        H.Fails(MOCK.Call(10, 'staffAction', { action = 'orderCancel', orderId = r.data.id }), 'no_permission', 'waiter cannot cancel')
        H.Fails(MOCK.Call(10, 'staffAction', { action = 'sales' }), 'no_permission', 'waiter cannot see sales')
        H.Ok(MOCK.Call(10, 'staffAction', { action = 'orderStatus', orderId = r.data.id, status = 'completed' }), 'served')
        H.Eq(Orders.ServedList(1)[1].id, 'cola', 'delivered to the table')

        H.Ok(MOCK.Call(12, 'staffAction', { action = 'sales' }), 'manager sales')
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'logs' }), 'manager logs')
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'business', open = false }), 'manager closes')
        H.True(not Business.IsOpen(), 'closed')
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'business', open = true }))
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'table', tableId = Tables.Of(1).id, op = 'release' }), 'manager releases')
        H.True(Tables.Of(1) == nil, 'customer removed')
        H.Fails(MOCK.Call(10, 'staffAction', { action = 'table', tableId = 2, op = 'reserve', name = 'VIP' }), 'no_permission', 'waiter cannot reserve')
    end)

    H.Test(kind .. ': a waiter takes an order for a table; it goes on the host\'s bill with the kitchen note', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 10, job = 'hookah', grade = 1, onduty = true })
        H.Player({ id = 11, job = 'hookah', grade = 0, onduty = true })
        H.Player({ id = 2 })
        H.AtHostess(10)
        H.AtHostess(11)
        H.AtHostess(2)
        local tableId = H.Seat(1)
        local lines = { { id = 'tea_nana', qty = 2 } }
        H.Fails(MOCK.Call(11, 'staffAction', { action = 'order', tableId = tableId, lines = lines, requestId = 'staff-req-1' }), 'no_permission', 'host role cannot take orders')
        H.Fails(MOCK.Call(2, 'staffAction', { action = 'order', tableId = tableId, lines = lines, requestId = 'staff-req-2' }), 'no_permission', 'customer cannot use it')
        H.Fails(MOCK.Call(10, 'staffAction', { action = 'order', tableId = 3, lines = lines, requestId = 'staff-req-3' }), 'table_unavailable', 'free table')
        local r = H.Ok(MOCK.Call(10, 'staffAction', { action = 'order', tableId = tableId, lines = lines, requestId = 'staff-req-4', note = '<b>הרבה נענע</b>' }))
        H.True(r.message ~= nil, 'confirmation message')
        H.Eq(Orders.UnpaidTotalFor(1), product('tea_nana').price * 2, 'on the host\'s bill')
        local staffView = Orders.StaffList()
        H.Eq(staffView[#staffView].note, 'bהרבה נענע/b', 'note sanitised and shown to staff')
        H.True(staffView[#staffView].placedBy ~= nil, 'waiter recorded')
        H.Fails(MOCK.Call(10, 'staffAction', { action = 'order', tableId = tableId, lines = lines, requestId = 'staff-req-4' }), 'duplicate_request', 'replay')
        local status = H.Ok(MOCK.Call(10, 'staffAction', { action = 'orderStatus', orderId = staffView[#staffView].id, status = 'preparing' }))
        H.True(status.message:find(L('order_status_preparing'), 1, true) ~= nil, 'status shown translated')
    end)

    H.Test(kind .. ': hybrid mode waits for staff, then the kitchen takes over', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 10, job = 'hookah', grade = 1, onduty = true })
        H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'water', qty = 1 } }))
        local order = Orders.byId[r.data.id]
        MOCK.Advance(30000)
        H.Eq(order.status, 'new', 'waits for staff')
        H.True(H.RunUntil(function() return order.status ~= 'new' end, 40000), 'kitchen took over after the grace period')
        H.True(order.auto, 'auto flag')
    end)

    H.Test(kind .. ': staff reserve / seat guest / request payment / clean', function()
        H.BootServer({ framework = kind })
        H.Player({ id = 1 })
        H.Player({ id = 2 })
        H.Player({ id = 12, job = 'hookah', grade = 3, isboss = true, gradeName = 'boss' })
        H.AtHostess(12)
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'table', tableId = 5, op = 'reserve', name = '<b>Danny</b>' }))
        H.Eq(Tables.Get(5).status, 'reserved', 'reserved')
        H.Eq(Tables.Get(5).reservedFor, 'bDanny/b', 'name sanitised')
        H.AtHostess(1)
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'table', tableId = 5, op = 'seat_guest', target = 1 }))
        H.Eq(Tables.Get(5).owner, 1, 'guest seated by staff')
        H.AtTable(1, 5)
        H.Ok(MOCK.Call(1, 'sit', { tableId = 5 }))
        H.Ok(H.Order(1, { { id = 'water', qty = 1 } }))
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'requestPayment', tableId = 5 }))
        H.True(#MOCK.EventsFor('cyphercity-hookah:client:openBill', 1) == 1, 'bill opened for the customer')
        local bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'table' })).data
        H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'cash', tip = 0 }))
        H.Ok(MOCK.Call(1, 'leaveTable', {}))
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'table', tableId = 5, op = 'clean' }))
        H.Eq(Tables.Get(5).status, 'free', 'cleaned')
    end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Payment adapter edge cases and alternative configurations
-- ═════════════════════════════════════════════════════════════════════════════

local function edgeSuite()
    H.Section('Payment adapters & configuration variants')

    H.Test('qbcore: RemoveMoney returning false leaves the bill unpaid', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1, failRemove = true })
        H.Seat(1)
        H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }))
        local bill = H.Ok(MOCK.Call(1, 'getBill', {})).data
        H.Fails(MOCK.Call(1, 'pay', { token = bill.token, account = 'bank', tip = 0 }), 'payment_failed')
        H.True(Orders.UnpaidTotalFor(1) > 0, 'still unpaid')
    end)

    H.Test('qbcore: bank balance is checked before charging (bank may go negative in qb-core)', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1, bank = 3 })
        H.Seat(1)
        H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }))
        local bill = H.Ok(MOCK.Call(1, 'getBill', {})).data
        H.Fails(MOCK.Call(1, 'pay', { token = bill.token, account = 'bank', tip = 0 }), 'insufficient_funds')
        H.Eq(H.Balance(1, 'bank'), 3, 'not charged')
    end)

    H.Test('esx: legacy removeAccountMoney without a return value is verified by balance', function()
        H.BootServer({ framework = 'esx' })
        H.Player({ id = 1, esxLegacyNoReturn = true })
        H.Player({ id = 2, esxLegacyNoReturn = true, esxNoDeduct = true })
        H.Seat(1)
        H.Seat(2)
        H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }))
        H.Ok(H.Order(2, { { id = 'cola', qty = 1 } }))
        local b1 = H.Ok(MOCK.Call(1, 'getBill', {})).data
        H.Ok(MOCK.Call(1, 'pay', { token = b1.token, account = 'cash', tip = 0 }), 'deducted → success')
        local b2 = H.Ok(MOCK.Call(2, 'getBill', {})).data
        H.Fails(MOCK.Call(2, 'pay', { token = b2.token, account = 'cash', tip = 0 }), 'payment_failed', 'not deducted → failure')
        H.True(Orders.UnpaidTotalFor(2) > 0, 'still unpaid')
    end)

    H.Test('on_order timing: charged immediately, no order without money, refund on staff cancel', function()
        H.BootServer({ framework = 'qbcore', config = function(c) c.Payments.timing = 'on_order' end })
        H.Player({ id = 1, cash = 100 })
        H.Player({ id = 12, job = 'hookah', grade = 3, isboss = true })
        H.AtHostess(12)
        H.Seat(1)
        H.Fails(H.Order(1, { { id = 'cola', qty = 1 } }), 'account_invalid', 'no account')
        local count = Utils.Count(Orders.byId)
        H.Fails(H.Order(1, { { id = 'shots_tray', qty = 2 } }, { account = 'cash' }), 'insufficient_funds', 'too expensive')
        H.Eq(Utils.Count(Orders.byId), count, 'no order created')
        local r = H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }, { account = 'cash' }))
        H.Eq(H.Balance(1, 'cash'), 100 - product('cola').price, 'charged on order')
        H.Eq(Orders.byId[r.data.id].paymentStatus, 'paid', 'paid')
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'orderCancel', orderId = r.data.id }))
        H.Eq(H.Balance(1, 'cash'), 100, 'refunded')
        H.Eq(Orders.byId[r.data.id].paymentStatus, 'refunded', 'refund recorded')
    end)

    H.Test('stock: out of stock, restored on cancel, restocked by the manager', function()
        H.BootServer({ framework = 'qbcore', config = function(c)
            c.Stock.enabled = true
            for _, item in ipairs(c.Menu) do if item.id == 'fries' then item.stock = 2 end end
        end })
        H.Player({ id = 1 })
        H.Player({ id = 12, job = 'hookah', grade = 3, isboss = true })
        H.AtHostess(12)
        H.Seat(1)
        H.Fails(H.Order(1, { { id = 'fries', qty = 3 } }), 'out_of_stock', 'more than stock')
        local r = H.Ok(H.Order(1, { { id = 'fries', qty = 2 } }))
        H.Eq(Orders.StockOf('fries'), 0, 'stock used')
        H.Ok(MOCK.Call(1, 'cancelOrder', { orderId = r.data.id }))
        H.Eq(Orders.StockOf('fries'), 2, 'stock restored')
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'restock', productId = 'fries' }))
        H.Eq(Orders.StockOf('fries'), 2 + Config.Stock.restockAmount, 'restocked')
    end)

    H.Test('sales are recorded and saved to data/sales.json', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1 })
        H.Seat(1)
        H.Ok(H.Order(1, { { id = 'whiskey', qty = 2 } }))
        local bill = H.Ok(MOCK.Call(1, 'getBill', {})).data
        H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'bank', tip = 15 }))
        local report = Persistence.Report(7)
        H.Eq(report.today.revenue, product('whiskey').price * 2, 'revenue')
        H.Eq(report.today.tips, math.floor(product('whiskey').price * 2 * 15 / 100 + 0.5), 'tips')
        H.Eq(report.top[1].id, 'whiskey', 'top item')
        Persistence.Save(true)
        local saved = json.decode(MOCK.files['data/sales.json'])
        H.True(saved and saved.days, 'file written')
    end)

    H.Test('on_order timing: staff cannot put orders on someone else\'s tab', function()
        H.BootServer({ framework = 'qbcore', config = function(c) c.Payments.timing = 'on_order' end })
        H.Player({ id = 1 })
        H.Player({ id = 10, job = 'hookah', grade = 1, onduty = true })
        H.AtHostess(10)
        local tableId = H.Seat(1)
        H.Fails(MOCK.Call(10, 'staffAction', { action = 'order', tableId = tableId, lines = { { id = 'cola', qty = 1 } }, requestId = 'staff-onorder-1' }), 'staff_order_on_bill_only')
    end)

    H.Test('customer order note is stored, trimmed to 80 characters and shown in the order list', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1 })
        H.Seat(1)
        H.Ok(H.Order(1, { { id = 'cola', qty = 1 } }, { note = string.rep('א', 120) }))
        local mine = Orders.ForPlayer(1)[1]
        H.Eq(utf8.len(mine.note), 80, 'note trimmed')
        H.Ok(H.Order(1, { { id = 'water', qty = 1 } }, { note = { 'not', 'text' } }))
        H.Eq(Orders.ForPlayer(1)[1].note, nil, 'non-text note ignored')
    end)

    H.Test('standalone: ACE roles work without a framework', function()
        H.BootServer({ framework = 'standalone' })
        H.Player({ id = 1, aces = { ['cyphercity.hookah.manager'] = true } })
        H.Player({ id = 2 })
        H.AtHostess(1)
        H.AtHostess(2)
        H.Eq(Staff.GetRole(1), 'manager', 'ACE manager')
        H.Ok(MOCK.Call(1, 'staffOpen', {}))
        H.Fails(MOCK.Call(2, 'staffOpen', {}), 'no_permission')
    end)

    H.Test('standalone with free orders disabled blocks ordering', function()
        H.BootServer({ framework = 'standalone', config = function(c) c.Standalone.allowFreeOrders = false end })
        H.Player({ id = 1 })
        H.Seat(1)
        H.Fails(H.Order(1, { { id = 'water', qty = 1 } }), 'payments_disabled')
    end)

    H.Test('detection: a framework that exists but is stopped stops the start-up', function()
        H.BootServer({ overrideResources = { es_extended = 'stopped' } })
        H.True(not Server.ready, 'not ready')
        H.True(Server.failure and Server.failure:find('es_extended', 1, true) ~= nil, 'failure names the resource')
        H.Player({ id = 1 })
        H.Fails(MOCK.Call(1, 'getState', {}), 'not_ready', 'callbacks refuse while not ready')
    end)

    H.Test('detection: waits for a framework that is still starting', function()
        H.BootServer({
            framework = 'esx',
            overrideResources = { es_extended = 'starting' },
            beforeLoad = function()
                SetTimeout(2000, function() MOCK.resources.es_extended = 'started' end)
            end,
        })
        H.True(not Server.ready, 'waiting')
        MOCK.Advance(3000)
        H.True(Server.ready, 'ready once es_extended started')
        H.Eq(Bridge.framework, 'esx', 'esx')
    end)

    H.Test('detection: explicit Config.Framework that is missing fails clearly', function()
        H.BootServer({ config = function(c) c.Framework = 'qbcore' end })
        H.True(not Server.ready, 'not ready')
        H.True(Server.failure:find('qb-core', 1, true) ~= nil, 'mentions qb-core')
    end)

    H.Test('inventory: menu items pointing at missing inventory items are ignored with a warning', function()
        H.BootServer({
            framework = 'qbcore',
            config = function(c)
                c.Inventory = 'qb-inventory'
                for _, item in ipairs(c.Menu) do
                    if item.id == 'beer_bottle' then item.inventory = { give = { name = 'beer', count = 1 } } end
                    if item.id == 'cola' then item.inventory = { give = { name = 'does_not_exist', count = 1 } } end
                end
            end,
            resources = { ['qb-inventory'] = 'started' },
            beforeLoad = function()
                MOCK.given = nil
                MOCK.exports['qb-inventory'] = {
                    GetItemCount = function() return 0 end,
                    CanAddItem = function() return true end,
                    AddItem = function(_, src, item, count) MOCK.given = { src = src, item = item, count = count } return true end,
                    RemoveItem = function() return true end,
                }
            end,
        })
        H.Eq(Bridge.inventory, 'qb-inventory', 'adapter')
        H.True(product('cola').inventory.give.disabled, 'missing item disabled')
        H.True(not product('beer_bottle').inventory.give.disabled, 'existing item kept')
        H.Player({ id = 1 })
        H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'beer_bottle', qty = 2 }, { id = 'cola', qty = 1 } }))
        local order = Orders.byId[r.data.id]
        H.RunUntil(function() return order.status == 'completed' end, 60000)
        H.True(MOCK.given == nil, 'real items are held back until the bill is paid')
        H.Eq(Orders.ServedList(1)[1].id, 'cola', 'missing item served to the table instead')
        local bill = H.Ok(MOCK.Call(1, 'getBill', {})).data
        H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'bank', tip = 0 }))
        H.True(MOCK.given and MOCK.given.item == 'beer' and MOCK.given.count == 2, 'real item given after payment')
    end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Regression tests for the independent code review findings
-- ═════════════════════════════════════════════════════════════════════════════

local function installQbBanking()
    MOCK.society = {}
    MOCK.resources['qb-banking'] = 'started'
    MOCK.exports['qb-banking'] = {
        GetAccount = function(_, account) return MOCK.society[account] and { balance = MOCK.society[account] } or nil end,
        CreateJobAccount = function(_, account, balance) MOCK.society[account] = balance return true end,
        AddMoney = function(_, account, amount) MOCK.society[account] = (MOCK.society[account] or 0) + amount return true end,
        RemoveMoney = function(_, account, amount) MOCK.society[account] = (MOCK.society[account] or 0) - amount return true end,
    }
end

local function reviewSuite()
    H.Section('Review findings (regressions)')

    H.Test('refunds: customer cannot cancel a paid order; staff refund returns tip and reverses society + stats', function()
        H.BootServer({
            framework = 'qbcore',
            config = function(c) c.Payments.society = { enabled = true, system = 'qb-banking', account = 'hookah' } end,
            beforeLoad = installQbBanking,
        })
        H.Player({ id = 1, bank = 5000 })
        H.Player({ id = 12, job = 'hookah', grade = 3, isboss = true })
        H.AtHostess(12)
        H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'whiskey', qty = 2 } }))
        local bill = H.Ok(MOCK.Call(1, 'getBill', {})).data
        H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'bank', tip = 10 }))
        local paid = product('whiskey').price * 2
        local tip = math.floor(paid * 10 / 100 + 0.5)
        H.Eq(H.Balance(1, 'bank'), 5000 - paid - tip, 'charged')
        H.Eq(MOCK.society.hookah, paid + tip, 'society deposit')
        H.Fails(MOCK.Call(1, 'cancelOrder', { orderId = r.data.id }), 'order_cannot_cancel', 'customer pay → cancel')
        H.Ok(MOCK.Call(12, 'staffAction', { action = 'orderCancel', orderId = r.data.id }))
        H.Eq(H.Balance(1, 'bank'), 5000, 'refund includes the tip share')
        H.Eq(MOCK.society.hookah, 0, 'society deposit taken back')
        H.Eq(Persistence.Report(1).today.revenue, 0, 'revenue reversed')
        H.Eq(Persistence.Report(1).today.tips, 0, 'tips reversed')
    end)

    H.Test('invites: an old invite does not open the next party\'s table', function()
        H.BootServer({ framework = 'qbcore' })
        for id = 1, 3 do H.Player({ id = id }) end
        local tableId = H.Seat(1)
        H.AtTable(2, tableId)
        H.Ok(MOCK.Call(1, 'invite', { target = 2 }))
        H.Ok(MOCK.Call(1, 'leaveTable', {}))
        MOCK.Advance((Config.TableSettings.cleaningTime + 2) * 1000)
        H.Eq(H.Seat(3), tableId, 'next party gets the same table')
        H.AtTable(2, tableId)
        H.Fails(MOCK.Call(2, 'sit', { tableId = tableId }), 'not_your_table', 'stale invite rejected')
        H.Eq(#Tables.InvitesFor(2), 0, 'stale invite no longer listed')
    end)

    H.Test('flood: hundreds of made-up callback names do not push real entries out of the log', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1 })
        Logger.Warn('security', 'MARKER real alert')
        for i = 1, 300 do MOCK.Call(1, 'fake_' .. i, {}) end
        H.True(H.LogContains('MARKER real alert'), 'earlier entry still in the log')
        local count = 0
        for _, entry in ipairs(Logger.Recent(500)) do if entry.category == 'security' then count = count + 1 end end
        H.True(count < 10, 'flood produced only a few log lines (' .. count .. ')')
    end)

    H.Test('requireBillBeforeLeave = false: leaving keeps the bill as a personal tab (not voided)', function()
        H.BootServer({ framework = 'qbcore', config = function(c) c.Payments.requireBillBeforeLeave = false end })
        H.Player({ id = 1 })
        H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'fries', qty = 1 } }))
        H.RunUntil(function() return Orders.byId[r.data.id].status == 'completed' end, 60000)
        H.Ok(MOCK.Call(1, 'leaveTable', {}))
        H.Eq(Orders.byId[r.data.id].paymentStatus, 'unpaid', 'still owed')
        local bill = H.Ok(MOCK.Call(1, 'getBill', { mode = 'personal' })).data
        H.Eq(bill.subtotal, product('fries').price, 'can still pay it')
    end)

    H.Test('bar orders (allowWithoutTable): reservation expiry does not void them; walking out is tracked', function()
        H.BootServer({ framework = 'qbcore', config = function(c) c.Orders.allowWithoutTable = true end })
        H.Player({ id = 1 })
        H.AtHostess(1)
        local r = H.Ok(H.Order(1, { { id = 'beer_draft', qty = 1 } }))
        H.Ok(MOCK.Call(1, 'requestTable', { partySize = 2 }))
        MOCK.Advance((Config.TableSettings.reserveTimeout + 2) * 1000)
        H.Eq(Orders.byId[r.data.id].paymentStatus, 'unpaid', 'bar tab survives the reservation expiry')
        H.Far(1)
        MOCK.Advance((Config.TableSettings.awayTimeout + Config.TableSettings.walkoutGrace + 15) * 1000)
        H.Eq(Orders.byId[r.data.id].paymentStatus, 'void', 'voided after walking out')
        H.True(H.LogContains('Walkout'), 'walkout logged')
    end)

    H.Test('character switch without disconnecting closes the previous character\'s table and bill', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1, bank = 5000 })
        local tableId = H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'shots_tray', qty = 1 } }))
        H.store[1].PlayerData.citizenid = 'OTHER-CHARACTER'
        H.store[1].PlayerData.money.bank = 300
        local state = H.Ok(MOCK.Call(1, 'getState', {})).data
        H.True(state.tableId == nil, 'new character is not at the old table')
        H.Eq(Orders.UnpaidTotalFor(1), 0, 'new character does not inherit the bill')
        H.Eq(Orders.byId[r.data.id].paymentStatus, 'void', 'old bill voided')
        H.True(H.LogContains('character_switch'), 'logged')
        H.True(Tables.Get(tableId).status ~= 'occupied', 'table released')
    end)

    H.Test('table tick survives a release in the middle of the away check', function()
        H.BootServer({ framework = 'qbcore', config = function(c) c.TableSettings.ownerDropBehaviour = 'release' end })
        for id = 1, 3 do H.Player({ id = id }) end
        local tableId = H.Seat(1)
        for _, id in ipairs({ 2, 3 }) do
            H.AtTable(id, tableId)
            H.Ok(MOCK.Call(1, 'invite', { target = id }))
            H.Ok(MOCK.Call(id, 'sit', { tableId = tableId }))
        end
        for id = 1, 3 do H.Far(id) end
        MOCK.Advance((Config.TableSettings.awayTimeout + 15) * 1000)
        for id = 1, 3 do H.True(Tables.Of(id) == nil, 'player ' .. id .. ' removed') end
    end)

    H.Test('a new party does not see the previous party\'s orders', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1 })
        H.Player({ id = 2 })
        local tableId = H.Seat(1)
        H.Ok(H.Order(1, { { id = 'water', qty = 1 } }))
        local bill = H.Ok(MOCK.Call(1, 'getBill', {})).data
        H.Ok(MOCK.Call(1, 'pay', { token = bill.token, account = 'cash', tip = 0 }))
        H.Ok(MOCK.Call(1, 'leaveTable', {}))
        MOCK.Advance((Config.TableSettings.cleaningTime + 2) * 1000)
        H.Eq(H.Seat(2), tableId, 'same table')
        H.Eq(#Orders.ForPlayer(2), 0, 'previous party hidden')
        H.Eq(Orders.UnpaidTotalForTable(tableId), 0, 'nothing carried over')
    end)

    H.Test('flavour changes cannot extend a hookah forever', function()
        H.BootServer({ framework = 'qbcore' })
        H.Player({ id = 1, bank = 50000 })
        local tableId = H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'hookah_classic', qty = 1, flavors = { 'double_apple' } } }))
        H.RunUntil(function() return Orders.byId[r.data.id].status == 'completed' end, 120000)
        local session = Hookah.ForTable(tableId)[1]
        for _ = 1, Config.Hookah.coalRefresh.maxRefreshes do
            H.Ok(MOCK.Call(1, 'hookahAction', { action = 'flavor', sessionId = session.id, flavors = { 'grape_mint' } }))
        end
        H.Fails(MOCK.Call(1, 'hookahAction', { action = 'flavor', sessionId = session.id, flavors = { 'lemon_mint' } }), 'hookah_max_refresh')
    end)

    H.Test('inventory items are not handed out when the customer disconnects before paying', function()
        H.BootServer({
            framework = 'qbcore',
            config = function(c)
                c.Inventory = 'qb-inventory'
                for _, item in ipairs(c.Menu) do
                    if item.id == 'beer_bottle' then item.inventory = { give = { name = 'beer', count = 1 } } end
                end
            end,
            resources = { ['qb-inventory'] = 'started' },
            beforeLoad = function()
                MOCK.given = nil
                MOCK.exports['qb-inventory'] = {
                    GetItemCount = function() return 0 end,
                    CanAddItem = function() return true end,
                    AddItem = function(_, src, item, count) MOCK.given = { src = src, item = item, count = count } return true end,
                    RemoveItem = function() return true end,
                }
            end,
        })
        H.Player({ id = 1 })
        H.Seat(1)
        local r = H.Ok(H.Order(1, { { id = 'beer_bottle', qty = 3 } }))
        H.RunUntil(function() return Orders.byId[r.data.id].status == 'completed' end, 60000)
        MOCK.RemovePlayer(1)
        H.True(MOCK.given == nil, 'no free items')
    end)
end

for _, kind in ipairs({ 'qbcore', 'qbox', 'esx', 'standalone' }) do
    frameworkSuite(kind)
end
for _, kind in ipairs({ 'qbcore', 'qbox', 'esx' }) do
    staffSuite(kind)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- In-game placement tool (/hookahsetup)
-- ═════════════════════════════════════════════════════════════════════════════

local function setupSuite()
    H.Section('Placement tool (/hookahsetup)')

    local ADMIN_ACE = 'cyphercity.hookah.admin'
    local BASE = { x = -1200.0, y = -880.0, z = 13.0 } -- far away from the demo venue in config.lua
    local LAYOUT_FILE = 'data/layout.json'

    local function admin(id) return H.Player({ id = id, aces = { [ADMIN_ACE] = true } }) end
    local function stand(src, dx, dy, heading)
        MOCK.Move(src, vec3(BASE.x + dx, BASE.y + dy, BASE.z))
        MOCK.players[src].heading = heading or 0.0
    end
    local function act(src, payload)
        MOCK.Advance(600) -- stay inside the setup rate limit
        return MOCK.Call(src, 'setupAction', payload)
    end
    local function near(a, b, eps) return math.abs(a - b) < (eps or 0.011) end

    -- hostess, one waiter, table 1 with two seats facing each other and one hookah spot
    local function placeFullLayout(src)
        H.Ok(MOCK.Call(src, 'setupOpen', {}), 'open')
        stand(src, 0, 0, 180.0)
        H.Ok(act(src, { action = 'hostess' }), 'hostess')
        stand(src, 6, 0, 90.0)
        H.Ok(act(src, { action = 'waiter_add' }), 'waiter')
        local tableId = H.Ok(act(src, { action = 'table_add' }), 'table').data.selected
        stand(src, 3, 5, 0.0)
        H.Ok(act(src, { action = 'seat_add', tableId = tableId }), 'seat 1')
        stand(src, 3, 7, 180.0)
        H.Ok(act(src, { action = 'seat_add', tableId = tableId }), 'seat 2')
        stand(src, 4, 6, 0.0)
        H.Ok(act(src, { action = 'spot_add', tableId = tableId }), 'spot')
        return tableId
    end

    H.Test('setup: only server admins (ACE) can use the placement tool — not even Debug mode opens it', function()
        H.BootServer({ framework = 'standalone', config = function(c) c.Debug = true end })
        H.Player({ id = 1 })
        stand(1, 0, 0)
        H.Fails(MOCK.Call(1, 'setupOpen', {}), 'setup_not_allowed', 'open')
        H.Fails(act(1, { action = 'hostess' }), 'setup_not_allowed', 'action')
        H.True(H.LogContains('setup_denied'), 'attempt logged as a security event')
        H.True(MOCK.files[LAYOUT_FILE] == nil, 'nothing saved')
        admin(2)
        H.Ok(MOCK.Call(2, 'setupOpen', {}), 'admin opens')
    end)

    H.Test('setup: a draft is saved but does not change the running lounge until it is complete', function()
        H.BootServer({ framework = 'qbcore' })
        admin(1)
        local hostessBefore = Config.Hostess.coords
        local r = H.Ok(MOCK.Call(1, 'setupOpen', {}))
        H.Eq(r.data.active, false, 'starts as draft')
        H.Eq(#r.data.missing, 3, 'hostess, waiter and table missing')
        stand(1, 0, 0, 180.0)
        r = H.Ok(act(1, { action = 'hostess' }))
        H.Eq(r.message, L('setup_hostess_set'), 'message')
        H.True(MOCK.files[LAYOUT_FILE] ~= nil and MOCK.files[LAYOUT_FILE]:find('hostess', 1, true) ~= nil, 'draft saved to the file')
        H.Eq(Config.Hostess.coords, hostessBefore, 'live hostess position unchanged')
        H.Eq(Layout.active, false, 'still a draft')
        H.Eq(#MOCK.EventsFor('cyphercity-hookah:client:layout'), 0, 'nothing broadcast for a draft')
        stand(1, 6, 0, 90.0)
        H.Ok(act(1, { action = 'waiter_add' }))
        local tableId = H.Ok(act(1, { action = 'table_add' })).data.selected
        H.Eq(tableId, 1, 'first table id')
        stand(1, 3, 5, 0.0)
        H.Fails(act(1, { action = 'seat_add' }), 'setup_select_table', 'seat without a table')
        r = H.Ok(act(1, { action = 'seat_add', tableId = tableId }))
        H.Eq(r.message, L('setup_activated', Config.Business.name), 'activation message')
        H.True(Layout.active and r.data.active, 'active once complete')
        -- the lounge now runs on the placed points
        H.True(near(Config.Hostess.coords.x, BASE.x) and near(Config.Hostess.coords.w, 180.0), 'hostess moved')
        H.Eq(#Config.Tables, 1, 'tables from the layout')
        H.Eq(#Tables.list, 1, 'server tables rebuilt')
        H.Eq(Tables.Get(1).seatCount, 1, 'one seat')
        local seat = Config.Tables[1].seats[1]
        H.True(near(seat.x, BASE.x + 3) and near(seat.y, BASE.y + 5 - 0.35), 'seat saved behind the admin (back to the chair)')
        H.Eq(Config.Venue.snapToGround, false, 'no ground snapping for placed points')
        H.True(Utils.Dist2D(Config.Venue.center, vec3(BASE.x, BASE.y, BASE.z)) < 10, 'venue centre moved')
        H.True(Config.Staff.managementPoint == nil, 'no staff point from config.lua at the new place')
        local events = MOCK.EventsFor('cyphercity-hookah:client:layout', -1)
        H.Eq(#events, 1, 'layout broadcast to everyone')
        H.True(events[1].args[1].layout and events[1].args[1].revision, 'payload has layout + revision')
        -- and works for a customer
        H.Player({ id = 2 })
        H.Eq(H.Seat(2, 1), 1, 'customer gets the placed table')
    end)

    H.Test('setup: duplicate, far-away and invalid points are refused; limits apply', function()
        H.BootServer({ framework = 'standalone' })
        admin(1)
        local tableId = placeFullLayout(1)
        stand(1, 4, 6, 0.0)
        H.Fails(act(1, { action = 'spot_add', tableId = tableId }), 'setup_too_close', 'same spot twice')
        MOCK.Move(1, vec3(BASE.x + 600, BASE.y, BASE.z))
        H.Fails(act(1, { action = 'waiter_add' }), 'setup_too_far', 'another part of the map')
        MOCK.Move(1, vec3(0, 0, 0))
        H.Fails(act(1, { action = 'waiter_add' }), 'setup_no_position', 'position unknown')
        H.Fails(act(1, { action = 'teleport' }), 'invalid_request', 'unknown action')
        H.Fails(act(1, { action = 'table_update', tableId = tableId, label = '   ' }), 'setup_label_invalid', 'empty label')
        H.Fails(act(1, { action = 'seat_add', tableId = 99 }), 'setup_select_table', 'unknown table')
        H.Ok(act(1, { action = 'table_update', tableId = tableId, label = '<b>ספה</b>', vip = true, seatZ = 5 }))
        local t = Layout.FindTable(Layout.data, tableId)
        H.Eq(t.label, 'bספה/b', 'label sanitised')
        H.Eq(t.vip, true, 'vip')
        H.Eq(t.seatZ, Layout.SEAT_Z, 'seat height clamped')
        H.Eq(Config.Tables[1].seatZ, Layout.SEAT_Z, 'seat height reaches Config.Tables')
        for i = 1, Layout.MAX.waiters - 1 do
            stand(1, 6, i * 1.5, 90.0)
            H.Ok(act(1, { action = 'waiter_add' }), 'waiter ' .. (i + 1))
        end
        stand(1, -6, 0, 90.0)
        H.Fails(act(1, { action = 'waiter_add' }), 'setup_limit', 'waiter limit')
        H.Eq(#Config.Waiters, Layout.MAX.waiters, 'waiters applied')
        local served = 0
        for _, w in ipairs(Config.Waiters) do served = served + #w.tables end
        H.Eq(served, #Config.Tables, 'every table has exactly one waiter')
    end)

    H.Test('setup: tables with guests are never changed under them; the rest of the layout can be', function()
        H.BootServer({ framework = 'qbcore' })
        admin(1)
        local tableId = placeFullLayout(1)
        H.Player({ id = 2 })
        H.Seat(2, 2)
        local t = Tables.Get(tableId)
        local session = t.session
        stand(1, 1, 6, 90.0)
        for _, payload in ipairs({
            { action = 'seat_add', tableId = tableId },
            { action = 'seat_remove', tableId = tableId },
            { action = 'spot_remove', tableId = tableId },
            { action = 'seat_nudge', tableId = tableId, index = 1, forward = 0.1 },
            { action = 'reset' },
        }) do
            H.Fails(act(1, payload), 'setup_table_busy', payload.action)
        end
        H.Ok(act(1, { action = 'table_update', tableId = tableId, label = 'שולחן הספה' }), 'rename is fine')
        stand(1, 0, -1, 180.0)
        H.Ok(act(1, { action = 'hostess' }), 'moving the hostess is fine')
        local second = H.Ok(act(1, { action = 'table_add' })).data.selected
        stand(1, 10, 5, 0.0)
        H.Ok(act(1, { action = 'seat_add', tableId = second }), 'new table next to it is fine')
        t = Tables.Get(tableId)
        H.Eq(t.label, 'שולחן הספה', 'label updated in place')
        H.Eq(t.status, 'occupied', 'still occupied')
        H.Eq(t.session, session, 'same party session')
        H.True(Tables.Of(2) == t, 'guest still at the table')
        H.Eq(#Tables.list, 2, 'two tables')
        H.Fails(act(1, { action = 'table_remove', tableId = tableId }), 'setup_table_busy', 'deleting the occupied table')
        H.Eq(#Layout.data.tables, 2, 'no table was deleted instead')
        H.Ok(act(1, { action = 'table_remove', tableId = second }), 'the free table can be deleted')
        H.True(Layout.FindTable(Layout.data, tableId) ~= nil and Layout.FindTable(Layout.data, second) == nil, 'exactly the chosen table was deleted')
        H.Eq(#Tables.list, 1, 'one table left')
        -- once the guests have left and the table is clean, it can be edited again
        H.Ok(MOCK.Call(2, 'leaveTable', {}))
        H.RunUntil(function() return Tables.Get(tableId).status == 'free' end, 120000)
        stand(1, 1, 6, 90.0)
        H.Ok(act(1, { action = 'seat_add', tableId = tableId }), 'free table can change')
        H.Eq(Tables.Get(tableId).seatCount, 3, 'third seat live')
        H.Eq(Tables.Get(tableId).session, session, 'session counter kept (no mix-up with old orders)')
    end)

    H.Test('setup: a hostess placed in the wrong place can be moved to the right one', function()
        H.BootServer({ framework = 'standalone' })
        admin(1)
        H.Ok(MOCK.Call(1, 'setupOpen', {}))
        MOCK.Move(1, vec3(195.0, -935.0, 29.7)) -- by mistake at the demo square
        H.Ok(act(1, { action = 'hostess' }))
        stand(1, 0, 0, 180.0)
        H.Ok(act(1, { action = 'hostess' }), 'moved far away to the real venue')
        H.True(near(Layout.data.hostess[1], BASE.x), 'hostess at the real venue')
        stand(1, 6, 0, 90.0)
        H.Ok(act(1, { action = 'waiter_add' }), 'the rest is measured from the new spot')
    end)

    H.Test('setup: guests at the far tables of a large venue are not treated as having left', function()
        H.BootServer({ framework = 'qbcore' })
        admin(1)
        H.Ok(MOCK.Call(1, 'setupOpen', {}))
        stand(1, 0, 0, 180.0)
        H.Ok(act(1, { action = 'hostess' }))
        stand(1, 2, 0, 90.0)
        H.Ok(act(1, { action = 'waiter_add' }))
        local near1 = H.Ok(act(1, { action = 'table_add' })).data.selected
        stand(1, 0, 4, 0.0)
        H.Ok(act(1, { action = 'seat_add', tableId = near1 }))
        local far = H.Ok(act(1, { action = 'table_add' })).data.selected
        stand(1, 0, 110, 0.0) -- a long hall: this table is ~55 m from the centre
        H.Ok(act(1, { action = 'seat_add', tableId = far }))
        H.True(Config.Venue.radius > Config.TableSettings.awayDistance, 'venue larger than awayDistance')
        H.Player({ id = 2 })
        H.AtHostess(2)
        MOCK.Advance(16000)
        H.Ok(MOCK.Call(2, 'requestTable', { partySize = 1 }))
        local t = Tables.Of(2)
        H.AtTable(2, t.id)
        H.Ok(MOCK.Call(2, 'sit', { tableId = t.id }))
        -- seat the guest at the far table explicitly
        if t.id ~= far then
            H.Ok(MOCK.Call(2, 'leaveTable', {}))
            Tables.Get(near1).status = 'occupied' -- keep the near table busy so the hostess picks the far one
            H.AtHostess(2)
            MOCK.Advance(16000)
            H.Ok(MOCK.Call(2, 'requestTable', { partySize = 1 }))
            t = Tables.Of(2)
            H.AtTable(2, t.id)
            H.Ok(MOCK.Call(2, 'sit', { tableId = t.id }))
        end
        H.Eq(t.id, far, 'guest at the far table')
        MOCK.Advance((Config.TableSettings.awayTimeout + 30) * 1000)
        H.True(Tables.Of(2) == t, 'still at the table after the away timeout')
    end)

    H.Test('setup: a running layout always keeps a hostess, a waiter and a table with a seat', function()
        H.BootServer({ framework = 'standalone' })
        admin(1)
        local tableId = placeFullLayout(1)
        H.Fails(act(1, { action = 'waiter_remove' }), 'setup_keep_waiter', 'last waiter')
        H.Fails(act(1, { action = 'table_remove', tableId = tableId }), 'setup_keep_table', 'last table')
        H.Ok(act(1, { action = 'seat_remove', tableId = tableId }), 'one of two seats')
        H.Fails(act(1, { action = 'seat_remove', tableId = tableId }), 'setup_keep_table', 'last seat')
        H.Fails(act(1, { action = 'manager_clear' }), 'setup_nothing_to_remove', 'no staff point yet')
        stand(1, 6, 2, 0.0)
        H.Ok(act(1, { action = 'manager' }), 'staff point')
        H.True(Config.Staff.managementPoint and near(Config.Staff.managementPoint.coords.y, BASE.y + 2), 'staff point applied')
        H.Ok(act(1, { action = 'manager_clear' }), 'staff point removed')
        H.True(Config.Staff.managementPoint == nil, 'staff point gone')
    end)

    H.Test('setup: switching between config.lua and the layout never restarts table session numbers', function()
        H.BootServer({ framework = 'qbcore' })
        admin(1)
        H.Player({ id = 2 })
        -- use config.lua table 2 once, so it has a party session behind it
        for _ = 1, 2 do
            H.AtHostess(2)
            MOCK.Advance(16000)
            H.Ok(MOCK.Call(2, 'requestTable', { partySize = 1 }))
            H.Ok(MOCK.Call(2, 'leaveTable', {}))
        end
        H.RunUntil(function()
            for _, t in ipairs(Tables.list) do if t.status ~= 'free' then return false end end
            return true
        end, 120000)
        local used = {}
        for _, t in ipairs(Tables.list) do if t.session > 0 then used[t.id] = t.session end end
        H.True(next(used) ~= nil, 'a config table was used')
        placeFullLayout(1)
        H.Eq(#Tables.list, 1, 'layout has one table')
        H.Ok(act(1, { action = 'reset' }))
        H.Eq(#Tables.list, 6, 'config tables back')
        for id, session in pairs(used) do
            H.Eq(Tables.Get(id).session, session, 'table ' .. id .. ' keeps its session counter')
        end
    end)

    H.Test('setup: the layout survives a restart; broken or hostile files are ignored safely', function()
        H.BootServer({ framework = 'standalone' })
        admin(1)
        placeFullLayout(1)
        local saved = MOCK.files[LAYOUT_FILE]
        H.True(saved and #saved > 0, 'file written')

        H.BootServer({ framework = 'standalone', beforeLoad = function() MOCK.files[LAYOUT_FILE] = saved end })
        H.True(Layout.active, 'active after restart')
        H.True(near(Config.Hostess.coords.x, BASE.x), 'hostess from the file')
        H.Eq(#Tables.list, 1, 'tables from the file')
        H.Eq(Tables.Get(1).hookahSpots, 1, 'hookah spot from the file')

        H.BootServer({ framework = 'standalone', beforeLoad = function() MOCK.files[LAYOUT_FILE] = '{not json' end })
        H.True(Server.ready, 'boots with a broken file')
        H.Eq(Layout.active, false, 'broken file ignored')
        H.Eq(#Tables.list, 6, 'config.lua tables')

        local hostile = {
            hostess = { 1e12, 0, 0 },
            waiters = { { 'x', 1, 2 }, { BASE.x, BASE.y, BASE.z, 'north' } },
            tables = {},
            nextId = -5,
        }
        for i = 1, 200 do
            hostile.tables[i] = { id = (i % 3 == 0) and 1 or i, label = string.rep('<', 5) .. 'x', seats = { { BASE.x, BASE.y + i * 0.5, BASE.z, 90 } }, spots = 'many' }
        end
        local data = Layout.Sanitize(json.decode(json.encode(hostile)))
        H.True(data.hostess == nil, 'out-of-range hostess dropped')
        H.Eq(#data.waiters, 1, 'only the valid waiter kept')
        H.Eq(data.waiters[1][4], 0.0, 'invalid heading → 0')
        H.Eq(#data.tables, Layout.MAX.tables, 'table count capped')
        local ids = {}
        for _, t in ipairs(data.tables) do
            H.True(not ids[t.id], 'unique table ids')
            ids[t.id] = true
            H.Eq(#t.spots, 0, 'invalid spot list dropped')
            H.True(not t.label:find('<', 1, true), 'label sanitised')
        end
        H.True(data.nextId > 1, 'next id repaired')
        H.Eq(Layout.IsComplete(data), false, 'no hostess → stays a draft')
    end)

    H.Test('setup: fine-tuning seats, export to config.lua and reset back to config.lua', function()
        H.BootServer({ framework = 'standalone' })
        admin(1)
        local tableId = placeFullLayout(1)
        local before = Config.Tables[1].seats[1]
        H.Ok(act(1, { action = 'seat_nudge', tableId = tableId, index = 1, forward = 0.1 }))
        local after = Config.Tables[1].seats[1]
        H.True(near(after.y, before.y + 0.1) and near(after.x, before.x), 'seat 1 (facing north) moved 10 cm forward')
        H.Ok(act(1, { action = 'seat_nudge', tableId = tableId, index = 1, turn = -15 }))
        H.True(near(Config.Tables[1].seats[1].w, 345.0), 'turned right by 15°')
        H.Fails(act(1, { action = 'seat_nudge', tableId = tableId, index = 9, forward = 0.1 }), 'setup_nothing_to_remove', 'unknown seat')

        local r = H.Ok(act(1, { action = 'export' }))
        local text = r.data.text
        H.True(text:find('Config.Tables = {', 1, true) ~= nil, 'tables in export')
        local env = {
            vec3 = vec3, vec4 = vec4,
            Config = { Venue = {}, Furniture = {}, Hostess = {}, Staff = {} },
        }
        local chunk, err = load(text, 'export', 't', env)
        H.True(chunk ~= nil, 'export is valid Lua: ' .. tostring(err))
        chunk()
        H.Eq(#env.Config.Tables, 1, 'exported tables')
        H.Eq(#env.Config.Tables[1].seats, 2, 'exported seats')
        H.Eq(#env.Config.Waiters, 1, 'exported waiters')
        H.True(near(env.Config.Hostess.coords.x, BASE.x), 'exported hostess')

        MOCK.ClearEvents()
        H.Ok(act(1, { action = 'reset' }))
        H.True(Layout.data == nil and not Layout.active, 'layout removed')
        H.Eq(#Config.Tables, 6, 'config.lua tables back')
        H.Eq(#Tables.list, 6, 'server tables back')
        H.Eq(MOCK.files[LAYOUT_FILE], '', 'file emptied')
        local events = MOCK.EventsFor('cyphercity-hookah:client:layout', -1)
        H.True(#events == 1 and events[1].args[1].layout == false, 'clients told to use config.lua')
        H.Fails(act(1, { action = 'export' }), 'setup_export_incomplete', 'nothing to export')
        H.Fails(act(1, { action = 'reset' }), 'setup_nothing_to_remove', 'nothing to reset')
    end)

    H.Test('setup: without OneSync the admin client position is used and validated', function()
        H.BootServer({ framework = 'standalone', onesync = 'off' })
        admin(1)
        H.Ok(MOCK.Call(1, 'setupOpen', {}))
        local r = H.Ok(act(1, { action = 'hostess', pos = { x = BASE.x, y = BASE.y, z = BASE.z, h = 45.0 } }))
        H.True(near(r.data.layout.hostess[1], BASE.x) and near(r.data.layout.hostess[4], 45.0), 'client position used')
        H.Eq(r.data.oneSync, false, 'panel is told OneSync is off')
        H.Fails(act(1, { action = 'waiter_add', pos = { x = 'a', y = BASE.y, z = BASE.z } }), 'setup_no_position', 'garbage position')
        H.Fails(act(1, { action = 'waiter_add' }), 'setup_no_position', 'missing position')
    end)

    H.Test('setup: other admins see changes live; players get the layout when they join', function()
        H.BootServer({ framework = 'standalone' })
        admin(1)
        admin(2)
        H.Ok(MOCK.Call(2, 'setupOpen', {}))
        placeFullLayout(1)
        H.True(#MOCK.EventsFor('cyphercity-hookah:client:setupState', 2) >= 1, 'second admin updated')
        H.Eq(#MOCK.EventsFor('cyphercity-hookah:client:setupState', 1), 0, 'the editor gets the answer instead')
        H.Ok(MOCK.Call(2, 'setupClose', {}))
        local count = #MOCK.EventsFor('cyphercity-hookah:client:setupState', 2)
        stand(1, 0, 1, 180.0)
        H.Ok(act(1, { action = 'hostess' }))
        H.Eq(#MOCK.EventsFor('cyphercity-hookah:client:setupState', 2), count, 'closed editor is no longer updated')
        H.Player({ id = 3 })
        local boot = H.Ok(MOCK.Call(3, 'bootstrap', {}))
        H.True(boot.data.layout.layout and boot.data.layout.revision == Setup.revision, 'bootstrap carries the active layout')
        H.True(H.LogContains(L('setup_hostess_set')), 'changes are logged')
        H.True(Setup.Report():find('ACTIVE', 1, true) ~= nil, 'hookahdiag shows the layout')
    end)
end

edgeSuite()
reviewSuite()
setupSuite()
