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

Kora.callback.register('qbgarages:getGarages', function()
    return Config.garages
end)

Kora.callback.register('qbgarages:houseGarages', function()
    return Config.garages
end)

local function nearGarage(src, garage)
    local ped = GetPlayerPed(src)
    local pos = GetEntityCoords(ped)
    return #(pos - vector3(garage.coords.x, garage.coords.y, garage.coords.z)) <= Config.interaction.distance
end

local function canUseGarage(src, garage, id, action)
    if garage.property then return PropertyGarages.authorize(src, id, action) end
    if garage.job then
        local job = exports.kora_core:getJob(src)
        return job and job.name == garage.job
    end
    if garage.gang then
        local gang = exports.kora_core:getGang(src)
        return gang and gang.name == garage.gang
    end
    return true
end

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

Kora.callback.register('qbgarages:list', function(src, garageId)
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
                fee = vehicle.state == 'impounded' and (tonumber(vehicle.impound_fee) or Config.impound.fee) or nil,
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
            if #(GetEntityCoords(other) - vector3(spawn.x, spawn.y, spawn.z)) < Config.spawn.clearance then
                free = false
                break
            end
        end
        if free then return spawn end
    end
end

Kora.callback.register('qbgarages:takeOut', function(src, garageId, plate)
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

    local model = tonumber(vehicle.model) or joaat(tostring(vehicle.model):lower())
    local entity = CreateVehicleServerSetter(model, vehicleType(vehicle.model), spawn.x, spawn.y, spawn.z, spawn.w)

    local deadline = GetGameTimer() + 3000
    while not DoesEntityExist(entity) and GetGameTimer() < deadline do Wait(10) end
    if not DoesEntityExist(entity) then return false, 'Could not spawn that vehicle' end

    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(entity, plate)

    if vehicle.state == 'impounded' then
        local fee = tonumber(vehicle.impound_fee) or Config.impound.defaultFee
        local paid = exports.kora_core:removeMoney(src, 'cash', fee, 'impound-fee')
        if not paid then
            DeleteEntity(entity)
            return false, ('You need $%d to release this vehicle'):format(fee)
        end
    end

    local affected = Kora.sql.update('UPDATE player_vehicles SET state = ? WHERE plate = ?', { 'out', plate })
    if affected == 1 then tagVehicle(entity, vehicle.id) end
    exports.kora_vehiclekeys:giveKeys(src, plate)
    allVehs[plate] = entity
    return { netId = NetworkGetNetworkIdFromEntity(entity), mods = vehicle.mods }
end)

local function getVehicleByPlate(plate)
    plate = plate:gsub('%s+', ''):upper()
    for _, vehicle in ipairs(GetAllVehicles()) do
        if GetVehicleNumberPlateText(vehicle):gsub('%s+', ''):upper() == plate then
            return vehicle
        end
    end
end

Kora.callback.register('qbgarages:store', function(src, garageId, plate, netId, fuel, mods)
    local garage = Config.garages[garageId]
    if not garage then return false, 'Unknown garage' end
    if not nearGarage(src, garage) then return false, 'Too far from the garage' end

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
    local snapshot = {
        engineHealth = math.floor(GetVehicleEngineHealth(entity)),
        bodyHealth = math.floor(GetVehicleBodyHealth(entity)),
        fuel = math.floor(fuel),
        mods = PropertyGarages.resolveMods(vehicle, type(mods) == 'table' and mods or nil),
    }

    Kora.sql.query('UPDATE player_vehicles SET state = ?, mods = ?, engine_health = ?, body_health = ?, fuel = ? WHERE plate = ?', {'garaged', snapshot.mods, snapshot.engineHealth, snapshot.bodyHealth, snapshot.fuel, plate})
    DeleteEntity(entity)
    allVehs[plate] = nil
    return true
end)

local function isVehicleOccupied(vehicle)
    for _, player in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(player)
        if GetVehiclePedIsIn(ped, false) == vehicle then
            return true
        end
    end

    return false
end

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

Kora.sql.query('UPDATE player_vehicles SET state = ? WHERE state = ?', {'garaged', 'out'})
