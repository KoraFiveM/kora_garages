fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbgarages'
author 'qbcore2'
version '0.1.0'
description 'Player-owned vehicle garages: store/retrieve, job and gang fleets, and an impound lot with a fee'

-- Speaks the REAL qb-garages wire protocol (the `qb-garage:*` callback and
-- event names, matching github.com/qbcore-framework/qb-garages) from
-- server/compat.lua, so a job script or a tow resource written against it keeps
-- working unmodified -- same convention as qbclothing's manifest comment.
provide 'qb-garages'

-- qbcore owns the `player_vehicles` table this resource is a UI over
-- (Core.garage.*), and its money export charges the impound fee. qbtarget
-- supplies the interaction zones registered at client script load time, so it
-- must be RUNNING before those registrations -- `dependency` creates that
-- start-order edge regardless of the server.cfg `ensure` position.
dependency 'qbtheme'
dependency 'qblib'
dependency 'qbcore'
dependency 'qbtarget'

shared_script '@qblib/init.lua'
shared_script '@qbcore/init.lua'

shared_scripts {
    'config.lua',
    'shared/garages.lua',
}

-- Explicit, never globbed -- alphabetic glob order would load callbacks.lua
-- before the api.lua it registers handlers into. access.lua defines the
-- ownership/distance/bucket gate every action funnels through and must load
-- first; compat.lua registers the legacy `qb-garage:*` surface and must load
-- last so every real API function it forwards to already exists.
server_scripts {
    'server/access.lua',
    'server/api.lua',
    'server/callbacks.lua',
    'server/compat.lua',
}

-- state.lua owns the local cache that the shared qblib AppShell renders.
-- actions.lua drives take-out/store and zones/blips/exports are entry points.
client_scripts {
    'client/state.lua',
    'client/ui.lua',
    'client/actions.lua',
    'client/zones.lua',
    'client/blips.lua',
    'client/exports.lua',
}
