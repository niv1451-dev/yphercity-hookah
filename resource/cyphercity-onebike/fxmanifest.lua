fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cyphercity-onebike'
author 'CypherCity'
description 'One Bike electric fat-tire bicycle for CypherCity: pedalling e-bike, one rider'
version '1.1.0'

-- The model itself (onebike.yft, onebike_hi.yft, onebike.ytd) goes in stream/,
-- which FiveM streams automatically. See README.md and docs/MODEL_BRIEF.md.
-- Ride physics and sound come from the game's own e-bike (Inductor), so the
-- server needs game build 2802 or newer (sv_enforceGameBuild).

files {
    'data/vehicles.meta',
    'data/carvariations.meta',
}

data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'

client_script 'client.lua'
