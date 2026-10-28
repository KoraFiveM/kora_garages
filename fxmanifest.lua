fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_garages'
-- Keep the legacy resource name resolvable for exports['qbgarages'] callers.
provide 'qbgarages'
author 'qbcore2'
version '0.2.0'
description 'Player-owned vehicle garages: store/retrieve, job and gang fleets, private house garages, and an impound lot with a fee'

dependency 'kora_theme'
dependency 'kora_lib'
dependency 'kora_core'
dependency 'kora_target'
dependency 'kora_sql'

shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'
shared_script '@kora_sql/init.lua'

shared_scripts {
    'shared/config.lua',
}

server_scripts {
    'server/property.lua',
    'server/server.lua',
}

files { 'sql/001_property_garages.sql' }

client_scripts {
    'client/client.lua',
}
