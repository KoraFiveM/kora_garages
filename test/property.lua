local H = dofile('../kora_core/test/harness.lua')
local jsonTools = dofile('../kora_core/test/mocks.lua')
local json = { encode = jsonTools.stableEncode, decode = jsonTools.simpleDecode }
local function copy(value) return json.decode(json.encode(value)) end

-- Only substitutes FiveM vector arithmetic used by the existing garage radius check.
local vectorMeta = {}
vectorMeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta) end
vectorMeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vector(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, vectorMeta) end

local function setup(stored, opts)
    local f = { provided = {}, callbacks = {}, events = {}, threads = {}, caller = 'housing', allowed = true,
        vehicle = { id = 7, plate = 'ABC123', citizenid = 'CID1', state = 'out', model = 'car', fuel = 50, engine_health = 900, body_health = 900 },
        rows = {}, timeouts = {}, bag = {}, noTagExport = opts and opts.noTagExport, convar = 1, deleted = 0, plate = 'ABC123', entityBucket = 0, exists = true, writes = 0 }
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    env.Core, env.PropertyGarages, env.json = { garage = {} }, nil, json
    env.Config = { garages = { public = { coords = vector(0, 0, 0), spawn = vector(0, 0, 0, 0), type = 'public', label = 'Public' } },
        interaction = { distance = 4, storeDistance = 12 }, spawn = { clearance = 2, timeout = 10000 }, garage = { spawnNetworkIdTimeout = 1000 } }
    env.GetCurrentResourceName = function() return 'kora_garages' end
    env.GetInvokingResource = function() return f.caller end
    env.vector3, env.vector4 = vector, vector
    env.GetPlayerPed = function(src) return tonumber(src) end
    env.GetEntityCoords = function() return vector(0, 0, 0) end
    env.GetPlayerRoutingBucket = function() return 0 end
    env.GetEntityRoutingBucket = function() return f.entityBucket end
    env.GetPlayers, env.GetAllVehicles = function() return {} end, function() return {} end
    env.GetVehiclePedIsIn = function() return 0 end
    env.NetworkGetEntityFromNetworkId = function(id) return id == 99 and 99 or 0 end
    env.NetworkGetNetworkIdFromEntity = function(id) return id end
    env.DoesEntityExist = function(entity) return entity == 99 and f.exists end
    env.GetEntityType = function() return 2 end
    env.GetVehicleNumberPlateText = function() return f.plate end
    env.GetVehicleEngineHealth, env.GetVehicleBodyHealth = function() return 900 end, function() return 900 end
    env.DeleteEntity = function() f.deleted = f.deleted + 1 end
    env.CreateVehicle, env.CreateVehicleServerSetter = function() return 99 end, function() return 99 end
    env.SetEntityRoutingBucket, env.SetVehicleNumberPlateText, env.SetVehicleBodyHealth = function() end, function() end, function() end
    env.GetGameTimer = function() return f.clock or 0 end
    env.Wait = function() f.clock = (f.clock or 0) + 1000 end
    env.GetConvarInt = function(name, default) if name == 'kora:vehicleIdStateBag' then return f.convar end return default end
    env.Entity = function(e)
        return { state = { set = function(_, key, value, replicated)
            f.bag[#f.bag + 1] = { entity = e, key = key, value = value, replicated = replicated }
        end } }
    end
    env.joaat = function() return 123 end
    env.SetTimeout = function(_, fn) f.timeouts[#f.timeouts + 1] = fn end
    env.CreateThread = function(fn) f.threads[#f.threads + 1] = fn end
    env.AddEventHandler = function(name, fn) f.events[name] = fn end
    env.RegisterCommand, env.TriggerClientEvent, env.TriggerEvent = function() end, function() end, function() end
    env.Kora = { compat = { isCallable = function(value) return type(value) == 'function' end },
        distance = { player = function() return not f.tooFar end },
        callback = { register = function(name, fn) f.callbacks[name] = fn end }, sql = { NULL = 'NULL' } }
    local sql = env.Kora.sql
    sql.ready, sql.ensureTables, sql.awaitTables = function() return true end, function() return {} end, function() return true end
    sql.single = function() return copy(f.vehicle) end
    sql.query = function(statement)
        if statement:find('kora_garages_property_garages', 1, true) then return stored or {} end
        if statement:find('SELECT `citizenid`', 1, true) then if f.beforeCapacity then f.beforeCapacity() end; return f.rows end
        return {}
    end
    sql.execute = function(statement, params)
        if f.failSave then return nil, 'controlled SQL failure' end
        f.saved = params and { id = params[1], provider = params[2], definition = params[3] }
        return { affectedRows = 1 }
    end
    sql.update = function(statement, params)
        if statement:find('kora_garages_property_garages', 1, true) then
            if f.failSave then return nil, 'controlled SQL failure' end
            f.saved = { id = params[2], provider = params[3], definition = params[1] }
            return 1
        end
        f.writes = f.writes + 1
        if f.failSave then return nil, 'controlled SQL failure' end
        if statement:find('`garage_id`', 1, true) then
            H.assertTrue(statement:find("AND `state`='out'", 1, true), 'store must compare vehicle state')
            if f.vehicle.state ~= 'out' then return 0 end
            f.vehicle.state, f.vehicle.garage_id = 'garaged', params[1]
        else
            if f.vehicle.state ~= 'garaged' then return 0 end
            f.vehicle.state = 'out'
        end
        return 1
    end
    assert(loadfile('../kora_core/modules/garage/server.lua', 't', env))()
    env.exports = setmetatable({ kora_core = {
        getPlayerData = function(_, _, path) return path and 'CID1' or { citizenid = 'CID1' } end,
        getByPlate = function() return copy(f.vehicle) end,
        getByOwner = function() return { copy(f.vehicle) } end,
        getShared = function() return {} end,
        storeVehicle = function(_, ...) return env.Core.garage.storeVehicle(...) end,
        spawnVehicle = function(_, ...) return env.Core.garage.spawnVehicle(...) end,
        tagVehicle = (not f.noTagExport) and function(_, ...) return env.Core.garage.tagVehicle(...) end or nil,
    }, kora_vehiclekeys = { giveKeys = function() end } }, { __call = function(_, name, fn) f.provided[name] = fn end })
    assert(loadfile('server/schema.lua', 't', env))()
    assert(loadfile('server/property.lua', 't', env))()
    assert(loadfile('server/server.lua', 't', env))()
    f.threads[1]()
    f.env, f.property = env, env.PropertyGarages
    function f.register(options)
        return f.provided.RegisterPropertyGarage('home', options or { coords = { x = 0, y = 0, z = 0 }, spawn = { x = 0, y = 0, z = 0 }, slots = 1 },
            function(_, action) return f.allowed and not (action == 'store' and f.noStore) end)
    end
    function f.takeOutPublic(plate)
        local result = f.call('takeOut', 'public', plate)
        if not result then return result end
        return f.call('confirmOut', plate, result.netId)
    end
    function f.call(name, ...) return f.callbacks['qbgarages:' .. name](1, ...) end
    return f
end

H.test('schema declares the property garages table keyed by id', function()
    local f = setup()
    local spec = f.env.QBGaragesSchema[1]
    H.assertEqual(spec.name, 'kora_garages_property_garages')
    H.assertEqual(spec.primary[1], 'id')
end)

H.test('all property garage actions require the live provider policy', function()
    local f = setup(); assert(f.register())
    f.allowed = false
    H.assertEqual(f.call('list', 'home'), false)
    H.assertEqual(f.call('store', 'home', 'ABC123', 99, 50, {}), false)
    f.vehicle.state, f.vehicle.garage_id = 'garaged', 'home'
    H.assertEqual(f.call('takeOut', 'home', 'ABC123'), false)
    H.assertEqual(f.writes, 0); H.assertEqual(f.deleted, 0)
    f.allowed = true
    f.events.onResourceStop('housing')
    H.assertEqual(f.call('list', 'home'), false)
end)

H.test('storage validates entity plate bucket capacity and confirmed persistence before deletion', function()
    local f = setup(); assert(f.register())
    f.plate = 'OTHER'
    H.assertEqual(f.call('store', 'home', 'ABC123', 99, 50, {}), false)
    f.plate, f.entityBucket = 'ABC123', 5
    H.assertEqual(f.call('store', 'home', 'ABC123', 99, 50, {}), false)
    f.entityBucket, f.rows = 0, { { citizenid = 'CID1' } }
    H.assertEqual(f.call('store', 'home', 'ABC123', 99, 50, {}), false)
    f.rows, f.failSave = {}, true
    H.assertEqual(f.call('store', 'home', 'ABC123', 99, 50, {}), false)
    H.assertEqual(f.deleted, 0)
    f.failSave = false
    H.assertTrue(f.call('store', 'home', 'ABC123', 99, 50, {}))
    H.assertEqual(f.vehicle.garage_id, 'home'); H.assertEqual(f.vehicle.state, 'garaged'); H.assertEqual(f.deleted, 1)
end)

H.test('protected vehicles cannot bypass housing through a public garage', function()
    local f = setup(); assert(f.register())
    f.vehicle.state, f.vehicle.garage_id = 'garaged', 'home'
    H.assertEqual(#f.call('list', 'public').vehicles, 0)
    H.assertEqual(f.call('takeOut', 'public', 'ABC123'), false)
    H.assertTrue(f.call('takeOut', 'home', 'ABC123'))
    H.assertEqual(f.vehicle.state, 'out')
    H.assertEqual(f.call('takeOut', 'home', 'ABC123'), false)
end)

H.test('persisted garage mappings deny access before rebind and cannot be stolen', function()
    local f = setup(); assert(f.register())
    local restarted = setup({ f.saved })
    H.assertEqual(restarted.call('list', 'home'), false)
    restarted.caller = 'other'
    H.assertEqual(restarted.register(), false)
    restarted.caller = 'housing'
    H.assertTrue(restarted.register())
    H.assertTrue(restarted.call('list', 'home'))
end)

H.test('capacity ignores former occupants only when configured by the owning provider', function()
    local f = setup()
    assert(f.register({ coords = { x = 0, y = 0, z = 0 }, spawn = { x = 0, y = 0, z = 0 }, slots = 1, capacityOwnerIds = { 'CID1' } }))
    f.rows = { { citizenid = 'FORMER' } }
    H.assertTrue(f.call('store', 'home', 'ABC123', 99, 50, {}))
end)

H.test('a recovered owned vehicle can move into public storage after property access ends', function()
    local f = setup(); assert(f.register())
    f.vehicle.state, f.vehicle.garage_id = 'garaged', 'home'
    assert(f.call('takeOut', 'home', 'ABC123'))
    f.allowed, f.failSave = false, true
    H.assertEqual(f.call('store', 'public', 'ABC123', 99, 50, {}), false)
    H.assertEqual(f.deleted, 0)
    f.failSave = false
    H.assertTrue(f.call('store', 'public', 'ABC123', 99, 50, {}))
    H.assertEqual(f.vehicle.garage_id, 'public'); H.assertEqual(f.deleted, 1)
    H.assertEqual(#f.call('list', 'public').vehicles, 1)
    H.assertTrue(f.call('takeOut', 'public', 'ABC123'))
end)

H.test('storage serializes concurrent requests and rechecks policy after a yielding query', function()
    local f = setup(); assert(f.register())
    f.beforeCapacity = function() coroutine.yield('capacity wait') end
    local thread = coroutine.create(function() return f.call('store', 'home', 'ABC123', 99, 50, {}) end)
    assert(coroutine.resume(thread))
    H.assertEqual(f.call('store', 'home', 'ABC123', 99, 50, {}), false)
    f.allowed = false
    local resumed, result = coroutine.resume(thread); assert(resumed, result)
    H.assertEqual(result, false); H.assertEqual(f.deleted, 0); H.assertEqual(f.writes, 0)
end)

H.test('core checks current vehicle ownership before persisting a stale housing snapshot', function()
    local f = setup(); assert(f.register())
    f.beforeCapacity = function() f.vehicle.citizenid = 'SECOND' end
    H.assertEqual(f.call('store', 'home', 'ABC123', 99, 50, {}), false)
    H.assertEqual(f.deleted, 0); H.assertEqual(f.writes, 0)
end)

H.test('public take-out tags the entity with the non-replicated vehicleid state bag', function()
    local f = setup()
    f.vehicle.state = 'garaged'
    H.assertTrue(f.takeOutPublic('ABC123'))
    H.assertEqual(#f.bag, 1)
    H.assertEqual(f.bag[1].entity, 99); H.assertEqual(f.bag[1].key, 'vehicleid'); H.assertEqual(f.bag[1].value, 7)
    H.assertTrue(f.bag[1].replicated == false, 'bag must be server-only')
end)

H.test('public take-out stays garaged until the client confirms, and cancel or timeout removes the entity', function()
    local f = setup()
    f.vehicle.state = 'garaged'
    H.assertTrue(f.call('takeOut', 'public', 'ABC123'))
    H.assertEqual(f.vehicle.state, 'garaged')
    H.assertEqual(f.call('takeOut', 'public', 'ABC123'), false)
    f.call('cancelOut', 'ABC123')
    H.assertEqual(f.deleted, 1); H.assertEqual(f.vehicle.state, 'garaged')
    H.assertEqual(f.call('confirmOut', 'ABC123', 99), false)
    H.assertTrue(f.call('takeOut', 'public', 'ABC123'))
    f.timeouts[#f.timeouts]()
    H.assertEqual(f.deleted, 2); H.assertEqual(f.call('confirmOut', 'ABC123', 99), false)
end)

H.test('property take-out is tagged through the kora_core spawn path', function()
    local f = setup(); assert(f.register())
    f.vehicle.state, f.vehicle.garage_id = 'garaged', 'home'
    H.assertTrue(f.call('takeOut', 'home', 'ABC123'))
    H.assertEqual(#f.bag, 1); H.assertEqual(f.bag[1].value, 7); H.assertTrue(f.bag[1].replicated == false)
end)

H.test('vehicleid state bag respects the convar and is skipped on spawn or DB failure', function()
    local f = setup()
    f.vehicle.state, f.convar = 'garaged', 0
    H.assertTrue(f.takeOutPublic('ABC123'))
    H.assertEqual(#f.bag, 0)
    local g = setup()
    g.vehicle.state, g.exists = 'garaged', false
    H.assertEqual(g.call('takeOut', 'public', 'ABC123'), false)
    local h = setup()
    h.vehicle.state, h.failSave = 'garaged', true
    h.takeOutPublic('ABC123')
    H.assertEqual(#g.bag + #h.bag, 0)
end)

H.test('take-out still works when the kora_core tagVehicle export is missing', function()
    local f = setup(nil, { noTagExport = true })
    f.vehicle.state = 'garaged'
    H.assertTrue(f.takeOutPublic('ABC123'))
    H.assertEqual(f.vehicle.state, 'out'); H.assertEqual(#f.bag, 0)
end)

H.test('storing keeps the stored cosmetics unless the client is trusted', function()
    local f = setup()
    local resolve, config = f.property.resolveMods, f.env.Config
    config.mods = { cosmetic = { 'color1', 'windowTint', 'neonColor', 'extras', 'wheelType' } }
    local row = { mods = { color1 = 1, windowTint = 0, modSpoilers = 2, [23] = 4, extras = { ["1"] = true }, fuelLevel = 50 } }
    local client = { color1 = 99, windowTint = 3, modSpoilers = 7, [23] = 9, neonColor = { 255, 0, 0 }, extras = { ["1"] = false },
        modTurbo = true, fuelLevel = 20, dirtLevel = 4.0, engineHealth = 800 }
    local out = resolve(row, client)
    H.assertEqual(out.color1, 1); H.assertEqual(out.windowTint, 0); H.assertEqual(out.modSpoilers, 2)
    H.assertEqual(out[23], 4); H.assertEqual(out.extras["1"], true)
    H.assertEqual(out.neonColor, nil); H.assertEqual(out.modTurbo, nil)
    H.assertEqual(out.fuelLevel, 20); H.assertEqual(out.dirtLevel, 4.0); H.assertEqual(out.engineHealth, 800)
    H.assertEqual(resolve(row, nil), row.mods)
    -- no stored look yet (a dealership row): an unpaid preview must not become its first look
    for _, fresh in ipairs({ {}, { mods = {} }, { mods = { fuelLevel = 50, dirtLevel = 1.0 } } }) do
        local first = resolve(fresh, client)
        H.assertEqual(first.color1, nil); H.assertEqual(first.windowTint, nil); H.assertEqual(first.modSpoilers, nil)
        H.assertEqual(first[23], nil); H.assertEqual(first.neonColor, nil); H.assertEqual(first.extras, nil)
        H.assertEqual(first.fuelLevel, 20); H.assertEqual(first.dirtLevel, 4.0)
    end
    H.assertEqual(resolve({ mods = {} }, nil), nil)
    config.SaveUnstoredLook = true
    H.assertEqual(resolve({}, client), client); H.assertEqual(resolve({ mods = { fuelLevel = 50 } }, client), client)
    H.assertEqual(resolve(row, client).color1, 1)
    config.SaveUnstoredLook = nil
    config.TrustClientCosmetics = true
    H.assertEqual(resolve(row, client), client)
end)

H.report('qbgarages property integration')
