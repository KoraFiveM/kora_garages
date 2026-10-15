local H = dofile('../qbcore/test/harness.lua')
local jsonTools = dofile('../qbcore/test/mocks.lua')
local json = { encode = jsonTools.stableEncode, decode = jsonTools.simpleDecode }
local function copy(value) return json.decode(json.encode(value)) end

-- Only substitutes FiveM vector arithmetic used by the existing garage radius check.
local vectorMeta = {}
vectorMeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta) end
vectorMeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vector(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, vectorMeta) end

local function setup(stored)
    local f = { provided = {}, callbacks = {}, events = {}, threads = {}, caller = 'housing', allowed = true,
        vehicle = { plate = 'ABC123', citizenid = 'CID1', state = 'out', model = 'car', fuel = 50, engine_health = 900, body_health = 900 },
        rows = {}, deleted = 0, plate = 'ABC123', entityBucket = 0, exists = true, writes = 0 }
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    env.Core, env.PropertyGarages, env.json = { garage = {} }, nil, json
    env.Config = { garages = { public = { coords = vector(0, 0, 0), spawn = vector(0, 0, 0, 0), type = 'public', label = 'Public' } },
        interaction = { distance = 4, storeDistance = 12 }, spawn = { clearance = 2 }, garage = { spawnNetworkIdTimeout = 1000 } }
    env.GetCurrentResourceName = function() return 'qbgarages' end
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
    env.GetGameTimer = function() return 0 end
    env.joaat = function() return 123 end
    env.CreateThread = function(fn) f.threads[#f.threads + 1] = fn end
    env.AddEventHandler = function(name, fn) f.events[name] = fn end
    env.RegisterCommand, env.TriggerClientEvent, env.TriggerEvent = function() end, function() end, function() end
    env.QB = { compat = { isCallable = function(value) return type(value) == 'function' end },
        distance = { player = function() return not f.tooFar end },
        callback = { register = function(name, fn) f.callbacks[name] = fn end }, sql = { NULL = 'NULL' } }
    local sql = env.QB.sql
    sql.ready, sql.migrateFiles = function() return true end, function() return true end
    sql.single = function() return copy(f.vehicle) end
    sql.query = function(statement)
        if statement:find('qbgarages_property_garages', 1, true) then return stored or {} end
        if statement:find('SELECT `citizenid`', 1, true) then if f.beforeCapacity then f.beforeCapacity() end; return f.rows end
        return {}
    end
    sql.execute = function(statement, params)
        if f.failSave then return nil, 'controlled SQL failure' end
        f.saved = params and { id = params[1], provider = params[2], definition = params[3] }
        return { affectedRows = 1 }
    end
    sql.update = function(statement, params)
        if statement:find('qbgarages_property_garages', 1, true) then
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
    assert(loadfile('../qbcore/modules/garage/server.lua', 't', env))()
    env.exports = setmetatable({ qbcore = {
        getPlayerData = function(_, _, path) return path and 'CID1' or { citizenid = 'CID1' } end,
        getByPlate = function() return copy(f.vehicle) end,
        getByOwner = function() return { copy(f.vehicle) } end,
        getShared = function() return {} end,
        storeVehicle = function(_, ...) return env.Core.garage.storeVehicle(...) end,
        spawnVehicle = function(_, ...) return env.Core.garage.spawnVehicle(...) end,
    }, qbvehiclekeys = { giveKeys = function() end } }, { __call = function(_, name, fn) f.provided[name] = fn end })
    assert(loadfile('server/property.lua', 't', env))()
    assert(loadfile('server/server.lua', 't', env))()
    f.threads[1]()
    f.env, f.property = env, env.PropertyGarages
    function f.register(options)
        return f.provided.RegisterPropertyGarage('home', options or { coords = { x = 0, y = 0, z = 0 }, spawn = { x = 0, y = 0, z = 0 }, slots = 1 },
            function(_, action) return f.allowed and not (action == 'store' and f.noStore) end)
    end
    function f.call(name, ...) return f.callbacks['qbgarages:' .. name](1, ...) end
    return f
end

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

H.report('qbgarages property integration')
