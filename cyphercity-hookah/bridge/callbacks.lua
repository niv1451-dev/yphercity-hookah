-- Self-contained client → server callback system (no framework dependency).
-- The client sends (name, requestId, payload); the server runs the registered
-- handler with the real `source` and replies only to that player.
-- Every callback is rate limited per player and wrapped in pcall.

Callback = {}

local REQUEST = 'cyphercity-hookah:cb:request'
local RESPONSE = 'cyphercity-hookah:cb:response'

if IsDuplicityVersion() then
    local handlers = {}

    function Callback.Register(name, handler, rateKey)
        handlers[name] = { fn = handler, rateKey = rateKey or name }
    end

    function Callback.Has(name)
        return handlers[name] ~= nil
    end

    function Callback.Names()
        local names = {}
        for name in pairs(handlers) do names[#names + 1] = name end
        table.sort(names)
        return names
    end

    local function reply(src, requestId, result)
        TriggerClientEvent(RESPONSE, src, requestId, result)
    end

    RegisterNetEvent(REQUEST, function(name, requestId, payload)
        local src = source
        if type(requestId) ~= 'number' then return end
        if type(name) ~= 'string' or #name > 48 then
            Security.Flag(src, 'callback_bad_name', { name = tostring(name) })
            return reply(src, requestId, { ok = false, code = 'invalid_request' })
        end
        local handler = handlers[name]
        if not handler then
            Security.Flag(src, 'callback_unknown', { name = name })
            return reply(src, requestId, { ok = false, code = 'invalid_request' })
        end
        if payload ~= nil and type(payload) ~= 'table' then
            return reply(src, requestId, { ok = false, code = 'invalid_request' })
        end
        if not Server.ready then
            return reply(src, requestId, { ok = false, code = 'not_ready' })
        end
        if not Security.RateLimit(src, handler.rateKey) then
            return reply(src, requestId, { ok = false, code = 'rate_limited' })
        end

        local ok, result = pcall(handler.fn, src, payload or {})
        if not ok then
            Logger.Error('system', ('Callback "%s" failed for player %s: %s'):format(name, src, tostring(result)))
            result = { ok = false, code = 'internal_error' }
        elseif type(result) ~= 'table' then
            result = { ok = result == true }
        end
        reply(src, requestId, result)
    end)
else
    local pending = {}
    local nextId = 0

    -- Blocks the calling thread until the server answers (or the timeout hits).
    function Callback.Await(name, payload, timeoutMs)
        nextId = nextId + 1
        local requestId = nextId
        local p = promise.new()
        pending[requestId] = p
        TriggerServerEvent(REQUEST, name, requestId, payload or {})
        SetTimeout(timeoutMs or 10000, function()
            if pending[requestId] then
                pending[requestId] = nil
                p:resolve({ ok = false, code = 'timeout' })
            end
        end)
        return Citizen.Await(p)
    end

    RegisterNetEvent(RESPONSE, function(requestId, result)
        local p = pending[requestId]
        if not p then return end
        pending[requestId] = nil
        p:resolve(type(result) == 'table' and result or { ok = false, code = 'internal_error' })
    end)
end
