-- Daily sales summaries. Kept in memory and (optionally) saved as JSON inside
-- the resource folder with SaveResourceFile — no database required.

Persistence = {
    data = { version = 1, days = {} },
}

local dirty = false
local lastSave = 0
local saveFailedWarned = false

local function settings()
    return (ServerConfig and ServerConfig.Persistence) or { enabled = false }
end

local function today(time)
    return os.date('%Y-%m-%d', time or os.time())
end

local function emptyDay()
    return { revenue = 0, tips = 0, orders = 0, payments = 0, items = {} }
end

function Persistence.Load()
    Persistence.data = { version = 1, days = {} }
    if not settings().enabled then return end
    local raw = LoadResourceFile(GetCurrentResourceName(), settings().file)
    if not raw or raw == '' then return end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' and type(decoded.days) == 'table' then
        Persistence.data = decoded
        Persistence.Prune()
    else
        Bridge.Print('warn', ('Could not read %s — starting a new sales file'):format(settings().file))
    end
end

function Persistence.Prune()
    local keep = settings().keepDays or 30
    local cutoff = today(os.time() - keep * 86400)
    for date in pairs(Persistence.data.days) do
        if date < cutoff then Persistence.data.days[date] = nil end
    end
end

function Persistence.Save(force)
    if not settings().enabled or not dirty then return end
    local current = os.time()
    if not force and current - lastSave < (settings().saveInterval or 60) then return end
    lastSave = current
    Persistence.Prune()
    local ok = SaveResourceFile(GetCurrentResourceName(), settings().file, json.encode(Persistence.data), -1)
    if ok then
        dirty = false
    elseif not saveFailedWarned then
        saveFailedWarned = true
        Bridge.Print('warn', ('Could not write %s (folder read-only?). Sales stay in memory only.'):format(settings().file))
    end
end

-- orders: list of order records that were just paid
function Persistence.RecordSale(orders, revenue, tips)
    local date = today()
    local day = Persistence.data.days[date]
    if not day then
        day = emptyDay()
        Persistence.data.days[date] = day
    end
    day.revenue = day.revenue + (revenue or 0)
    day.tips = day.tips + (tips or 0)
    day.payments = day.payments + 1
    for _, order in ipairs(orders) do
        day.orders = day.orders + 1
        for _, line in ipairs(order.lines) do
            local item = day.items[line.id]
            if not item then
                item = { label = line.label, qty = 0, revenue = 0 }
                day.items[line.id] = item
            end
            item.qty = item.qty + line.qty
            item.revenue = item.revenue + line.total
        end
    end
    dirty = true
end

-- Removes a refunded order from the day it is refunded on.
function Persistence.RecordRefund(order, revenue, tips)
    local date = today()
    local day = Persistence.data.days[date]
    if not day then
        day = emptyDay()
        Persistence.data.days[date] = day
    end
    day.revenue = day.revenue - (revenue or 0)
    day.tips = day.tips - (tips or 0)
    day.orders = math.max(0, day.orders - 1)
    for _, line in ipairs(order.lines) do
        local item = day.items[line.id]
        if item then
            item.qty = math.max(0, item.qty - line.qty)
            item.revenue = item.revenue - line.total
        end
    end
    dirty = true
end

function Persistence.Report(days)
    days = days or 7
    local list = {}
    for i = days - 1, 0, -1 do
        local date = today(os.time() - i * 86400)
        local day = Persistence.data.days[date] or emptyDay()
        list[#list + 1] = { date = date, revenue = day.revenue, tips = day.tips, orders = day.orders, payments = day.payments }
    end
    local current = Persistence.data.days[today()] or emptyDay()
    local top = {}
    for id, item in pairs(current.items) do
        top[#top + 1] = { id = id, label = item.label, qty = item.qty, revenue = item.revenue }
    end
    table.sort(top, function(a, b) return a.qty > b.qty end)
    while #top > 8 do table.remove(top) end
    return {
        today = { revenue = current.revenue, tips = current.tips, orders = current.orders, payments = current.payments },
        days = list,
        top = top,
        persisted = settings().enabled == true,
    }
end
