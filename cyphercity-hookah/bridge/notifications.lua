-- Notification bridge. The server always sends one event; the client decides how
-- to display it: ox_lib (event 'ox_lib:notify'), the framework's own notify, or
-- the built-in NUI toast. GTA's native text cannot render Hebrew, so the native
-- feed is never used for messages.

Notify = {}

local EVENT = 'cyphercity-hookah:client:notify'
local VALID = { success = true, error = true, info = true, warning = true }

if IsDuplicityVersion() then
    function Notify.Player(src, message, kind, duration)
        if not src or src <= 0 then return end
        TriggerClientEvent(EVENT, src, message, VALID[kind] and kind or 'info', duration)
    end
else
    function Notify.Send(message, kind, duration)
        if type(message) ~= 'string' or message == '' then return end
        kind = VALID[kind] and kind or 'info'
        duration = duration or 5000
        local mode = Bridge.notify or 'nui'

        if mode == 'ox_lib' and Bridge.IsStarted('ox_lib') then
            TriggerEvent('ox_lib:notify', {
                title = Config.Business.name,
                description = message,
                type = kind,
                duration = duration,
                position = 'top',
            })
            return
        end

        if mode == 'framework' and Framework.ClientNotify(message, kind, duration) then
            return
        end

        SendNUIMessage({ action = 'toast', data = { message = message, type = kind, duration = duration } })
    end

    RegisterNetEvent(EVENT, function(message, kind, duration)
        Notify.Send(message, kind, duration)
    end)
end
