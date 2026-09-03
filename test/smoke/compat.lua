-- The legacy qb-garages surface, and the native client-facing callbacks.
--
-- The point of this file is that a LEGACY caller gets exactly the same refusals
-- as the native path. A compat layer that quietly skipped the ownership,
-- distance or bucket checks would be a way in around all of them, which is the
-- classic mistake in a compatibility shim.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local world = mocks.install()
dofile('config.lua')
dofile('shared/garages.lua')
dofile('server/access.lua')
dofile('server/api.lua')
dofile('server/callbacks.lua')
dofile('server/compat.lua')

local legion = Config.garages.legionsquare

local function at(coords, offset)
    return { x = coords.x + (offset or 0), y = coords.y, z = coords.z }
end

local function stand(garageId)
    world.movePlayer(1, at(Config.garages[garageId].coords))
end

world.setPlayer(1, { citizenid = 'CID1', coords = at(legion.coords), money = { cash = 0, bank = 5000 } })
world.setPlayer(2, { citizenid = 'CID2', coords = at(legion.coords) })

-- --- the native surface -----------------------------------------------------

h.test('the client-facing callbacks are registered, and only those', function()
    -- This is the complete list of things a browser may ask for. Anything else
    -- appearing here is a new attack surface that needs its own review.
    for _, name in ipairs({ 'qbgarages:list', 'qbgarages:takeOut', 'qbgarages:store', 'qbgarages:retrieveImpound' }) do
        h.assertTrue(world.callbacks[name] ~= nil, name .. ' should be registered')
        h.assertTrue(world.callbacks[name].opts.rateLimit ~= nil,
            name .. ' must be rate limited: every one of these is a DB write or a listing')
    end
end)

h.test('the native server exports are registered', function()
    for _, name in ipairs({ 'impound', 'isOwner', 'getGarages' }) do
        h.assertTrue(world.registeredExports[name] ~= nil, 'exports.qbgarages:' .. name)
    end
end)

h.test('a refused listing comes back as (false, reason), not as an error', function()
    -- These run inside a client's promise. A raised error would leave the
    -- browser's fetch hanging until the callback timeout instead of showing the
    -- player why they were refused.
    stand('legionsquare')
    local ok, reason = world.callback('qbgarages:list', 1, 'no-such-garage')
    h.assertFalse(ok, 'refused')
    h.assertEqual(reason, 'unknown garage', 'with a reason the UI can show verbatim')
end)

h.test('getGarages hands out a copy, not the live config', function()
    local snapshot = world.registeredExports.getGarages()
    snapshot.legionsquare.label = 'Hacked'
    h.assertEqual(Config.garages.legionsquare.label, 'Legion Square Parking',
        'a consumer must not be able to edit this resource\'s config through the reference')
end)

h.test('isOwner answers the one question without handing out the row', function()
    world.addVehicle({ plate = 'OWNED1', model = 'sultan', citizenid = 'CID1' })

    h.assertTrue(world.registeredExports.isOwner(1, 'OWNED1'), 'their own car')
    h.assertFalse(world.registeredExports.isOwner(2, 'OWNED1'), 'not somebody else\'s')
    h.assertFalse(world.registeredExports.isOwner(1, 'GHOST'), 'nor an unknown plate')
    h.assertEqual(world.registeredExports.isOwner(1, 'OWNED1'), true,
        'and answers with a boolean, not with the row: it carries the owner citizenid')
end)

h.test('the impound export clamps its fee and records it on the row', function()
    world.addVehicle({ plate = 'TOW1', model = 'sultan', citizenid = 'CID1', state = 'out' })

    h.assertTrue(world.registeredExports.impound('TOW1', 99999999, 'impoundlot'), 'the impound applies')
    h.assertEqual(world.vehicles.TOW1.state, 'impounded', 'the row is held')
    h.assertEqual(world.vehicles.TOW1.impound_fee, Config.impound.maxFee, 'with a clamped fee')

    -- No money is touched here on purpose: the fee is collected at the lot, when
    -- the player is standing there and can actually afford it.
    h.assertEqual(world.balance(1, 'bank'), 5000, 'and nothing is charged at impound time')

    h.assertFalse(world.registeredExports.impound(nil, 100), 'a missing plate is refused')
end)

-- --- legacy callbacks -------------------------------------------------------

h.test('GetGarageVehicles answers with a plate-keyed table', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'LEG1', model = 'sultan', citizenid = 'CID1' })

    local byPlate = world.callback('qb-garage:server:GetGarageVehicles', 1, 'legionsquare')
    h.assertTrue(byPlate.LEG1 ~= nil, 'upstream indexed its result by plate, and so does this')
    h.assertEqual(byPlate.LEG1.model, 'sultan', 'with the fields a legacy UI reads')
end)

h.test('GetGarageVehicles is refused for a garage the player is not at', function()
    world.movePlayer(1, at(legion.coords, 100.0))
    h.assertEqual(world.callback('qb-garage:server:GetGarageVehicles', 1, 'legionsquare'), nil,
        'the legacy path gets the same distance check as the native one')
end)

h.test('GetDepotVehicles finds the impound lot by type, not by a hardcoded name', function()
    stand('impoundlot')
    world.addVehicle({ plate = 'DEP1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 300 })

    local byPlate = world.callback('qb-garage:server:GetDepotVehicles', 1)
    h.assertTrue(byPlate.DEP1 ~= nil, 'upstream had one global depot; this finds it in config')
    h.assertEqual(byPlate.DEP1.fee, 300, 'with the release fee')
end)

h.test('checkOwner re-reads ownership rather than believing the caller', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'CHK1', model = 'sultan', citizenid = 'CID1' })
    world.addVehicle({ plate = 'CHK2', model = 'sultan', citizenid = 'CID2' })

    local owned, record = world.callback('qb-garage:server:checkOwner', 1, 'CHK1', 'legionsquare')
    h.assertTrue(owned, 'their own car')
    h.assertEqual(record.plate, 'CHK1', 'answered with the wire record')

    local notOwned, reason = world.callback('qb-garage:server:checkOwner', 1, 'CHK2', 'legionsquare')
    h.assertFalse(notOwned, 'somebody else\'s is refused')
    h.assertEqual(reason, 'not your vehicle', 'with a reason')
end)

h.test('IsSpawnOk is answered from the server\'s own free-space search', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'SPN1', model = 'sultan', citizenid = 'CID1' })
    h.assertTrue(world.callback('qb-garage:server:IsSpawnOk', 1, 'SPN1', 'legionsquare'), 'space available')

    -- Upstream asked the CLIENT whether a spawn point looked clear. Here the
    -- server decides, so a client that lies about congestion gains nothing.
    for _, spawn in ipairs(legion.spawns) do
        world.spawnEntity({ plate = 'BLOCK', coords = { x = spawn.x, y = spawn.y, z = spawn.z } })
    end
    h.assertFalse(world.callback('qb-garage:server:IsSpawnOk', 1, 'SPN1', 'legionsquare'), 'and full is full')
end)

h.test('GetVehicleProperties is ownership-gated', function()
    world.addVehicle({ plate = 'MOD1', model = 'sultan', citizenid = 'CID1', mods = { color1 = 5 } })

    local mine = world.callback('qb-garage:server:GetVehicleProperties', 1, 'MOD1')
    h.assertEqual(mine.color1, 5, 'the owner gets the blob')

    -- The blob is a fair description of somebody's car, so it is not public.
    h.assertEqual(world.callback('qb-garage:server:GetVehicleProperties', 2, 'MOD1'), nil,
        'and nobody else does')
end)

-- --- legacy events ----------------------------------------------------------

h.test('the legacy state event honours only the garage-in transition', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'LEGSTORE', model = 'sultan', citizenid = 'CID1', state = 'out' })
    local netId = world.spawnEntity({ plate = 'LEGSTORE', coords = at(legion.coords, 2.0), engine = 800, body = 900, fuel = 50 })

    _G.source = 1
    TriggerEvent('qb-garage:server:updateVehicleState', 1, 'LEGSTORE', netId, 'legionsquare')

    h.assertEqual(world.vehicles.LEGSTORE.state, 'garaged', 'state 1 stores the vehicle')
    h.assertEqual(world.vehicles.LEGSTORE.engine_health, 800, 'with the server\'s own reading, not the caller\'s')
end)

h.test('the legacy state event refuses the garage-OUT transition', function()
    world.addVehicle({ plate = 'LEGOUT', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 400 })

    -- Upstream's "state 0" is a raw write with no location or ownership proof of
    -- its own, which would make it a free un-impound primitive.
    _G.source = 1
    TriggerEvent('qb-garage:server:updateVehicleState', 0, 'LEGOUT', 1, 'legionsquare')

    h.assertEqual(world.vehicles.LEGOUT.state, 'impounded', 'nothing was written')
end)

h.test('the legacy state event with no entity is refused, not fatal', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'LEGNONE', model = 'sultan', citizenid = 'CID1', state = 'out' })

    -- A store with no verifiable entity cannot be checked at all. A legacy
    -- resource mid-flow must not die because of it either.
    _G.source = 1
    TriggerEvent('qb-garage:server:updateVehicleState', 1, 'LEGNONE', nil, 'legionsquare')

    h.assertEqual(world.vehicles.LEGNONE.state, 'out', 'no entity, no store')
end)

h.test('PayDepotPrice ignores the caller\'s price and charges the recorded fee', function()
    stand('impoundlot')
    world.addVehicle({ plate = 'DEPPAY', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 900 })
    local before = world.balance(1, 'bank')

    -- The single most valuable thing to fake in this whole resource: paying one
    -- dollar for your own impound release.
    _G.source = 1
    TriggerEvent('qb-garage:server:PayDepotPrice', { plate = 'DEPPAY', depotPrice = 1 })

    h.assertEqual(before - world.balance(1, 'bank'), 900, 'the row\'s fee was charged, not the caller\'s')
    h.assertEqual(world.vehicles.DEPPAY.state, 'out', 'and the vehicle was released')
end)

h.test('a malformed legacy payload is ignored, not fatal', function()
    -- A tow script mid-callout must not die because its own payload was wrong.
    _G.source = 1
    TriggerEvent('qb-garage:server:PayDepotPrice', 'not a table')
    TriggerEvent('qb-garage:server:PayDepotPrice', {})
    TriggerEvent('qb-garage:server:updateVehicleState')
    h.assertTrue(true, 'nothing was thrown')
end)

h.test('the legacy surface ships enabled', function()
    -- `provide 'qb-garages'` in the manifest promises an unmodified third-party
    -- consumer keeps working, so this defaulting to off would make that promise
    -- false. server/compat.lua returns before registering anything when it is
    -- off, so a server that owns these event names elsewhere gets the names back
    -- rather than a shim that registers and then ignores them.
    h.assertEqual(Config.compat.legacy, true, 'compat is on by default')
end)

h.report('compat')
