-- Diagnostics: config validation at start-up and the "hookahdiag" command, which
-- prints what this server actually runs (frameworks, inventories, targets,
-- versions, OneSync, game build) so you can pick the right adapters.
-- Usage: type  hookahdiag  in the server console (txAdmin → Live Console),
-- or in-game F8 for players with the ACE permission in ServerConfig.AdminAce.

Diagnostics = {}

local KNOWN_RESOURCES = {
    { 'es_extended', 'ESX framework' },
    { 'qb-core', 'QBCore framework (also "provided" by qbx_core on Qbox)' },
    { 'qbx_core', 'Qbox framework' },
    { 'ox_lib', 'ox_lib (notifications)' },
    { 'ox_target', 'ox_target' },
    { 'qb-target', 'qb-target' },
    { 'ox_inventory', 'ox_inventory' },
    { 'qb-inventory', 'qb-inventory' },
    { 'ps-inventory', 'ps-inventory (not supported directly)' },
    { 'lj-inventory', 'lj-inventory (not supported directly)' },
    { 'esx_addonaccount', 'ESX society accounts' },
    { 'esx_status', 'ESX hunger/thirst' },
    { 'qb-banking', 'qb-banking (society)' },
    { 'Renewed-Banking', 'Renewed-Banking (society)' },
    { 'qb-hud', 'qb-hud' },
}

local VALID = {
    Framework = { auto = true, esx = true, qbcore = true, qbox = true, standalone = true },
    Inventory = { none = true, auto = true, ox_inventory = true, ['qb-inventory'] = true, esx = true },
    Target = { auto = true, ox_target = true, ['qb-target'] = true, standalone = true },
    Notify = { auto = true, ox_lib = true, framework = true, nui = true },
    timing = { on_bill = true, on_order = true },
    accounts = { cash = true, bank = true },
    payer = { owner = true, any_member = true },
    mode = { auto = true, staff = true, hybrid = true },
}

function Diagnostics.ValidateConfig()
    local out = {}
    local function add(level, text, ...) out[#out + 1] = { level = level, text = text:format(...) } end

    for _, key in ipairs({ 'Framework', 'Inventory', 'Target', 'Notify' }) do
        if not VALID[key][Config[key]] then add('error', 'Config.%s = "%s" is not a valid option', key, tostring(Config[key])) end
    end
    if not VALID.timing[Config.Payments.timing] then add('error', 'Config.Payments.timing must be "on_bill" or "on_order"') end
    if not VALID.payer[Config.Payments.tableBillPayer] then add('error', 'Config.Payments.tableBillPayer must be "owner" or "any_member"') end
    if not VALID.mode[Config.Orders.mode] then add('error', 'Config.Orders.mode must be "auto", "staff" or "hybrid"') end
    if type(Config.Payments.accounts) ~= 'table' or #Config.Payments.accounts == 0 then
        add('error', 'Config.Payments.accounts must list at least one of "cash" / "bank"')
    else
        for _, account in ipairs(Config.Payments.accounts) do
            if not VALID.accounts[account] then add('error', 'Config.Payments.accounts contains unknown account "%s"', tostring(account)) end
        end
    end
    for _, tip in ipairs((Config.Payments.tips or {}).options or {}) do
        if not Utils.ToInt(tip) or tip < 0 or tip > 100 then add('error', 'Tip option %s must be a whole number 0-100', tostring(tip)) end
    end

    local tableIds = {}
    for _, t in ipairs(Config.Tables or {}) do
        if t.id then tableIds[t.id] = true end
        if t.center and Config.Venue.center and Utils.Dist2D(t.center, Config.Venue.center) > Config.Venue.radius then
            add('warn', 'Table %s is outside Config.Venue.radius — customers there would be "outside" the lounge', tostring(t.id))
        end
        if #(Config.Hookah.Types or {}) > 0 and #(t.hookahSpots or {}) == 0 then
            add('warn', 'Table %s has no hookahSpots — hookahs cannot be ordered there', tostring(t.id))
        end
    end
    for index, waiter in ipairs(Config.Waiters or {}) do
        for _, tableId in ipairs(waiter.tables or {}) do
            if not tableIds[tableId] then add('warn', 'Config.Waiters[%d] references unknown table %s', index, tostring(tableId)) end
        end
    end
    if Config.Hostess.coords and Utils.Dist2D(Config.Hostess.coords, Config.Venue.center) > Config.Venue.radius then
        add('warn', 'The hostess stands outside Config.Venue.radius')
    end
    for grade, role in pairs(Config.Staff.gradeRoles or {}) do
        if not (Config.Staff.permissions or {})[role] then add('error', 'Config.Staff.gradeRoles[%s] uses unknown role "%s"', tostring(grade), tostring(role)) end
    end
    for id, profile in pairs(Config.ConsumeProfiles or {}) do
        if type(profile.dict) ~= 'string' or type(profile.clip) ~= 'string' then
            add('error', 'Config.ConsumeProfiles.%s needs dict and clip', id)
        end
    end
    return out
end

local function resourceLine(name, description)
    local state = GetResourceState(name)
    if state == 'missing' then return nil end
    local version = GetResourceMetadata(name, 'version', 0) or '?'
    return ('  %-18s %-10s v%-10s %s'):format(name, state, version, description)
end

function Diagnostics.Report()
    local lines = {}
    local function add(text, ...) lines[#lines + 1] = select('#', ...) > 0 and text:format(...) or text end

    add('=== cyphercity-hookah diagnostics ===')
    add('Resource version: %s', GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?')
    add('Ready: %s%s', tostring(Server.ready), Server.failure and (' — FAILURE: ' .. Server.failure) or '')
    add('Adapters: framework=%s (config: %s) | inventory=%s (config: %s) | money=%s | society=%s',
        tostring(Bridge.framework), Config.Framework, tostring(Bridge.inventory), Config.Inventory,
        Server.ready and Payments.MoneyMode() or '?', tostring(Banking.system or 'off'))
    add('Target/notify are chosen on each client: config Target=%s, Notify=%s', Config.Target, Config.Notify)
    add('OneSync: %s | game build: %s', GetConvar('onesync', 'off'), GetConvar('sv_enforceGameBuild', 'default'))
    add('Detected resources:')
    local any = false
    for _, entry in ipairs(KNOWN_RESOURCES) do
        local line = resourceLine(entry[1], entry[2])
        if line then add(line) any = true end
    end
    if not any then add('  (none of the known frameworks / inventories / targets were found)') end

    add('Catalog: %d products, %d flavours, %d categories | errors: %d | warnings: %d',
        #Catalog.products, #Catalog.flavors, #Catalog.categories, #Catalog.errors, #Catalog.warnings)
    for _, message in ipairs(Catalog.errors) do add('  ERROR: %s', message) end
    for _, message in ipairs(Catalog.warnings) do add('  warn: %s', message) end
    for _, message in ipairs(Diagnostics.ValidateConfig()) do add('  %s: %s', message.level, message.text) end

    add(Setup.Report())
    if Server.ready then
        local occupied, active = 0, 0
        for _, t in ipairs(Tables.list) do if t.status ~= 'free' then occupied = occupied + 1 end end
        for _, order in pairs(Orders.byId) do
            if order.status == 'new' or order.status == 'preparing' or order.status == 'serving' then active = active + 1 end
        end
        add('Live: %d/%d tables in use | %d active orders | %d hookahs | staff on duty: %d | lounge open: %s',
            occupied, #Tables.list, active, Utils.Count(Hookah.sessions), Staff.OnDutyCount(), tostring(Business.IsOpen()))
    end
    add('Callbacks registered: %d', #Callback.Names())
    add('=====================================')
    return lines
end

RegisterCommand('hookahdiag', function(source)
    if source ~= 0 and not IsPlayerAceAllowed(source, ServerConfig.AdminAce) then return end
    local lines = Diagnostics.Report()
    if source == 0 then
        for _, line in ipairs(lines) do print(line) end
    else
        TriggerClientEvent('cyphercity-hookah:client:diagnostics', source, lines)
    end
end, false)
