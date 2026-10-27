-- Framework bridge: player, identity, job, money and needs for ESX Legacy,
-- QBCore and Qbox, plus a standalone mode. Only the documented public APIs of
-- each framework are used (see README → "Bridge API reference").

Framework = {
    name = nil,
    object = nil,
    supportsMoney = false,
    supportsJobs = false,
}

local IS_SERVER = IsDuplicityVersion()

if IS_SERVER then
    local adapters = {}

    local function esxAccount(account)
        return account == 'cash' and 'money' or 'bank'
    end

    -- ESX Legacy ------------------------------------------------------------
    adapters.esx = {
        init = function()
            local ok, object = pcall(function()
                return exports[Bridge.ResourceName('esx')]:getSharedObject()
            end)
            if not ok or type(object) ~= 'table' then
                return false, 'exports["es_extended"]:getSharedObject() failed: ' .. tostring(object)
            end
            Framework.object = object
            return true
        end,
        getPlayer = function(src)
            return Framework.object.GetPlayerFromId(src)
        end,
        identifier = function(player)
            return player.identifier
        end,
        name = function(player)
            return player.getName and player.getName() or nil
        end,
        job = function(player)
            local job = (player.getJob and player.getJob()) or player.job
            if type(job) ~= 'table' then return nil end
            return {
                name = job.name,
                label = job.label,
                grade = tonumber(job.grade) or 0,
                gradeName = job.grade_label or job.grade_name,
                isBoss = job.grade_name == 'boss',
                onDuty = job.onDuty ~= false,
            }
        end,
        balance = function(player, account)
            local data = player.getAccount(esxAccount(account))
            return data and data.money or nil
        end,
        remove = function(player, account, amount, reason)
            -- Current ESX returns true/false; older builds return nothing, in which case
            -- Framework.RemoveMoney verifies the new balance instead.
            return player.removeAccountMoney(esxAccount(account), amount, reason)
        end,
        add = function(player, account, amount, reason)
            player.addAccountMoney(esxAccount(account), amount, reason)
            return true
        end,
        addNeeds = function(player, src, needs)
            if GetResourceState('esx_status') ~= 'started' then return false end
            -- esx_status keeps hunger/thirst server-authoritative on a 0 - 1,000,000 scale
            -- and exposes the server event used by esx_basicneeds.
            if needs.hunger then TriggerEvent('esx_status:add', src, 'hunger', math.floor(needs.hunger * 10000)) end
            if needs.thirst then TriggerEvent('esx_status:add', src, 'thirst', math.floor(needs.thirst * 10000)) end
            return true
        end,
    }

    -- QBCore & Qbox share the player object layout ------------------------------
    local function qbStyle(getPlayer)
        return {
            getPlayer = getPlayer,
            identifier = function(player)
                return player.PlayerData and player.PlayerData.citizenid
            end,
            name = function(player)
                local info = player.PlayerData and player.PlayerData.charinfo
                if type(info) == 'table' and info.firstname then
                    return ('%s %s'):format(info.firstname, info.lastname or '')
                end
                return nil
            end,
            job = function(player)
                local job = player.PlayerData and player.PlayerData.job
                if type(job) ~= 'table' then return nil end
                local grade = type(job.grade) == 'table' and job.grade or {}
                return {
                    name = job.name,
                    label = job.label,
                    grade = tonumber(grade.level) or 0,
                    gradeName = grade.name,
                    isBoss = job.isboss == true,
                    onDuty = job.onduty == true,
                }
            end,
            balance = function(player, account)
                local money = player.PlayerData and player.PlayerData.money
                return type(money) == 'table' and money[account] or nil
            end,
            remove = function(player, account, amount, reason)
                return player.Functions.RemoveMoney(account, amount, reason)
            end,
            add = function(player, account, amount, reason)
                return player.Functions.AddMoney(account, amount, reason)
            end,
            addNeeds = function(player, src, needs)
                local meta = player.PlayerData and player.PlayerData.metadata
                if type(meta) ~= 'table' or not player.Functions.SetMetaData then return false end
                local hunger = tonumber(meta.hunger) or 100
                local thirst = tonumber(meta.thirst) or 100
                if needs.hunger then hunger = math.min(100, hunger + needs.hunger) end
                if needs.thirst then thirst = math.min(100, thirst + needs.thirst) end
                player.Functions.SetMetaData('hunger', hunger)
                player.Functions.SetMetaData('thirst', thirst)
                if Framework.name == 'qbcore' then
                    TriggerClientEvent('hud:client:UpdateNeeds', src, hunger, thirst)
                end
                return true
            end,
        }
    end

    adapters.qbcore = qbStyle(function(src)
        return Framework.object.Functions.GetPlayer(src)
    end)
    adapters.qbcore.init = function()
        local ok, object = pcall(function()
            return exports[Bridge.ResourceName('qbcore')]:GetCoreObject()
        end)
        if not ok or type(object) ~= 'table' then
            return false, 'exports["qb-core"]:GetCoreObject() failed: ' .. tostring(object)
        end
        Framework.object = object
        return true
    end

    adapters.qbox = qbStyle(function(src)
        return exports[Bridge.ResourceName('qbox')]:GetPlayer(src)
    end)
    adapters.qbox.init = function()
        local ok, err = pcall(function()
            return exports[Bridge.ResourceName('qbox')]:GetPlayer(0)
        end)
        if not ok then
            return false, 'exports.qbx_core:GetPlayer() is not available: ' .. tostring(err)
        end
        return true
    end

    -- Standalone: identity from FiveM natives, no jobs, no money ----------------
    adapters.standalone = {
        init = function() return true end,
        getPlayer = function(src)
            if GetPlayerName(src) then return { source = src } end
            return nil
        end,
        identifier = function(player)
            return GetPlayerIdentifierByType(player.source, 'license')
                or GetPlayerIdentifierByType(player.source, 'fivem')
                or ('player:' .. tostring(player.source))
        end,
        name = function(player) return GetPlayerName(player.source) end,
        job = function() return nil end,
    }

    local adapter

    function Framework.Init(name)
        adapter = adapters[name]
        if not adapter then return false, 'Unknown framework: ' .. tostring(name) end
        local ok, err = adapter.init()
        if not ok then return false, err end
        Framework.name = name
        Framework.supportsMoney = adapter.balance ~= nil and adapter.remove ~= nil
        Framework.supportsJobs = name ~= 'standalone'
        return true
    end

    function Framework.GetPlayer(src)
        if not adapter or not src then return nil end
        local ok, player = pcall(adapter.getPlayer, src)
        if ok then return player end
        return nil
    end

    function Framework.IsLoaded(src)
        return Framework.GetPlayer(src) ~= nil
    end

    function Framework.GetIdentifier(src)
        local player = Framework.GetPlayer(src)
        local id = player and adapter.identifier(player)
        return id or GetPlayerIdentifierByType(src, 'license') or ('player:' .. tostring(src))
    end

    function Framework.GetCharName(src)
        local player = Framework.GetPlayer(src)
        local name
        if player then
            local ok, result = pcall(adapter.name, player)
            if ok then name = result end
        end
        if type(name) ~= 'string' or name == '' then name = GetPlayerName(src) or ('#' .. tostring(src)) end
        return name
    end

    function Framework.GetJob(src)
        if not adapter or not adapter.job then return nil end
        local player = Framework.GetPlayer(src)
        if not player then return nil end
        local ok, job = pcall(adapter.job, player)
        if ok and type(job) == 'table' and job.name then return job end
        return nil
    end

    function Framework.GetBalance(src, account)
        if not Framework.supportsMoney then return nil end
        local player = Framework.GetPlayer(src)
        if not player then return nil end
        local ok, balance = pcall(adapter.balance, player, account)
        if ok and type(balance) == 'number' then return balance end
        return nil
    end

    -- Removes money and verifies it really left the account.
    -- Returns true, or false + reason ('no_player' | 'no_balance' | 'insufficient_funds' | 'error' | 'rejected' | 'not_deducted').
    function Framework.RemoveMoney(src, account, amount, reason)
        if not Framework.supportsMoney then return false, 'unsupported' end
        amount = Utils.ToInt(amount)
        if not amount or amount <= 0 then return false, 'invalid_amount' end
        local player = Framework.GetPlayer(src)
        if not player then return false, 'no_player' end
        local before = Framework.GetBalance(src, account)
        if not before then return false, 'no_balance' end
        if before < amount then return false, 'insufficient_funds' end

        local ok, result = pcall(adapter.remove, player, account, amount, reason)
        if not ok then
            Logger.Error('payment', ('RemoveMoney threw for %s: %s'):format(src, tostring(result)))
            return false, 'error'
        end
        if result == false then return false, 'rejected' end
        if result == true then return true end

        local after = Framework.GetBalance(src, account)
        if not after or after > before - amount then return false, 'not_deducted' end
        return true
    end

    function Framework.AddMoney(src, account, amount, reason)
        if not Framework.supportsMoney or not adapter.add then return false end
        local player = Framework.GetPlayer(src)
        if not player then return false end
        local ok, result = pcall(adapter.add, player, account, amount, reason)
        return ok and result ~= false
    end

    function Framework.AddNeeds(src, needs)
        if not adapter or not adapter.addNeeds then return false end
        local player = Framework.GetPlayer(src)
        if not player then return false end
        local ok, result = pcall(adapter.addNeeds, player, src, needs)
        return ok and result == true
    end
else
    -- Client side: only used for framework-native notifications.
    local esxObject, qbObject

    function Framework.ClientNotify(message, kind, duration)
        local name = Bridge.framework
        if name == 'esx' then
            if not esxObject then
                local ok, object = pcall(function() return exports[Bridge.ResourceName('esx')]:getSharedObject() end)
                if ok then esxObject = object end
            end
            if esxObject and esxObject.ShowNotification then
                esxObject.ShowNotification(message, kind, duration)
                return true
            end
        elseif name == 'qbcore' then
            if not qbObject then
                local ok, object = pcall(function() return exports[Bridge.ResourceName('qbcore')]:GetCoreObject() end)
                if ok then qbObject = object end
            end
            if qbObject and qbObject.Functions and qbObject.Functions.Notify then
                local qbType = kind == 'info' and 'primary' or kind
                qbObject.Functions.Notify(message, qbType, duration)
                return true
            end
        elseif name == 'qbox' then
            local ok = pcall(function()
                exports[Bridge.ResourceName('qbox')]:Notify(message, kind, duration)
            end)
            return ok
        end
        return false
    end
end
