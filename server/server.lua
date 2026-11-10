local allVehs = {}
PropertyGarages.entities = allVehs
CreateThread(function()
    -- Legacy housing is optional; kora_housing stores its properties in a different table.
    local exists = Kora.sql.scalar('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { 'houselocations' })
    if not exists or exists == 0 then return end

    local rows = Kora.sql.query('SELECT * FROM houselocations WHERE garage IS NOT NULL')
    if not rows then return end

    for _, row in ipairs(rows) do
        local ok, pos = pcall(json.decode, row.garage)
        if ok and type(pos) == 'table' and pos.x and pos.y and pos.z then
            local point = vector4(pos.x, pos.y, pos.z, pos.w or 0.0)
            Config.garages['house_' .. row.name] = {
                type = 'private',
                label = 'Garage - ' .. row.name,
                coords = point,
                spawn = point,
            }
        end
    end
end)

Kora.callback.register('kora_garages:getGarages', function()
    return Config.garages
end)

Kora.callback.register('kora_garages:houseGarages', function()
    return Config.garages
end)

local function nearGarage(src, garage)
    return Kora.distance.player(src, garage.coords, Config.interaction.distance)
end

local function canUseGarage(src, garage, id, action)
    if garage.property then return PropertyGarages.authorize(src, id, action) end
    if garage.job then
        local job = exports.kora_core:getJob(src)
        if not (job and job.name == garage.job) then return false end
        -- Config.garageTypes.job.requireDuty is also enforced client-side (mayUse), but
        -- that only gates the zone UI; a client calling these callbacks directly must be
        -- checked here too or an off-duty player could use the job garage regardless.
        local policy = Config.garageTypes[garage.type]
        if policy and policy.requireDuty and not job.onduty then return false end
        return true
    end
    if garage.gang then
        local gang = exports.kora_core:getGang(src)
        return gang and gang.name == garage.gang
    end
    return true
end

local function finite(value) return type(value) == 'number' and value == value and math.abs(value) < math.huge end

local function ownsVehicle(src, plate)
    local citizenid = exports.kora_core:getPlayerData(src, { 'citizenid' })
    local vehicle = exports.kora_core:getByPlate(plate)
    if not vehicle then return nil, 'That vehicle does not exist' end
    if vehicle.citizenid ~= citizenid then return nil, 'That is not your vehicle' end
    return vehicle
end

-- Tags the spawned entity with player_vehicles.id (server-only `vehicleid` state
-- bag, read by stock ox_inventory). Older kora_core builds lack the export, so
-- the call is guarded and silently does nothing there.
local function tagVehicle(entity, id)
    pcall(function() return exports.kora_core:tagVehicle(entity, id) end)
end

-- The stored fee, or the default, never above Config.impound.maxFee ("ceiling
-- so a bad impound write can't bankrupt someone").
local function impoundFee(vehicle)
    local fee = tonumber(vehicle.impound_fee) or Config.impound.defaultFee
    local cap = tonumber(Config.impound.maxFee)
    if cap and fee > cap then fee = cap end
    return fee
end

Kora.callback.register('kora_garages:list', function(src, garageId)
    local garage = Config.garages[garageId]
    if not garage then return false, 'Unknown garage' end
    if not nearGarage(src, garage) then return false, 'Too far from the garage' end
    if not canUseGarage(src, garage, garageId, 'list') then return false, 'You cannot use this garage' end

    local citizenid = exports.kora_core:getPlayerData(src, { 'citizenid' })
    local vehicles = exports.kora_core:getByOwner(citizenid) or {}

    local list = {}
    for _, vehicle in ipairs(vehicles) do
        local showsImpounded = garage.type == 'impound'
        local atGarage = garage.property and vehicle.garage_id == garageId or not garage.property and not PropertyGarages.reserved(vehicle)
        if atGarage and (vehicle.state == 'impounded') == showsImpounded then
            list[#list + 1] = {
                plate = vehicle.plate,
                model = vehicle.model,
                state = vehicle.state,
                fee = vehicle.state == 'impounded' and impoundFee(vehicle) or nil,
            }
        end
    end
    return { garage = { id = garageId, label = garage.label, type = garage.type }, vehicles = list }
end)

local vehicleTypes = {
    boats = 'boat',
    helicopters = 'heli',
    planes = 'plane',
    motorcycles = 'bike',
    cycles = 'bike',
}

local function vehicleType(model)
    return vehicleTypes[exports.kora_core:getShared('vehicles', model).category or ''] or 'automobile'
end

local function pickSpawn(garage)
    local vehicles = GetAllVehicles()

    for _, spawn in ipairs(garage.spawns or { garage.spawn }) do
        local free = true
        for _, other in ipairs(vehicles) do
            if Kora.util.vecDistance(GetEntityCoords(other), spawn) < Config.spawn.clearance then
                free = false
                break
            end
        end
        if free then return spawn end
    end
end

local pendingOut = {}

local function discardPending(plate)
    local pending = pendingOut[plate]
    pendingOut[plate] = nil
    if pending and DoesEntityExist(pending.entity) then DeleteEntity(pending.entity) end
end

Kora.callback.register('kora_garages:takeOut', function(src, garageId, plate)
    local garage = Config.garages[garageId]
    if not garage then return false, 'Unknown garage' end
    if not nearGarage(src, garage) then return false, 'Too far from the garage' end
    if not canUseGarage(src, garage, garageId, 'retrieve') then return false, 'You cannot use this garage' end

    local vehicle, err = ownsVehicle(src, plate)
    if not vehicle then return false, err end

    if vehicle.state == 'out' then return false, 'That vehicle is already out' end
    if vehicle.state == 'impounded' and garage.type ~= 'impound' then return false, 'That vehicle is impounded' end

    local spawn = pickSpawn(garage)
    if not spawn then return false, 'There is no free spot to bring that out' end
    if garage.property then return PropertyGarages.takeOut(src, garageId, vehicle, spawn) end
    if PropertyGarages.reserved(vehicle) then return false, 'Use the property garage or its recovery service.' end

    if pendingOut[plate] then return false, 'That vehicle is already being brought out' end

    -- Claim the plate before the yielding spawn wait below: CreateVehicleServerSetter
    -- plus the Wait(10) loop lets a second takeOut call for the same plate run on this
    -- same tick before pendingOut[plate] would otherwise be set, which let a client
    -- fire two takeOut requests back-to-back and get two vehicles out of one stored row.
    local pending = { src = src }
    pendingOut[plate] = pending

    local model = tonumber(vehicle.model) or joaat(tostring(vehicle.model):lower())
    local entity = CreateVehicleServerSetter(model, vehicleType(vehicle.model), spawn.x, spawn.y, spawn.z, spawn.w)

    Kora.loops.controlled(function() return DoesEntityExist(entity) end, false, 3000, 10)
    if not DoesEntityExist(entity) or pending.cancelled then
        if pendingOut[plate] == pending then pendingOut[plate] = nil end
        if DoesEntityExist(entity) then DeleteEntity(entity) end
        return false, 'Could not spawn that vehicle'
    end

    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(entity, plate)

    -- State only becomes 'out' once the client confirms it can see the vehicle.
    -- If it never confirms, the entity is removed and nothing was changed.
    pending.entity = entity
    pending.vehicle = vehicle
    SetTimeout(Config.spawn.timeout + 5000, function()
        if pendingOut[plate] == pending then discardPending(plate) end
    end)

    return { netId = NetworkGetNetworkIdFromEntity(entity), mods = vehicle.mods, timeout = Config.spawn.timeout }
end)

Kora.callback.register('kora_garages:confirmOut', function(src, plate, netId)
    local pending = pendingOut[plate]
    if not pending or pending.src ~= src or not pending.entity then return false, 'That vehicle is no longer being brought out' end
    local entity, vehicle = pending.entity, pending.vehicle
    if not DoesEntityExist(entity) or NetworkGetNetworkIdFromEntity(entity) ~= netId then
        discardPending(plate)
        return false, 'Could not spawn that vehicle'
    end
    pendingOut[plate] = nil

    if vehicle.state == 'impounded' then
        local fee = impoundFee(vehicle)
        local paid = exports.kora_core:removeMoney(src, 'cash', fee, 'impound-fee')
        if not paid then
            DeleteEntity(entity)
            return false, ('You need $%d to release this vehicle'):format(fee)
        end
    end

    local affected = Kora.sql.update('UPDATE player_vehicles SET state = ? WHERE plate = ?', { 'out', plate })
    if affected ~= 1 then
        -- DB write failed: don't hand out keys for a vehicle the DB still thinks is
        -- garaged, or a second takeOut could spawn a dupe of the same stored row.
        DeleteEntity(entity)
        return false, 'Could not spawn that vehicle'
    end
    tagVehicle(entity, vehicle.id)
    exports.kora_vehiclekeys:giveKeys(src, plate)
    allVehs[plate] = entity
    return true
end)

Kora.callback.register('kora_garages:cancelOut', function(src, plate)
    local pending = pendingOut[plate]
    if pending and pending.src == src then
        if pending.entity then discardPending(plate) else pending.cancelled = true end
    end
    return true
end)

local function getVehicleByPlate(plate)
    plate = Kora.vehicle.normalizePlate(plate, { whitespace = 'remove' })
    for _, vehicle in ipairs(GetAllVehicles()) do
        if Kora.vehicle.normalizePlate(GetVehicleNumberPlateText(vehicle), { whitespace = 'remove' }) == plate then
            return vehicle
        end
    end
end

Kora.callback.register('kora_garages:store', function(src, garageId, plate, netId, fuel, mods)
    local garage = Config.garages[garageId]
    if not garage then return false, 'Unknown garage' end
    if not nearGarage(src, garage) then return false, 'Too far from the garage' end
    -- list/takeOut both gate on canUseGarage; store was missing it, letting anyone
    -- store their own vehicle into a job/gang-restricted garage without membership.
    if not canUseGarage(src, garage, garageId, 'store') then return false, 'You cannot use this garage' end

    local vehicle, err = ownsVehicle(src, plate)
    if not vehicle then return false, err end

    if garage.property then return PropertyGarages.store(src, garageId, vehicle, netId, fuel, mods) end
    if PropertyGarages.reserved(vehicle) and vehicle.state == 'out' and garage.type == 'public' and canUseGarage(src, garage, garageId, 'store') then
        return PropertyGarages.store(src, garageId, vehicle, netId, fuel, mods, true)
    end
    if PropertyGarages.reserved(vehicle) then return false, 'Use the property garage or its recovery service.' end

    local entity = NetworkGetEntityFromNetworkId(tonumber(netId))
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        entity = getVehicleByPlate(plate)
        if not entity then return false, 'That vehicle is not here' end
    end

    -- A spoofed netId/plate must not let a client store (and delete) someone else's
    -- entity: verify it's actually a vehicle, actually carries this plate, in the
    -- player's own bucket, near enough, and unoccupied before touching it.
    if GetEntityType(entity) ~= 2 then return false, 'That vehicle is not here' end
    if GetVehicleNumberPlateText(entity):gsub('%s+', ''):upper() ~= plate:gsub('%s+', ''):upper() then
        return false, 'Vehicle plate does not match.'
    end
    if GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(src) then return false, 'Vehicle is in another routing bucket.' end
    if not Kora.distance.player(src, GetEntityCoords(entity), Config.interaction.storeDistance) then return false, 'Vehicle is too far away.' end
    for _, player in ipairs(GetPlayers()) do
        if tonumber(player) ~= src and GetVehiclePedIsIn(GetPlayerPed(player), false) == entity then return false, 'Vehicle is occupied.' end
    end
    if not finite(fuel) or fuel < 0 or fuel > 100 then return false, 'Invalid fuel snapshot.' end
    if mods ~= nil and (type(mods) ~= 'table' or #json.encode(mods) > 131072) then return false, 'Invalid vehicle modifications.' end

    local snapshot = {
        engineHealth = math.floor(GetVehicleEngineHealth(entity)),
        bodyHealth = math.floor(GetVehicleBodyHealth(entity)),
        fuel = math.floor(fuel),
        mods = PropertyGarages.resolveMods(vehicle, type(mods) == 'table' and mods or nil),
    }

    if Config.RecordGarageId and garage.type ~= 'impound' then
        Kora.sql.query('UPDATE player_vehicles SET state = ?, garage_id = ?, mods = ?, engine_health = ?, body_health = ?, fuel = ? WHERE plate = ?', {'garaged', garageId, snapshot.mods, snapshot.engineHealth, snapshot.bodyHealth, snapshot.fuel, plate})
    else
        Kora.sql.query('UPDATE player_vehicles SET state = ?, mods = ?, engine_health = ?, body_health = ?, fuel = ? WHERE plate = ?', {'garaged', snapshot.mods, snapshot.engineHealth, snapshot.bodyHealth, snapshot.fuel, plate})
    end
    DeleteEntity(entity)
    allVehs[plate] = nil
    return true
end)

local function removeVehicles(minutes)
    local function removeAll()
        for plate, entity in pairs(allVehs) do
            if DoesEntityExist(entity) and not isVehicleOccupied(entity) then
                DeleteEntity(entity)
            end

            allVehs[plate] = nil
            Kora.sql.query('UPDATE player_vehicles SET state = ? WHERE plate = ?', { 'garaged', plate})
        end
    end

    if minutes <= 0 then
        removeAll()
        Kora.notify.send(-1, { title = 'ADMIN', message = 'All vehicles have been removed.', type = 'info'})
        return
    end

    Kora.notify.send(-1, { title = 'ADMIN', message = ('All vehicles will be removed in %d minutes.'):format(minutes), type = 'info'})

    CreateThread(function()
        for time = minutes, 1, -1 do
            Wait(60000)

            if time > 1 then
                Kora.notify.send(-1, {
                    title = 'ADMIN',
                    message = ('All vehicles will be removed in %d minutes.'):format(time - 1),
                    type = 'info'
                })
            end
        end
        removeAll()
        Kora.notify.send(-1, { title = 'ADMIN', message = 'All vehicles have been removed.', type = 'info'})
    end)
end

RegisterCommand('garage:storeAll', function(source, args)
    if not IsPlayerAceAllowed(source, 'command') then return end
    removeVehicles(tonumber(args[1]) or 1)
end, false)

-- Vehicles left out by a restart go back to the garage; on a blank database player_vehicles appears after kora_core's schema setup.
CreateThread(function()
    if not Kora.sql.awaitTables({ 'player_vehicles' }, 60000) then return end
    Kora.sql.query('UPDATE player_vehicles SET state = ? WHERE state = ?', {'garaged', 'out'})
end)
