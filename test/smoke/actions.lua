-- Take out and store, end to end through qbcore's persistence semantics.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local world = mocks.install()
dofile('config.lua')
dofile('shared/garages.lua')
dofile('server/access.lua')
dofile('server/api.lua')

local api = Garages.api
local legion = Config.garages.legionsquare

local function at(coords, offset)
    return { x = coords.x + (offset or 0), y = coords.y, z = coords.z }
end

world.setPlayer(1, { citizenid = 'CID1', coords = at(legion.coords) })
world.setPlayer(2, { citizenid = 'CID2', coords = at(legion.coords) })

---Stands src 1 at a garage. Called at the START of every test rather than
---restored at the end: a test that fails mid-way would otherwise leave the
---player at the wrong garage and every later test would fail on distance
---instead of on the rule it was written for.
local function stand(garageId)
    world.movePlayer(1, at(Config.garages[garageId].coords))
end

-- --- listing ----------------------------------------------------------------

h.test('the listing shows only the caller\'s own vehicles', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'MINE1', model = 'sultan', citizenid = 'CID1' })
    world.addVehicle({ plate = 'THEIRS1', model = 'sultan', citizenid = 'CID2' })

    local payload = api.list(1, 'legionsquare')
    h.assertEqual(#payload.vehicles, 1, 'one car')
    h.assertEqual(payload.vehicles[1].plate, 'MINE1', 'and it is theirs')
end)

h.test('the wire record carries condition and state, never identity', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'COND1', model = 'sultan', citizenid = 'CID1', fuel = 42, engine = 750, body = 500 })

    local payload = api.list(1, 'legionsquare')
    local record
    for _, vehicle in ipairs(payload.vehicles) do
        if vehicle.plate == 'COND1' then record = vehicle end
    end

    h.assertEqual(record.fuel, 42, 'fuel as stored')
    h.assertEqual(record.engine, 75, 'engine as a percentage, so the browser never learns the 0..1000 scale')
    h.assertEqual(record.body, 50, 'body likewise')
    h.assertEqual(record.state, 'garaged', 'state is what the take-out button is enabled on')
    h.assertEqual(record.label, 'Karin Sultan', 'the registry name, not the spawn code')
    -- The DB row also carries the owner, the mods blob and the last known world
    -- position. A UI needs none of the three, and the last one is a hint about
    -- where to find somebody's car.
    h.assertEqual(record.citizenid, nil, 'the owner citizenid never reaches the browser')
    h.assertEqual(record.mods, nil, 'nor the mods blob')
    h.assertEqual(record.last_position, nil, 'nor where the car was last seen')
end)

h.test('an impounded vehicle is hidden from an ordinary garage and shown at the lot', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'HELD1', model = 'sultan', citizenid = 'CID1', state = 'impounded', impound_fee = 750 })

    for _, vehicle in ipairs(api.list(1, 'legionsquare').vehicles) do
        h.assertTrue(vehicle.plate ~= 'HELD1', 'a street garage must not offer a car the lot is holding')
    end

    stand('impoundlot')
    local lot = api.list(1, 'impoundlot')

    local found
    for _, vehicle in ipairs(lot.vehicles) do
        if vehicle.plate == 'HELD1' then found = vehicle end
    end
    h.assertTrue(found ~= nil, 'the lot lists it')
    h.assertEqual(found.fee, 750, 'with the fee that was recorded on the row')
    h.assertEqual(#lot.vehicles, 1, 'and nothing that is not impounded')
    h.assertFalse(lot.garage.canStore, 'storing at an impound lot is meaningless and the UI is told so')
end)

-- --- take out ---------------------------------------------------------------

h.test('taking out spawns the vehicle and marks the row out', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'OUT1', model = 'sultan', citizenid = 'CID1' })

    local result, err = api.takeOut(1, 'legionsquare', 'OUT1')
    h.assertTrue(result ~= false, 'the take-out should succeed: ' .. tostring(err))
    h.assertTrue(result.netId ~= nil, 'and hand back a network id for the client to dress')
    h.assertEqual(world.vehicles.OUT1.state, 'out', 'the row is out')
    h.assertEqual(result.plate, 'OUT1', 'the plate comes back from the DB row, not from the request')
end)

h.test('a vehicle that is already out cannot be taken out twice', function()
    stand('legionsquare')
    -- Otherwise one plate becomes an unlimited vehicle spawner: press the button
    -- twice and there are two of the same car.
    local result, err = api.takeOut(1, 'legionsquare', 'OUT1')
    h.assertFalse(result, 'the second attempt must be refused')
    h.assertEqual(err, 'vehicle is already out', 'and say why')
end)

h.test('an impounded vehicle cannot be taken out of an ordinary garage', function()
    stand('legionsquare')
    local result, err = api.takeOut(1, 'legionsquare', 'HELD1')
    h.assertFalse(result, 'an impounded car is not in the garage')
    h.assertTrue(err:find('impounded', 1, true) ~= nil, 'and say so: ' .. tostring(err))
    h.assertTrue(err:find('impound lot', 1, true) ~= nil, 'and say where it is instead')
    h.assertEqual(world.vehicles.HELD1.state, 'impounded', 'and nothing changes')
end)

h.test('a garage refuses a vehicle outside its allowed categories', function()
    world.addVehicle({ plate = 'HELI1', model = 'buzzard', citizenid = 'CID1' })
    world.addVehicle({ plate = 'CAR1', model = 'sultan', citizenid = 'CID1' })
    stand('paletoair')

    local result, err = api.takeOut(1, 'paletoair', 'CAR1')
    h.assertFalse(result, 'a saloon is not a hangar vehicle')
    h.assertEqual(err, 'this garage does not accept that vehicle', 'and say why')

    h.assertTrue(api.takeOut(1, 'paletoair', 'HELI1') ~= false, 'the helicopter is fine')
end)

h.test('a model absent from the registry is accepted anywhere', function()
    -- The allow-list keeps a plane out of a street garage; it is not a whitelist
    -- of purchasable cars. Refusing unregistered models would make every addon
    -- vehicle unretrievable the moment one garage grew a `categories` list.
    world.addVehicle({ plate = 'ADDON1', model = 'somecustomcar', citizenid = 'CID1' })
    -- The motel rather than the hangar: paletoair has a single spawn point and
    -- the helicopter above is now parked on it, which would refuse this
    -- take-out for a reason that has nothing to do with the category rule.
    stand('motel')

    h.assertTrue(api.takeOut(1, 'motel', 'ADDON1') ~= false, 'an unknown model is not refused')
end)

h.test('a garage with every space taken refuses rather than stacking cars', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'FULL1', model = 'sultan', citizenid = 'CID1' })

    -- One blocker on each of Legion Square's three configured points.
    for _, spawn in ipairs(legion.spawns) do
        world.spawnEntity({ plate = 'BLOCK', coords = { x = spawn.x, y = spawn.y, z = spawn.z } })
    end

    local result, err = api.takeOut(1, 'legionsquare', 'FULL1')
    h.assertFalse(result, 'a full garage must refuse')
    h.assertEqual(err, 'every space is taken', 'and say why')
    h.assertEqual(world.vehicles.FULL1.state, 'garaged', 'and leave the row alone')
end)

h.test('a blocker in another routing bucket does not occupy a space', function()
    -- A car parked on the same coordinates in a different world is somewhere
    -- else. Counting it would make an instanced garage permanently full.
    local saved = Config.garages.motel.bucket
    for _, spawn in ipairs(Config.garages.motel.spawns) do
        world.spawnEntity({ plate = 'ELSE', coords = { x = spawn.x, y = spawn.y, z = spawn.z }, bucket = 12 })
    end

    h.assertTrue(api.freeSpawn(Config.garages.motel) ~= nil, 'the space is still free')
    Config.garages.motel.bucket = saved
end)

-- --- store ------------------------------------------------------------------

h.test('storing snapshots the SERVER\'s own readings and deletes the entity', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'PARK1', model = 'sultan', citizenid = 'CID1', state = 'out', fuel = 100, engine = 1000, body = 1000 })
    local netId, handle = world.spawnEntity({
        plate = 'PARK1', coords = at(legion.coords, 3.0), engine = 620, body = 415, fuel = 33,
    })

    -- The client sends a mods blob and NOTHING else about the car's condition.
    -- Even if it tried, the values below are read off the entity server-side.
    local ok, err = api.store(1, 'legionsquare', 'PARK1', netId, {
        color1 = 12, modEngine = 3, fuelLevel = 100, engineHealth = 1000,
    })
    h.assertTrue(ok, 'the store should succeed: ' .. tostring(err))

    local row = world.vehicles.PARK1
    h.assertEqual(row.state, 'garaged', 'the row is garaged')
    h.assertEqual(row.engine_health, 620, 'engine health read off the entity, not from the request')
    h.assertEqual(row.body_health, 415, 'body health likewise')
    h.assertEqual(row.fuel, 33, 'and fuel')

    h.assertEqual(row.mods.color1, 12, 'a cosmetic mod is kept')
    h.assertEqual(row.mods.modEngine, nil, 'a performance mod is dropped: a garage is not a free tuner')
    h.assertEqual(row.mods.fuelLevel, nil, 'and a condition value smuggled in as a mod is dropped too')
    h.assertEqual(row.mods.engineHealth, nil, 'both of them')

    -- qbcore's storeVehicle deliberately leaves the entity alive -- it has no
    -- handle. Deleting it is the caller's job, and the caller is the server:
    -- deleting client-side would leave the car driveable for anyone whose client
    -- ignored the request while the row read `garaged`.
    h.assertTrue(world.wasDeleted(handle), 'the live entity is deleted server-side')
end)

h.test('a network id whose entity carries another plate is refused', function()
    stand('legionsquare')
    -- The interesting exploit: own a wreck, park a supercar, and store the
    -- supercar against the wreck's row.
    world.addVehicle({ plate = 'WRECK1', model = 'sultan', citizenid = 'CID1', state = 'out' })
    local netId = world.spawnEntity({ plate = 'SUPER1', coords = at(legion.coords, 2.0) })

    local ok, err = api.store(1, 'legionsquare', 'WRECK1', netId, nil)
    h.assertFalse(ok, 'the plates must match')
    h.assertEqual(err, 'that is not the same vehicle', 'and say why')
    h.assertEqual(world.vehicles.WRECK1.state, 'out', 'and nothing is written')
end)

h.test('a vehicle parked away from the garage cannot be stored', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'FAR1', model = 'sultan', citizenid = 'CID1', state = 'out' })
    local netId = world.spawnEntity({
        plate = 'FAR1', coords = at(legion.coords, Config.interaction.storeDistance + 5.0),
    })

    local ok, err = api.store(1, 'legionsquare', 'FAR1', netId, nil)
    h.assertFalse(ok, 'a car three streets away is not at this garage')
    h.assertEqual(err, 'the vehicle is not at this garage', 'and say why')
end)

h.test('a vehicle in another routing bucket cannot be stored', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'GHOST1', model = 'sultan', citizenid = 'CID1', state = 'out' })
    local netId = world.spawnEntity({ plate = 'GHOST1', coords = at(legion.coords, 2.0), bucket = 9 })

    local ok, err = api.store(1, 'legionsquare', 'GHOST1', netId, nil)
    h.assertFalse(ok, 'a car in another world is not here')
    h.assertEqual(err, 'vehicle is not in your world', 'and say why')
end)

h.test('a network id with no entity behind it is refused', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'NONE1', model = 'sultan', citizenid = 'CID1', state = 'out' })

    h.assertFalse(api.store(1, 'legionsquare', 'NONE1', 999999, nil), 'an invented net id')
    h.assertFalse(api.store(1, 'legionsquare', 'NONE1', nil, nil), 'a missing one')
    h.assertFalse(api.store(1, 'legionsquare', 'NONE1', 'twelve', nil), 'and a non-numeric one')
end)

h.test('an entity that is not a vehicle is refused', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'PED1', model = 'sultan', citizenid = 'CID1', state = 'out' })
    local netId = world.spawnEntity({ plate = 'PED1', coords = at(legion.coords, 1.0), entityType = 1 })

    local ok, err = api.store(1, 'legionsquare', 'PED1', netId, nil)
    h.assertFalse(ok, 'a ped is not a car')
    h.assertEqual(err, 'entity is not a vehicle', 'and say why')
end)

h.test('storing is refused at an impound lot', function()
    world.addVehicle({ plate = 'LOT1', model = 'sultan', citizenid = 'CID1', state = 'out' })
    stand('impoundlot')
    local netId = world.spawnEntity({ plate = 'LOT1', coords = at(Config.garages.impoundlot.coords, 2.0) })

    -- Otherwise the lot becomes a way to clear an impound without paying: the
    -- row would come out `garaged` with the fee still on it.
    local ok, err = api.store(1, 'impoundlot', 'LOT1', netId, nil)
    h.assertFalse(ok, 'an impound lot is not a garage')
    h.assertEqual(err, 'you cannot store a vehicle here', 'and say why')
end)

h.test('storing somebody else\'s car is refused before any entity work', function()
    stand('legionsquare')
    world.addVehicle({ plate = 'NOTMINE', model = 'sultan', citizenid = 'CID2', state = 'out' })
    local netId = world.spawnEntity({ plate = 'NOTMINE', coords = at(legion.coords, 1.0) })

    local ok, err = api.store(1, 'legionsquare', 'NOTMINE', netId, nil)
    h.assertFalse(ok, 'not the caller\'s car')
    h.assertEqual(err, 'not your vehicle', 'and say why')
    h.assertEqual(world.vehicles.NOTMINE.state, 'out', 'and it stays out')
end)

-- --- mods filter ------------------------------------------------------------

h.test('an oversized mods blob is dropped whole', function()
    -- A client growing a DB column one key at a time. Dropping the blob costs
    -- the player their wheel colour, not their car.
    local huge = {}
    for i = 1, Config.mods.entryCap + 5 do huge['color' .. i] = i end
    h.assertEqual(api.filterMods(huge), nil, 'over the cap')

    h.assertEqual(api.filterMods('not a table'), nil, 'a string')
    h.assertEqual(api.filterMods(nil), nil, 'nothing at all')
    h.assertEqual(api.filterMods({ modEngine = 4, modBrakes = 2 }), nil,
        'a blob of nothing but performance mods filters down to nothing')
end)

h.report('actions')
