-- Catalog engine: turns Config.Categories / Config.Menu / Config.Hookah into one
-- validated, indexed product list. The server uses it as the only source of prices;
-- the client uses it to build the NUI menu.

Catalog = {
    categories = {},
    categoryById = {},
    products = {},      -- ordered list of every valid product (menu items + hookah types)
    byId = {},
    flavors = {},
    flavorById = {},
    errors = {},
    warnings = {},
}

local ID_PATTERN = '^[%w_%-]+$'

local function addError(message, ...)
    Catalog.errors[#Catalog.errors + 1] = string.format(message, ...)
end

local function addWarning(message, ...)
    Catalog.warnings[#Catalog.warnings + 1] = string.format(message, ...)
end

local function validId(id)
    return type(id) == 'string' and #id > 0 and #id <= 48 and id:match(ID_PATTERN) ~= nil
end

local function validLabel(label)
    return type(label) == 'string' and #label > 0
end

local function validPrice(price)
    local n = Utils.ToInt(price)
    return n ~= nil and n >= 0 and n <= 1000000
end

local function copyTags(tags)
    local out = {}
    if type(tags) == 'table' then
        for _, tag in ipairs(tags) do
            if type(tag) == 'string' then out[#out + 1] = tag end
        end
    end
    return out
end

local function buildCategories()
    for index, category in ipairs(Config.Categories or {}) do
        if not validId(category.id) then
            addError('Category #%d has an invalid id', index)
        elseif Catalog.categoryById[category.id] then
            addError('Duplicate category id "%s"', category.id)
        elseif not validLabel(category.label) then
            addError('Category "%s" has no label', category.id)
        else
            local entry = { id = category.id, label = category.label, icon = category.icon, order = index }
            Catalog.categories[#Catalog.categories + 1] = entry
            Catalog.categoryById[category.id] = entry
        end
    end
end

local function buildFlavors()
    for index, flavor in ipairs((Config.Hookah and Config.Hookah.Flavors) or {}) do
        if not validId(flavor.id) then
            addError('Flavor #%d has an invalid id', index)
        elseif Catalog.flavorById[flavor.id] then
            addError('Duplicate flavor id "%s"', flavor.id)
        elseif not validLabel(flavor.label) then
            addError('Flavor "%s" has no label', flavor.id)
        elseif not validPrice(flavor.price or 0) then
            addError('Flavor "%s" has an invalid price', flavor.id)
        else
            local entry = {
                id = flavor.id,
                label = flavor.label,
                price = Utils.ToInt(flavor.price or 0),
                color = flavor.color,
                enabled = flavor.enabled ~= false,
            }
            Catalog.flavors[#Catalog.flavors + 1] = entry
            Catalog.flavorById[flavor.id] = entry
        end
    end
end

local function registerProduct(product, source)
    if Catalog.byId[product.id] then
        addError('Duplicate product id "%s" (%s)', product.id, source)
        return
    end
    Catalog.products[#Catalog.products + 1] = product
    Catalog.byId[product.id] = product
end

local function validateCommon(raw, source, index)
    if not validId(raw.id) then
        addError('%s #%d has an invalid id (letters, numbers, _ and - only)', source, index)
        return false
    end
    if not validLabel(raw.label) then
        addError('%s "%s" has no label', source, raw.id)
        return false
    end
    if not validPrice(raw.price) then
        addError('%s "%s" has an invalid price (must be a whole number >= 0)', source, raw.id)
        return false
    end
    if raw.prepTime ~= nil and (type(raw.prepTime) ~= 'number' or raw.prepTime < 0 or raw.prepTime > 3600) then
        addError('%s "%s" has an invalid prepTime', source, raw.id)
        return false
    end
    if raw.maxQty ~= nil then
        local maxQty = Utils.ToInt(raw.maxQty)
        if not maxQty or maxQty < 1 or maxQty > 100 then
            addError('%s "%s" has an invalid maxQty', source, raw.id)
            return false
        end
    end
    if raw.stock ~= nil and (not Utils.ToInt(raw.stock) or raw.stock < 0) then
        addError('%s "%s" has an invalid stock value', source, raw.id)
        return false
    end
    return true
end

local function buildHookahTypes()
    local types = (Config.Hookah and Config.Hookah.Types) or {}
    if #types > 0 and not Catalog.categoryById.hookah then
        addError('Config.Hookah.Types is set but there is no category with id "hookah"')
        return
    end
    for index, raw in ipairs(types) do
        if validateCommon(raw, 'Hookah type', index) then
            local maxFlavors = Utils.ToInt(raw.maxFlavors or 1)
            local duration = Utils.ToInt(raw.duration or 1200)
            local allowed
            local ok = true
            if not maxFlavors or maxFlavors < 1 or maxFlavors > 3 then
                addError('Hookah type "%s" has an invalid maxFlavors (1-3)', raw.id)
                ok = false
            end
            if not duration or duration < 30 then
                addError('Hookah type "%s" has an invalid duration (seconds, >= 30)', raw.id)
                ok = false
            end
            if raw.allowedFlavors ~= nil then
                allowed = {}
                for _, flavorId in ipairs(raw.allowedFlavors) do
                    if Catalog.flavorById[flavorId] then
                        allowed[flavorId] = true
                    else
                        addWarning('Hookah type "%s" allows unknown flavor "%s" (ignored)', raw.id, tostring(flavorId))
                    end
                end
                if not next(allowed) then
                    addError('Hookah type "%s" has no valid allowedFlavors', raw.id)
                    ok = false
                end
            end
            if ok then
                registerProduct({
                    id = raw.id,
                    kind = 'hookah',
                    category = 'hookah',
                    label = raw.label,
                    description = raw.description or '',
                    price = Utils.ToInt(raw.price),
                    image = raw.image,
                    prepTime = raw.prepTime,
                    tags = copyTags(raw.tags),
                    maxQty = Utils.ToInt(raw.maxQty or 2),
                    stock = raw.stock,
                    enabled = raw.enabled ~= false,
                    duration = duration,
                    maxFlavors = maxFlavors,
                    allowedFlavors = allowed,
                    prop = raw.prop or (Config.Hookah and Config.Hookah.defaultProp),
                }, 'Config.Hookah.Types')
            end
        end
    end
end

local function buildMenu()
    for index, raw in ipairs(Config.Menu or {}) do
        if validateCommon(raw, 'Menu item', index) then
            if not Catalog.categoryById[raw.category] then
                addError('Menu item "%s" uses unknown category "%s"', raw.id, tostring(raw.category))
            elseif raw.category == 'hookah' then
                addError('Menu item "%s" cannot use the "hookah" category (add it to Config.Hookah.Types instead)', raw.id)
            else
                local consume = raw.consume
                if consume == nil or not (Config.ConsumeProfiles or {})[consume] then
                    if consume ~= nil then
                        addWarning('Menu item "%s" uses unknown consume profile "%s" (using "food")', raw.id, tostring(consume))
                    end
                    consume = 'food'
                end
                local inventory
                if type(raw.inventory) == 'table' then
                    inventory = {}
                    local give, require = raw.inventory.give, raw.inventory.require
                    if type(give) == 'table' and type(give.name) == 'string' then
                        inventory.give = { name = give.name, count = Utils.ToInt(give.count or 1) or 1 }
                    end
                    if type(require) == 'table' and type(require.name) == 'string' then
                        inventory.require = {
                            name = require.name,
                            count = Utils.ToInt(require.count or 1) or 1,
                            remove = require.remove == true,
                            label = require.label,
                        }
                    end
                end
                registerProduct({
                    id = raw.id,
                    kind = 'item',
                    category = raw.category,
                    label = raw.label,
                    description = raw.description or '',
                    price = Utils.ToInt(raw.price),
                    image = raw.image,
                    prepTime = raw.prepTime,
                    tags = copyTags(raw.tags),
                    maxQty = Utils.ToInt(raw.maxQty),
                    stock = raw.stock,
                    enabled = raw.enabled ~= false,
                    consume = consume,
                    inventory = inventory,
                }, 'Config.Menu')
            end
        end
    end
end

function Catalog.Build()
    Catalog.categories, Catalog.categoryById = {}, {}
    Catalog.products, Catalog.byId = {}, {}
    Catalog.flavors, Catalog.flavorById = {}, {}
    Catalog.errors, Catalog.warnings = {}, {}

    buildCategories()
    buildFlavors()
    buildHookahTypes()
    buildMenu()

    return #Catalog.errors == 0
end

function Catalog.Get(id)
    if type(id) ~= 'string' then return nil end
    return Catalog.byId[id]
end

function Catalog.IsOrderable(product)
    return product ~= nil and product.enabled
end

function Catalog.MaxQty(product)
    local globalMax = (Config.Orders and Config.Orders.maxQtyPerLine) or 10
    if product.maxQty then return math.min(product.maxQty, globalMax) end
    return globalMax
end

function Catalog.FlavorAllowed(product, flavorId)
    local flavor = Catalog.flavorById[flavorId]
    if not flavor or not flavor.enabled then return false end
    if product.allowedFlavors and not product.allowedFlavors[flavorId] then return false end
    return true
end

-- Validates the flavour list sent by a client for a hookah product.
-- Returns a clean list of flavour ids, or nil + error code.
function Catalog.ValidateFlavors(product, flavors)
    if product.kind ~= 'hookah' then
        if flavors ~= nil and not (type(flavors) == 'table' and next(flavors) == nil) then
            return nil, 'flavor_invalid'
        end
        return {}
    end
    if not Utils.IsArray(flavors) or #flavors < 1 or #flavors > product.maxFlavors then
        return nil, 'flavor_invalid'
    end
    local seen, clean = {}, {}
    for _, flavorId in ipairs(flavors) do
        if type(flavorId) ~= 'string' or seen[flavorId] or not Catalog.FlavorAllowed(product, flavorId) then
            return nil, 'flavor_invalid'
        end
        seen[flavorId] = true
        clean[#clean + 1] = flavorId
    end
    return clean
end

function Catalog.UnitPrice(product, flavors)
    local price = product.price
    for _, flavorId in ipairs(flavors or {}) do
        local flavor = Catalog.flavorById[flavorId]
        if flavor then price = price + flavor.price end
    end
    return price
end

function Catalog.FlavorLabels(flavors)
    local labels = {}
    for _, flavorId in ipairs(flavors or {}) do
        local flavor = Catalog.flavorById[flavorId]
        labels[#labels + 1] = flavor and flavor.label or flavorId
    end
    return labels
end

-- Display data for the NUI. Prices here are for display only; the server
-- recalculates every order from its own copy of the catalog.
function Catalog.ForNui()
    local products = {}
    for _, product in ipairs(Catalog.products) do
        if product.enabled then
            local allowed
            if product.allowedFlavors then
                allowed = {}
                for flavorId in pairs(product.allowedFlavors) do allowed[#allowed + 1] = flavorId end
                table.sort(allowed)
            end
            products[#products + 1] = {
                id = product.id,
                kind = product.kind,
                category = product.category,
                label = product.label,
                description = product.description,
                price = product.price,
                image = product.image,
                prepTime = product.prepTime,
                tags = product.tags,
                maxQty = Catalog.MaxQty(product),
                maxFlavors = product.maxFlavors,
                allowedFlavors = allowed,
                duration = product.duration,
            }
        end
    end
    local flavors = {}
    for _, flavor in ipairs(Catalog.flavors) do
        if flavor.enabled then
            flavors[#flavors + 1] = { id = flavor.id, label = flavor.label, price = flavor.price, color = flavor.color }
        end
    end
    local categories = {}
    for _, category in ipairs(Catalog.categories) do
        categories[#categories + 1] = { id = category.id, label = category.label, icon = category.icon }
    end
    return { categories = categories, products = products, flavors = flavors }
end

Catalog.Build()
