-- Society / business account bridge (server only). Disabled by default.
-- Supported (verified against current source):
--   esx_addonaccount : TriggerEvent('esx_addonaccount:getSharedAccount', name, cb) → account.addMoney(amount)
--   qb-banking       : exports['qb-banking']:GetAccount / CreateJobAccount / AddMoney(account, amount, reason)
--   Renewed-Banking  : exports['Renewed-Banking']:addAccountMoney / removeAccountMoney(account, amount)
-- Refunds take the money back out with account.removeMoney / RemoveMoney / removeAccountMoney.

Banking = { system = nil }

local SYSTEMS = { 'Renewed-Banking', 'qb-banking', 'esx_addonaccount' }

local depositors = {}

depositors.esx_addonaccount = function(account, amount)
    local done = false
    TriggerEvent('esx_addonaccount:getSharedAccount', account, function(shared)
        if shared then
            done = shared.addMoney(amount) ~= false
        end
    end)
    return done
end

depositors['qb-banking'] = function(account, amount, reason)
    local bank = exports['qb-banking']
    local existing = bank:GetAccount(account)
    if not existing then
        bank:CreateJobAccount(account, 0)
    end
    return bank:AddMoney(account, amount, reason) ~= false
end

depositors['Renewed-Banking'] = function(account, amount)
    return exports['Renewed-Banking']:addAccountMoney(account, amount) == true
end

local withdrawers = {}

withdrawers.esx_addonaccount = function(account, amount)
    local done = false
    TriggerEvent('esx_addonaccount:getSharedAccount', account, function(shared)
        if shared and type(shared.removeMoney) == 'function' then
            done = shared.removeMoney(amount) ~= false
        end
    end)
    return done
end

withdrawers['qb-banking'] = function(account, amount, reason)
    return exports['qb-banking']:RemoveMoney(account, amount, reason) ~= false
end

withdrawers['Renewed-Banking'] = function(account, amount)
    return exports['Renewed-Banking']:removeAccountMoney(account, amount) == true
end

function Banking.Init()
    local settings = Config.Payments.society or {}
    if not settings.enabled then
        Banking.system = nil
        return true
    end
    local wanted = settings.system or 'auto'
    if wanted == 'auto' then
        for _, name in ipairs(SYSTEMS) do
            if GetResourceState(name) == 'started' then
                Banking.system = name
                break
            end
        end
    elseif depositors[wanted] and GetResourceState(wanted) == 'started' then
        Banking.system = wanted
    end
    if not Banking.system then
        return false, ('Config.Payments.society is enabled but no supported banking resource is started (wanted: %s)'):format(wanted)
    end
    return true
end

function Banking.Deposit(amount, reason)
    if not Banking.system or amount <= 0 then return false end
    local account = (Config.Payments.society or {}).account or Config.Business.job
    local ok, result = pcall(depositors[Banking.system], account, amount, reason)
    if not ok or not result then
        Logger.Warn('payment', ('Society deposit of %s to "%s" via %s failed: %s'):format(amount, account, Banking.system, tostring(result)))
        return false
    end
    return true
end

-- Takes a refunded amount back out of the society account.
function Banking.Withdraw(amount, reason)
    if not Banking.system or amount <= 0 then return false end
    local account = (Config.Payments.society or {}).account or Config.Business.job
    local ok, result = pcall(withdrawers[Banking.system], account, amount, reason)
    if not ok or not result then
        Logger.Warn('payment', ('Society withdrawal of %s from "%s" via %s failed — correct the society balance manually: %s'):format(amount, account, Banking.system, tostring(result)))
        return false
    end
    return true
end
