fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbgarages'
author 'qbcore2'
version '0.2.0'
description 'Player-owned vehicle garages: store/retrieve, job and gang fleets, private house garages, and an impound lot with a fee'

-- qbcore owns player_vehicles and the money export; qbtarget supplies the
-- interaction zones registered at client script load, so it must be running
-- first regardless of server.cfg ensure order.
dependency 'qbtheme'
dependency 'qblib'
dependency 'qbcore'
dependency 'qbtarget'
dependency 'oxmysql'

shared_script '@qblib/init.lua'
shared_script '@qbcore/init.lua'
shared_script '@qbsql/init.lua'
    
shared_scripts {
    'config.lua',
    'shared/garages.lua',
}

-- access.lua must load before api.lua, which callbacks.lua registers into.
server_scripts {
    'server/server.lua',
}

client_scripts {
    'client/client.lua',
}
