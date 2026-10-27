-- Logging bridge (server only): console, in-memory ring buffer (shown in the
-- staff panel) and optional Discord webhook read from a server-only convar.
-- Never log passwords, tokens or webhook URLs.

Logger = {}

local entries = {}
local nextId = 0
local discordQueue = {}
local webhook = ''

local LEVEL_COLOR = { debug = '^8', info = '^5', warn = '^3', error = '^1' }
local DISCORD_COLOR = { info = 13148011, warn = 15105570, error = 15158332, debug = 9807270 }
local SENSITIVE_KEYS = { token = true, password = true, webhook = true, secret = true, key = true }

local function settings()
    return (ServerConfig and ServerConfig.Logging) or {}
end

local function sanitize(data)
    if type(data) ~= 'table' then return nil end
    local clean = {}
    for k, v in pairs(data) do
        local key = tostring(k)
        if not SENSITIVE_KEYS[key:lower()] then
            if type(v) == 'table' then
                clean[key] = sanitize(v)
            elseif type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then
                clean[key] = v
            end
        end
    end
    return clean
end

function Logger.Init()
    local discord = settings().discord or {}
    if discord.enabled then
        webhook = GetConvar(discord.convar or 'cyphercity_hookah_webhook', '')
        if webhook == '' then
            Bridge.Print('warn', ('Discord logging is enabled but convar "%s" is empty — Discord logs are off'):format(discord.convar or 'cyphercity_hookah_webhook'))
        end
    end
end

local function queueDiscord(entry)
    local discord = settings().discord or {}
    if not discord.enabled or webhook == '' then return end
    if not (discord.categories or {})[entry.category] then return end
    discordQueue[#discordQueue + 1] = entry
    if #discordQueue > 50 then table.remove(discordQueue, 1) end
end

function Logger.FlushDiscord()
    if #discordQueue == 0 or webhook == '' then return end
    local entry = table.remove(discordQueue, 1)
    local fields = {}
    for k, v in pairs(entry.data or {}) do
        if #fields < 15 then
            fields[#fields + 1] = { name = k, value = type(v) == 'table' and json.encode(v) or tostring(v), inline = true }
        end
    end
    local payload = {
        username = (settings().discord or {}).username or 'CypherCity Hookah',
        embeds = { {
            title = ('[%s] %s'):format(entry.category, entry.level:upper()),
            description = entry.message,
            color = DISCORD_COLOR[entry.level] or DISCORD_COLOR.info,
            fields = fields,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', entry.time),
        } },
    }
    PerformHttpRequest(webhook, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function Logger.Log(level, category, message, data)
    level = LEVEL_COLOR[level] and level or 'info'
    local cfg = settings()
    if level == 'debug' and not cfg.debug then return end

    nextId = nextId + 1
    local entry = {
        id = nextId,
        time = os.time(),
        level = level,
        category = category or 'system',
        message = tostring(message),
        data = sanitize(data),
    }

    entries[#entries + 1] = entry
    local max = cfg.memorySize or 250
    while #entries > max do table.remove(entries, 1) end

    if cfg.console ~= false then
        local extra = ''
        if entry.data and next(entry.data) then extra = ' ' .. json.encode(entry.data) end
        print(('%s[hookah:%s]^7 %s%s'):format(LEVEL_COLOR[level], entry.category, entry.message, extra))
    end

    if level ~= 'debug' then queueDiscord(entry) end
    return entry
end

function Logger.Info(category, message, data) return Logger.Log('info', category, message, data) end
function Logger.Warn(category, message, data) return Logger.Log('warn', category, message, data) end
function Logger.Error(category, message, data) return Logger.Log('error', category, message, data) end
function Logger.Debug(category, message, data) return Logger.Log('debug', category, message, data) end

function Logger.Recent(limit, category)
    local out = {}
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if not category or entry.category == category then
            out[#out + 1] = entry
            if #out >= (limit or 50) then break end
        end
    end
    return out
end
