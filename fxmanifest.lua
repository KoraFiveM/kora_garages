fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbgarages'
author 'qbcore2'
version '0.2.0'
description 'Player-owned vehicle garages: store/retrieve, job and gang fleets, private house garages, and an impound lot with a fee'

dependency 'qbtheme'
dependency 'qblib'
dependency 'qbcore'
dependency 'qbtarget'
dependency 'qbsql'

shared_script '@qblib/init.lua'
shared_script '@qbcore/init.lua'
shared_script '@qbsql/init.lua'

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
