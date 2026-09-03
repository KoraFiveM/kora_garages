-- Impound release: the fee, its ORDER, and what happens when either half fails.
--
-- The ordering rule is the whole test file. Charging after clearing the flag
-- turns an unaffordable retrieval into a free one, because the row is already
-- `garaged` by the time the charge fails.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local world = mocks.install()
dofile('config.lua')
dofile('shared/garages.lua')
dofile('server/access.lua')
dofile('server/api.lua')

local api = Garages.api
local lot = Config.garages.impoundlot

local function at(coords, offset)
    return { x = coords.x + (offset or 0), y = coords.y, z = coords.z }
end

local function stand(garageId)
    world.movePlayer(1, at(Config.garages[garageId].coords))
end

world.setPlayer(1, {
    citizenid = 'CID1', coords = at(lot.coords),
    money = { cash = 100, bank = 2000 },
})

h.test('an unaffordable fee refuses, charges nothing, and leaves the car impounded', function()
    stand('impoundlot')
    world.addVehicle({ plate = 'BROKE1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 5000 })

    local result, err = api.retrieveImpound(1, 'impoundlot', 'BROKE1')

    h.assertFalse(result, 'the release must be refused')
    h.assertEqual(err, 'insufficient funds', 'with qbcore\'s own reason, not a reworded one')
    h.assertEqual(world.balance(1, 'bank'), 2000, 'no money moved')
    -- The load-bearing assertion in this file: had the flag been cleared first,
    -- the player would now own a released car they never paid for.
    h.assertEqual(world.vehicles.BROKE1.state, 'impounded', 'and the vehicle is still held')
end)

h.test('an affordable fee is charged before the flag is cleared, and the car comes out', function()
    stand('impoundlot')
    world.addVehicle({ plate = 'PAY1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 750 })

    local result, err = api.retrieveImpound(1, 'impoundlot', 'PAY1')

    h.assertTrue(result ~= false, 'the release should succeed: ' .. tostring(err))
    h.assertEqual(result.fee, 750, 'the fee is reported back, so the UI can say what was paid')
    h.assertEqual(world.balance(1, 'bank'), 1250, 'and it left the configured account')
    -- Released AND handed over in one action: an impound lot that released the
    -- row but left the car in the garage would send the player somewhere else
    -- to collect what they just paid for.
    h.assertEqual(world.vehicles.PAY1.state, 'out', 'the vehicle is out, not merely un-impounded')
    h.assertTrue(result.netId ~= nil, 'with an entity for the client to dress')
end)

h.test('a row with no recorded fee falls back to the configured default', function()
    stand('impoundlot')
    world.addVehicle({ plate = 'NOFEE1', model = 'sultan', citizenid = 'CID1', state = 'impounded' })

    -- Zero would make every impound free, which is the one outcome nobody
    -- configuring an impound lot wants by accident.
    h.assertEqual(api.impoundFee(world.vehicles.NOFEE1), Config.impound.defaultFee, 'the default applies')
end)

h.test('an absurd recorded fee is clamped, not honoured', function()
    world.addVehicle({ plate = 'GOUGE1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 99999999 })

    -- A badly written impound writer must not be able to bankrupt a player.
    h.assertEqual(api.impoundFee(world.vehicles.GOUGE1), Config.impound.maxFee, 'clamped to the ceiling')
end)

h.test('a failed flag-clear refunds the fee', function()
    stand('impoundlot')
    local row = world.addVehicle({ plate = 'FAIL1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 500 })
    row.failClear = true

    local before = world.balance(1, 'bank')
    local result, err = api.retrieveImpound(1, 'impoundlot', 'FAIL1')

    h.assertFalse(result, 'the release fails')
    h.assertEqual(err, 'write failed', 'reporting the persistence error')
    -- A player who is charged and gets nothing has no way to recover. A double
    -- refund is a bug we would rather have than a stolen fee.
    h.assertEqual(world.balance(1, 'bank'), before, 'and the fee is refunded')
    h.assertEqual(world.vehicles.FAIL1.state, 'impounded', 'with the car still held')
end)

h.test('a free release still works and charges nothing', function()
    stand('impoundlot')
    local row = world.addVehicle({ plate = 'FREE1', model = 'sultan', citizenid = 'CID1', state = 'impounded' })
    row.impound_fee = 0

    local saved = Config.impound.defaultFee
    Config.impound.defaultFee = 0

    local before = world.balance(1, 'bank')
    local result = api.retrieveImpound(1, 'impoundlot', 'FREE1')

    h.assertTrue(result ~= false, 'a zero fee is not a failure')
    h.assertEqual(result.fee, 0, 'and is reported as zero')
    h.assertEqual(world.balance(1, 'bank'), before, 'with no money moved at all')

    Config.impound.defaultFee = saved
end)

h.test('an impounded vehicle cannot be released anywhere but a lot', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'WRONG1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 100 })

    local result, err = api.retrieveImpound(1, 'legionsquare', 'WRONG1')
    h.assertFalse(result, 'a street garage does not release impounds')
    h.assertEqual(err, 'impounded vehicles are only released at an impound lot', 'and say where to go')
    h.assertEqual(world.balance(1, 'bank'), 1250, 'and charges nothing on the way to refusing')
end)

h.test('a vehicle that is not impounded is not a release', function()
    stand('impoundlot')
    world.addVehicle({ plate = 'FINE1', model = 'sultan', citizenid = 'CID1', state = 'garaged' })

    local result, err = api.retrieveImpound(1, 'impoundlot', 'FINE1')
    h.assertFalse(result, 'nothing to release')
    h.assertEqual(err, 'vehicle is not impounded', 'and say why')
end)

h.test('somebody else\'s impounded car cannot be released', function()
    stand('impoundlot')
    world.addVehicle({ plate = 'NOTME1', model = 'sultan', citizenid = 'CID_OTHER', state = 'impounded', impound_fee = 100 })

    local before = world.balance(1, 'bank')
    local result, err = api.retrieveImpound(1, 'impoundlot', 'NOTME1')

    h.assertFalse(result, 'ownership is checked before the wallet is touched')
    h.assertEqual(err, 'not your vehicle', 'and say why')
    h.assertEqual(world.balance(1, 'bank'), before, 'so a refused release is never a paid one')
    h.assertEqual(world.vehicles.NOTME1.state, 'impounded', 'and the car stays held')
end)

h.test('a release from out of range is refused before the fee', function()
    world.addVehicle({ plate = 'AWAY1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 100 })
    world.movePlayer(1, at(lot.coords, 50.0))

    local before = world.balance(1, 'bank')
    local result, err = api.retrieveImpound(1, 'impoundlot', 'AWAY1')

    h.assertFalse(result, 'you have to be at the lot')
    h.assertEqual(err, 'too far from the garage', 'and say why')
    h.assertEqual(world.balance(1, 'bank'), before, 'and pay nothing')
end)

h.report('impound')
