fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cyphercity-hookah'
author 'CypherCity'
description "The Sheikh's Place (המקום של השייח) hookah lounge for CypherCity — hostess, tables, waiters, hookahs, menu, bills and staff panel"
version '1.0.0'

-- No hard dependencies: ESX / QBCore / Qbox, ox_target / qb-target, ox_lib and
-- inventories are detected at start-up (see config.lua → Bridge).

shared_scripts {
    'config.lua',
    'shared/utils.lua',
    'shared/locales.lua',
    'shared/items.lua',
    'shared/layout.lua',
    'bridge/init.lua',
    'bridge/callbacks.lua',
    'bridge/framework.lua',
    'bridge/notifications.lua',
}

server_scripts {
    'config_server.lua',
    'bridge/logger.lua',
    'bridge/inventory.lua',
    'bridge/banking.lua',
    'server/security.lua',
    'server/staff.lua',
    'server/persistence.lua',
    'server/sync.lua',
    'server/tables.lua',
    'server/hookah.lua',
    'server/orders.lua',
    'server/payments.lua',
    'server/waiters.lua',
    'server/diagnostics.lua',
    'server/setup.lua',
    'server/api.lua',
    'server/main.lua',
}

client_scripts {
    'client/util.lua',
    'bridge/target.lua',
    'client/nui.lua',
    'client/main.lua',
    'client/peds.lua',
    'client/furniture.lua',
    'client/tables.lua',
    'client/hookah.lua',
    'client/consume.lua',
    'client/interactions.lua',
    'client/devtools.lua',
    'client/setup.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/locale.js',
    'html/assets/icons/*.svg',
    'html/assets/fonts/*.ttf',
}
