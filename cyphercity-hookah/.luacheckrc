-- luacheck configuration for cyphercity-hookah (run: luacheck .)
std = 'lua54'
max_line_length = false

-- Modules defined by this resource (shared between files)
globals = {
    'Config', 'ServerConfig', 'Utils', 'Locales', 'L', 'Catalog', 'Bridge', 'Callback',
    'Framework', 'Notify', 'Target', 'Inventory', 'Banking', 'Logger', 'Security', 'Staff',
    'Persistence', 'Sync', 'Tables', 'Hookah', 'Orders', 'Payments', 'Diagnostics', 'Server',
    'Business', 'UI', 'State', 'Client', 'ClientUtil', 'Peds', 'Furniture', 'Seat',
    'HookahClient', 'Consume', 'Interactions',
}

-- Lower-case globals provided by the FiveM Lua runtime
read_globals = { 'vec3', 'vec4', 'vector3', 'vector4', 'json', 'exports', 'promise', 'source', 'msgpack' }

-- FiveM natives are global functions in PascalCase (CreatePed, GetPlayerPed, ...).
-- Undefined PascalCase globals are therefore allowed; every lower-case typo is still reported.
ignore = { '113/%u.*', '212' }

exclude_files = { 'tests/**', 'html/**' }

files['fxmanifest.lua'] = {
    read_globals = { 'fx_version', 'game', 'lua54', 'name', 'author', 'description', 'version',
        'shared_scripts', 'server_scripts', 'client_scripts', 'ui_page', 'files', 'dependency', 'dependencies' },
}
