-- The shipped config, checked against the rules the code relies on.
--
-- Every garage in Config.garages is a live security boundary: a missing bucket,
-- an unknown type or an empty spawn list all fail CLOSED at runtime, which means
-- a config typo shows up as "this garage does not work" with no error anywhere.
-- This suite is what turns that into a test failure instead.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/garages.lua')

local S = Garages.shared

h.test('the interaction mode selects a supported provider', function()
    h.assertTrue(Config.interaction.mode == 'target' or Config.interaction.mode == 'interact',
        "interaction mode must be 'target' or 'interact'")
end)

h.test('every garage names a configured type', function()
    for id, garage in pairs(Config.garages) do
        h.assertTrue(Config.garageTypes[garage.type] ~= nil,
            ('%s has type %q, which is not in Config.garageTypes'):format(id, tostring(garage.type)))
    end
end)

h.test('every garage has coordinates, a label and an explicit routing bucket', function()
    for id, garage in pairs(Config.garages) do
        h.assertEqual(type(garage.label), 'string', id .. ' needs a label: it is the qbtarget prompt')
        h.assertEqual(type(garage.coords), 'table', id .. ' needs coords')
        h.assertEqual(type(garage.coords.x), 'number', id .. ' coords need a numeric x')
        -- Not merely present: numeric. A nil bucket fails the runtime check, so a
        -- garage missing one is silently unusable in game.
        h.assertEqual(type(garage.bucket), 'number', id .. ' needs an explicit numeric bucket')
    end
end)

h.test('every garage has at least one spawn point with a heading', function()
    for id, garage in pairs(Config.garages) do
        h.assertEqual(type(garage.spawns), 'table', id .. ' needs a spawns list')
        h.assertTrue(#garage.spawns >= 1, id .. ' needs at least one spawn point')
        for index, spawn in ipairs(garage.spawns) do
            local where = ('%s spawn %d'):format(id, index)
            h.assertEqual(type(spawn.x), 'number', where .. ' needs x')
            h.assertEqual(type(spawn.y), 'number', where .. ' needs y')
            h.assertEqual(type(spawn.z), 'number', where .. ' needs z')
            -- Without `w` a retrieved car faces due north regardless of the bay
            -- it is in, which reads as a bug rather than as a missing field.
            h.assertEqual(type(spawn.w), 'number', where .. ' needs a heading (w)')
        end
    end
end)

h.test('spawn points are far enough apart to actually be separate spaces', function()
    -- Two points closer than the clearance can never both be free, so the second
    -- one is dead config: the garage silently has one fewer bay than it looks.
    for id, garage in pairs(Config.garages) do
        for i = 1, #garage.spawns do
            for j = i + 1, #garage.spawns do
                local separation = S.distance(garage.spawns[i], garage.spawns[j])
                h.assertTrue(separation >= Config.spawn.clearance,
                    ('%s spawns %d and %d are %.1fm apart, under the %.1fm clearance'):format(
                        id, i, j, separation, Config.spawn.clearance))
            end
        end
    end
end)

h.test('spawn points are reachable from the garage marker', function()
    -- A spawn point beyond the store distance produces the absurd sequence:
    -- retrieve a car, then be told it is not at this garage when you try to put
    -- it back without moving it.
    for id, garage in pairs(Config.garages) do
        for index, spawn in ipairs(garage.spawns) do
            local separation = S.distance(garage.coords, spawn)
            h.assertTrue(separation <= Config.interaction.storeDistance,
                ('%s spawn %d is %.1fm from the marker, past the %.1fm store distance'):format(
                    id, index, separation, Config.interaction.storeDistance))
        end
    end
end)

h.test('every garage type supplies a label for the map legend', function()
    -- client/blips.lua assigns category 2, which lists these labels outside
    -- GTA's Owned Property group. See qblib/modules/blips/docs.md.
    for name, policy in pairs(Config.garageTypes) do
        h.assertEqual(type(policy.blipLabel), 'string', name .. ' needs a shared blipLabel')
        h.assertEqual(type(policy.blipSprite), 'number', name .. ' needs a blip sprite')
        h.assertEqual(type(policy.blipColor), 'number', name .. ' needs a blip colour')
        h.assertTrue(policy.shows == 'garaged' or policy.shows == 'impounded',
            name .. ' must show either garaged or impounded vehicles')
    end

    -- The two street types deliberately share ONE label: to a player, a public
    -- and a private garage are both just "a garage".
    h.assertEqual(Config.garageTypes.public.blipLabel, Config.garageTypes.private.blipLabel,
        'public and private share one map label on purpose')
end)

h.test('a job garage names a job, a gang garage names a gang', function()
    for id, garage in pairs(Config.garages) do
        if garage.type == 'job' then
            h.assertEqual(type(garage.job), 'string', id .. ' is a job garage with no job')
        elseif garage.type == 'gang' then
            h.assertEqual(type(garage.gang), 'string', id .. ' is a gang garage with no gang')
        else
            -- The reverse matters too: a `job` on a public garage would gate it
            -- without any of the type's own duty policy applying.
            h.assertEqual(garage.job, nil, id .. ' is not a job garage but names a job')
            h.assertEqual(garage.gang, nil, id .. ' is not a gang garage but names a gang')
        end
    end
end)

h.test('exactly one impound lot exists, and it refuses storing', function()
    -- The legacy `qb-garage:server:GetDepotVehicles`/`PayDepotPrice` path finds
    -- the lot by TYPE (upstream had one global depot and took no argument), so a
    -- config with none makes both legacy entry points dead.
    local lots = 0
    for _, garage in pairs(Config.garages) do
        if garage.type == 'impound' then lots = lots + 1 end
    end
    h.assertTrue(lots >= 1, 'the legacy depot path needs at least one impound garage')

    h.assertFalse(Config.garageTypes.impound.allowStore,
        'storing at a lot would clear an impound without charging for it')
end)

h.test('the store distance is wider than the interaction distance', function()
    -- A player standing at the marker can legitimately have parked a few spaces
    -- away. If these were equal, a busy garage would be unusable.
    h.assertTrue(Config.interaction.storeDistance > Config.interaction.distance,
        'storeDistance must exceed the interaction distance')
end)

h.test('the impound defaults are usable and bounded', function()
    h.assertTrue(Config.impound.defaultFee > 0, 'a zero default makes every impound free by accident')
    h.assertTrue(Config.impound.maxFee >= Config.impound.defaultFee, 'the ceiling must not be below the default')
    h.assertTrue(Config.impound.account == 'bank' or Config.impound.account == 'cash',
        'the fee account must be one qbcore knows')
end)

h.test('the cosmetic mod allow-list excludes every performance mod', function()
    local allowed = {}
    for _, key in ipairs(Config.mods.cosmetic) do allowed[key] = true end

    -- Named individually rather than checked by prefix: these are the six that
    -- would turn a garage into a free tuning shop, and the list is short enough
    -- to be explicit about.
    for _, banned in ipairs({ 'modEngine', 'modBrakes', 'modTransmission', 'modSuspension', 'modArmor', 'modTurbo' }) do
        h.assertFalse(allowed[banned], banned .. ' must never be accepted from a client')
    end

    -- And the server-owned fields, which a mods blob must not be able to carry.
    for _, owned in ipairs({ 'plate', 'model', 'engineHealth', 'bodyHealth', 'fuelLevel' }) do
        h.assertFalse(allowed[owned], owned .. ' is server-owned and must not ride in on a mods blob')
    end
end)

h.report('config')
