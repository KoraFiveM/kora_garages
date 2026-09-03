-- The gate: every way a garage action is refused before it ever reaches
-- qbcore's persistence layer.
--
-- These are the tests that matter most in this resource. Take-out and store are
-- three lines of glue over Core.garage.*; the security IS the feature.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local world = mocks.install()
dofile('config.lua')
dofile('shared/garages.lua')
dofile('server/access.lua')

local legion = Config.garages.legionsquare
local pool = Config.garages.missionrow
local lockup = Config.garages.ballas

local function at(coords, offset)
    return { x = coords.x + (offset or 0), y = coords.y, z = coords.z }
end

-- src 1: an ordinary civilian standing at Legion Square.
world.setPlayer(1, { citizenid = 'CID1', coords = at(legion.coords) })
-- src 2: an on-duty officer at the motor pool.
world.setPlayer(2, {
    citizenid = 'CID2', coords = at(pool.coords),
    job = { name = 'police', onduty = true },
})
-- src 3: the same officer's colleague, off duty.
world.setPlayer(3, {
    citizenid = 'CID3', coords = at(pool.coords),
    job = { name = 'police', onduty = false },
})
-- src 4: a Ballas member at the lockup.
world.setPlayer(4, { citizenid = 'CID4', coords = at(lockup.coords), gang = { name = 'ballas' } })
-- src 9: connected but with no character loaded.
world.setPlayer(9, { coords = at(legion.coords) })

world.addVehicle({ plate = 'CIV1', model = 'sultan', citizenid = 'CID1' })
world.addVehicle({ plate = 'OTHER1', model = 'sultan', citizenid = 'CID_SOMEONE_ELSE' })
world.addVehicle({ plate = 'FLEET1', model = 'police', job = 'police' })

-- --- the garage itself ------------------------------------------------------

h.test('a garage id the config does not know is refused', function()
    -- The browser sends this string. An unknown one must not fall back to some
    -- other garage, which would authorise an action at the wrong place.
    local resolved, err = Garages.access.resolve(1, 'not-a-garage')
    h.assertFalse(resolved, 'an invented garage id must be refused')
    h.assertEqual(err, 'unknown garage', 'and named as such')

    h.assertFalse(Garages.access.resolve(1, nil), 'so must a missing one')
    h.assertFalse(Garages.access.resolve(1, { id = 'legionsquare' }), 'and a table pretending to be one')
end)

h.test('a garage whose type is not configured fails closed', function()
    -- A typo'd type has no idea who may use the garage, so guessing "everyone"
    -- would silently open it to the whole server.
    Config.garages.brokenone = { type = 'multistorey', label = 'Broken', coords = at(legion.coords), spawns = {}, bucket = 0 }

    local resolved, err = Garages.access.resolve(1, 'brokenone')
    h.assertFalse(resolved, 'an unknown type must not resolve')
    h.assertEqual(err, 'garage has no known type', 'and say why')

    Config.garages.brokenone = nil
end)

-- --- character --------------------------------------------------------------

h.test('a connected player with no character is refused', function()
    local resolved, err = Garages.access.resolve(9, 'legionsquare')
    h.assertFalse(resolved, 'no citizenid means no garage')
    h.assertEqual(err, 'no loaded character', 'and say why')
end)

-- --- distance ---------------------------------------------------------------

h.test('an action from out of range is refused', function()
    h.assertTrue(Garages.access.resolve(1, 'legionsquare') ~= nil, 'in range to start with')

    -- Just past the configured reach. The client's qbtarget zone is wider than
    -- this on purpose, so "the prompt appeared" is never proof of range.
    world.movePlayer(1, at(legion.coords, Config.interaction.distance + 1.0))

    local resolved, err = Garages.access.resolve(1, 'legionsquare')
    h.assertFalse(resolved, 'out of range must be refused')
    h.assertEqual(err, 'too far from the garage', 'and say why')

    world.movePlayer(1, at(legion.coords))
end)

h.test('a garage across the map is refused even while standing in another one', function()
    -- The realistic exploit: keep the panel open at Legion Square and send the
    -- id of the police motor pool with it.
    local resolved, err = Garages.access.resolve(1, 'missionrow')
    h.assertFalse(resolved, 'a distant garage must be refused')
    -- Refused on the JOB before distance is even measured, which is the
    -- stricter of the two answers and the one worth reporting.
    h.assertEqual(err, 'this garage is not for your job', 'on the first failing rule')
end)

-- --- routing bucket ---------------------------------------------------------

h.test('a player in another routing bucket is refused', function()
    world.setBucket(1, 7)

    local resolved, err = Garages.access.resolve(1, 'legionsquare')
    h.assertFalse(resolved, 'a different world is not this garage')
    h.assertEqual(err, 'garage is not in your world', 'and say why')

    world.setBucket(1, 0)
    h.assertTrue(Garages.access.resolve(1, 'legionsquare') ~= nil, 'and allowed again on return')
end)

h.test('a garage with no configured bucket fails closed', function()
    -- "Any bucket" must not be something a garage can mean by omission, or an
    -- instanced apartment garage becomes reachable from the open world.
    local saved = Config.garages.legionsquare.bucket
    Config.garages.legionsquare.bucket = nil

    local resolved, err = Garages.access.resolve(1, 'legionsquare')
    h.assertFalse(resolved, 'a bucketless garage must not resolve')
    h.assertEqual(err, 'garage has no routing bucket', 'and say why')

    Config.garages.legionsquare.bucket = saved
end)

h.test('the bucket check fails closed when the native is missing', function()
    -- A future FXServer that moved this native client-side must degrade into
    -- "refused", never into "unchecked".
    local saved = _G.GetPlayerRoutingBucket
    _G.GetPlayerRoutingBucket = nil

    local ok, err = Garages.access.sameBucket(1, Config.garages.legionsquare)
    h.assertFalse(ok, 'a missing native must not skip the check')
    h.assertEqual(err, 'routing bucket validation unavailable', 'and say so plainly')

    _G.GetPlayerRoutingBucket = saved
end)

-- --- job and gang -----------------------------------------------------------

h.test('a job garage admits only that job, on duty', function()
    h.assertTrue(Garages.access.resolve(2, 'missionrow') ~= nil, 'the on-duty officer')

    local resolved, err = Garages.access.resolve(3, 'missionrow')
    h.assertFalse(resolved, 'the off-duty officer must be refused')
    h.assertEqual(err, 'you must be on duty', 'and told which rule')
end)

h.test('a gang garage admits only that gang, with no duty concept', function()
    h.assertTrue(Garages.access.resolve(4, 'ballas') ~= nil, 'the member, who is never "on duty"')

    world.setPlayer(5, { citizenid = 'CID5', coords = at(lockup.coords), gang = { name = 'vagos' } })
    local resolved, err = Garages.access.resolve(5, 'ballas')
    h.assertFalse(resolved, 'a rival must be refused')
    h.assertEqual(err, 'this garage is not for your gang', 'and told why')
end)

-- --- ownership --------------------------------------------------------------

h.test('a plate owned by somebody else is refused', function()
    local resolved = Garages.access.resolve(1, 'legionsquare')

    local row, err = Garages.access.ownedRowFor(resolved, 'OTHER1')
    h.assertFalse(row, 'another character\'s car must be refused')
    h.assertEqual(err, 'not your vehicle', 'and say why')

    h.assertTrue(Garages.access.ownedRowFor(resolved, 'CIV1') ~= nil, 'their own is fine')
end)

h.test('a plate is matched after normalisation, not raw', function()
    local resolved = Garages.access.resolve(1, 'legionsquare')

    -- GTA pads a plate to eight characters with spaces, so the string read off a
    -- live entity is not equal to the one in SQL until both are normalised.
    -- Getting this wrong reports "not your vehicle" for a car the player is in.
    h.assertTrue(Garages.access.ownedRowFor(resolved, 'civ1    ') ~= nil, 'padded and lowercase resolves')
    h.assertFalse(Garages.access.ownedRowFor(resolved, ''), 'an empty plate does not')
    h.assertFalse(Garages.access.ownedRowFor(resolved, 12345), 'nor a number')
    h.assertFalse(Garages.access.ownedRowFor(resolved, 'TOOLONGPLATE'), 'nor an over-long one')
end)

h.test('an unknown plate is refused rather than treated as unowned', function()
    local resolved = Garages.access.resolve(1, 'legionsquare')
    local row, err = Garages.access.ownedRowFor(resolved, 'GHOST')
    h.assertFalse(row, 'a plate with no row must be refused')
    h.assertEqual(err, 'unknown vehicle', 'and say why')
end)

h.test('a job-fleet row is only reachable at its own job garage', function()
    local pd = Garages.access.resolve(2, 'missionrow')
    h.assertTrue(Garages.access.ownedRowFor(pd, 'FLEET1') ~= nil, 'the cruiser at the motor pool')

    -- Without the job rule, a cruiser row would be retrievable from Legion
    -- Square by anyone who knew the plate -- the row has no citizenid to check.
    local resolved = Garages.access.resolve(1, 'legionsquare')
    local row, err = Garages.access.ownedRowFor(resolved, 'FLEET1')
    h.assertFalse(row, 'and nowhere else')
    h.assertEqual(err, 'not your vehicle', 'reported the same way as any other refusal')
end)

h.report('access')
