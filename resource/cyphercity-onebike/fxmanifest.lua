fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cyphercity-onebike'
author 'CypherCity'
description 'One Bike electric fat-tire bike for CypherCity: throttle e-bike, feet on turning pedals, one rider'
version '1.3.0'

-- The model itself (onebike.yft, onebike_hi.yft, onebike.ytd) goes in stream/,
-- which FiveM streams automatically. See README.md and docs/MODEL_BRIEF.md.
-- It drives as an electric motorbike with its own handling (data/handling.meta, about 50 km/h)
-- and the sound of the game's electric motorbike (Powersurge), so the server needs a game build
-- that has the Powersurge: 3095 or newer (sv_enforceGameBuild).

files {
    'data/handling.meta',
    'data/vehicles.meta',
    'data/carvariations.meta',
}

data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'

client_script 'client.lua'
