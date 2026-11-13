PropertyGarages = { records = {}, known = {}, ready = false, entities = {} }
local Property = PropertyGarages
local writes = {}

local function finite(value) return type(value) == 'number' and value == value and math.abs(value) < math.huge end
local function point(value)
    return (type(value) == 'table' or type(value) == 'vector3' or type(value) == 'vector4')
        and finite(value.x) and finite(value.y) and finite(value.z) and (value.w == nil or finite(value.w))
end
local function copy(value) return json.decode(json.encode(value)) end
local function position(value) return { x = value.x, y = value.y, z = value.z, w = value.w or 0.0 } end

local function definition(id, value)
    if type(id) ~= 'string' or #id < 1 or #id > 50 or type(value) ~= 'table' then return nil, 'Invalid property garage.' end
    if not point(value.coords) or not finite(value.slots) or value.slots % 1 ~= 0 or value.slots < 1 or value.slots > 1000 then return nil, 'Garage coordinates and capacity are required.' end
    local spawns = value.spawns or { value.spawn }
    if type(spawns) ~= 'table' or #spawns < 1 or #spawns > 100 then return nil, 'Garage needs a vehicle spawn.' end
    local result = { type = 'private', property = true, label = tostring(value.label or id):sub(1, 100),
        coords = position(value.coords), spawns = {}, slots = value.slots, retrievalOnly = value.retrievalOnly == true, noBlip = true }
    for _, spawn in ipairs(spawns) do
        if not point(spawn) then return nil, 'Invalid garage spawn.' end
        result.spawns[#result.spawns + 1] = position(spawn)
    end
    if value.capacityOwnerIds ~= nil then
        if type(value.capacityOwnerIds) ~= 'table' then return nil, 'Invalid capacity owners.' end
        result.capacityOwnerIds = {}
        for _, cid in ipairs(value.capacityOwnerIds) do
            if type(cid) ~= 'string' or #cid < 1 or #cid > 50 then return nil, 'Invalid capacity owner.' end
            result.capacityOwnerIds[#result.capacityOwnerIds + 1] = cid
        end
    end
    return result
end

function Property.authorize(src, id, action)
    local garage, policy = Config.garages[id], Property.records[id]
    if not Property.ready or not garage or garage.disabled or not policy then return false, Kora.lang('Garage.property_access_unavailable') end
    if action == 'store' and garage.retrievalOnly then return false, Kora.lang('Garage.recovery_only') end
    local ok, allowed = pcall(policy.callback, src, action, id)
    if not ok or allowed ~= true then return false, Kora.lang('Garage.cannot_use_property') end
    return true
end

function Property.reserved(vehicle)
    return vehicle.garage_id and (not Property.ready or Property.known[vehicle.garage_id] ~= nil)
end

local function withWrite(id, plate, handler)
    if writes[id] or writes[plate] then return false, Kora.lang('Garage.busy_try_again') end
    writes[id], writes[plate] = true, true
    local result = table.pack(pcall(handler))
    writes[id], writes[plate] = nil, nil
    if not result[1] then return false, Kora.lang('Garage.operation_failed') end
    return table.unpack(result, 2, result.n)
end

local cosmeticKeys
local function isCosmetic(key)
    if not cosmeticKeys then
        cosmeticKeys = {}
        for _, name in ipairs(Config.mods and Config.mods.cosmetic or {}) do cosmeticKeys[name] = true end
    end
    if cosmeticKeys[key] then return true end
    if type(key) == 'string' then
        if key:find('^mod%u') then return true end
        key = tonumber(key)
    end
    return type(key) == 'number' and key >= 0 and key <= 49 and key % 1 == 0
end

local function hasLook(props)
    for key in pairs(props) do
        if isCosmetic(key) then return true end
    end
    return false
end

-- Unless Config.TrustClientCosmetics is on, paid-for look (Config.mods.cosmetic, every
-- `mod*` slot and numeric mod indexes 0-49) comes from the stored row, never the client.
-- A row with no stored look yet (dealership rows have no props) keeps none either, so an
-- unpaid preview can't become its first look, unless Config.SaveUnstoredLook is on.
function Property.resolveMods(vehicle, mods)
    if Config.TrustClientCosmetics then return mods end
    local stored = vehicle and vehicle.mods
    if type(stored) ~= 'table' then stored = {} end
    if Config.SaveUnstoredLook and not hasLook(stored) then return mods end
    if type(mods) ~= 'table' then return next(stored) ~= nil and stored or nil end
    local result = {}
    for key, value in pairs(mods) do
        if not isCosmetic(key) then result[key] = value end
    end
    for key, value in pairs(stored) do
        if isCosmetic(key) then result[key] = value end
    end
    return result
end

function Property.store(src, id, vehicle, netId, fuel, mods, recovered)
    return withWrite(id, vehicle.plate, function()
        local garage = Config.garages[id]
        local allowed, err
        if recovered then
            if not garage or garage.property or garage.type ~= 'public' or vehicle.state ~= 'out' or not Property.reserved(vehicle) then return false, Kora.lang('Garage.property_recovery_unavailable') end
        else
            allowed, err = Property.authorize(src, id, 'store')
            if not allowed then return false, err end
        end
        local entity = tonumber(netId) and NetworkGetEntityFromNetworkId(tonumber(netId))
        if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false, Kora.lang('Garage.vehicle_unavailable') end
        local plate = Kora.vehicle.normalizePlate(GetVehicleNumberPlateText(entity), { whitespace = 'remove' })
        if plate ~= Kora.vehicle.normalizePlate(vehicle.plate, { whitespace = 'remove' }) then return false, Kora.lang('Garage.plate_mismatch') end
        if GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(src) then return false, Kora.lang('Garage.different_bucket') end
        if not Kora.distance.player(src, GetEntityCoords(entity), Config.interaction.storeDistance) then return false, Kora.lang('Garage.vehicle_too_far') end
        if not Kora.distance.player(src, garage.coords, Config.interaction.distance) then return false, Kora.lang('Garage.too_far') end
        if isVehicleOccupied(entity, src) then return false, Kora.lang('Garage.vehicle_occupied') end
        if not finite(fuel) or fuel < 0 or fuel > 100 then return false, Kora.lang('Garage.invalid_fuel') end
        if mods ~= nil and (type(mods) ~= 'table' or #json.encode(mods) > 131072) then return false, Kora.lang('Garage.invalid_modifications') end
        mods = Property.resolveMods(vehicle, mods)
        if not recovered then
            local rows, queryErr = Kora.sql.query('SELECT `citizenid` FROM `player_vehicles` WHERE `garage_id`=? AND `state`=\'garaged\' AND `deleted_at` IS NULL', { id })
            if not rows or queryErr then return false, queryErr or Kora.lang('Garage.garage_storage_unavailable') end
            local count, owners = 0, garage.capacityOwnerIds
            local ownerSet
            if owners then ownerSet = {}; for _, cid in ipairs(owners) do ownerSet[cid] = true end end
            for _, row in ipairs(rows) do if not ownerSet or ownerSet[row.citizenid] then count = count + 1 end end
            if count >= garage.slots then return false, Kora.lang('Garage.property_garage_full') end
            allowed, err = Property.authorize(src, id, 'store')
            if not allowed then return false, err end
        end
        local saved, saveErr = exports.kora_core:storeVehicle(vehicle.plate, {
            garageId = id, fuel = math.floor(fuel), mods = mods,
            ownerCitizenId = vehicle.citizenid,
            engineHealth = math.floor(GetVehicleEngineHealth(entity)), bodyHealth = math.floor(GetVehicleBodyHealth(entity)),
        })
        if not saved then return false, saveErr end
        if DoesEntityExist(entity)
            and Kora.vehicle.normalizePlate(GetVehicleNumberPlateText(entity), { whitespace = 'remove' })
            == Kora.vehicle.normalizePlate(vehicle.plate, { whitespace = 'remove' }) then
            DeleteEntity(entity)
        end
        Property.entities[vehicle.plate] = nil
        return true
    end)
end

function Property.takeOut(src, id, vehicle, spawn)
    return withWrite(id, vehicle.plate, function()
        local allowed, err = Property.authorize(src, id, 'retrieve')
        if not allowed then return false, err end
        if vehicle.garage_id ~= id then return false, Kora.lang('Garage.vehicle_stored_elsewhere') end
        local networkId, spawnErr = exports.kora_core:spawnVehicle(src, vehicle.plate, spawn, spawn.w or 0.0, vehicle.citizenid)
        if not networkId then return false, spawnErr end
        local entity = NetworkGetEntityFromNetworkId(networkId)
        Property.entities[vehicle.plate] = entity
        exports.kora_vehiclekeys:giveKeys(src, vehicle.plate)
        return { netId = networkId, mods = vehicle.mods }
    end)
end

exports('RegisterPropertyGarage', function(id, raw, callback)
    if not Property.ready then return false, Kora.lang('Garage.property_persistence_unavailable') end
    if not Kora.compat.isCallable(callback) then return false, Kora.lang('Garage.garage_policy_callable') end
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if Property.known[id] and Property.known[id] ~= owner then return false, Kora.lang('Garage.garage_owned_elsewhere') end
    if Config.garages[id] and not Property.known[id] then return false, Kora.lang('Garage.garage_id_exists') end
    local garage, err = definition(id, raw)
    if not garage then return false, err end
    return withWrite(id, 'registration:' .. id, function()
        local saved, saveErr
        if Property.known[id] then
            saved, saveErr = Kora.sql.update('UPDATE `kora_garages_property_garages` SET `definition`=? WHERE `id`=? AND `provider`=?', { json.encode(garage), id, owner })
            if saved ~= 1 then return false, saveErr or Kora.lang('Garage.garage_registration_changed') end
        else
            saved, saveErr = Kora.sql.execute('INSERT INTO `kora_garages_property_garages` (`id`,`provider`,`definition`) VALUES (?,?,?)', { id, owner, json.encode(garage) })
            if not saved then return false, saveErr end
        end
        Property.known[id], Property.records[id], Config.garages[id] = owner, { callback = callback, owner = owner }, garage
        TriggerClientEvent('kora_garages:propertyRegistered', -1, id, garage)
        return true
    end)
end)

exports('UnregisterPropertyGarage', function(id)
    if Property.known[id] ~= (GetInvokingResource() or GetCurrentResourceName()) then return false, Kora.lang('Garage.garage_not_owned') end
    Property.records[id] = nil
    if Config.garages[id] then Config.garages[id].disabled = true end
    TriggerClientEvent('kora_garages:propertyRemoved', -1, id)
    return true
end)

AddEventHandler('onResourceStop', function(name)
    for id, owner in pairs(Property.known) do
        if owner == name then
            Property.records[id] = nil
            if Config.garages[id] then Config.garages[id].disabled = true end
            TriggerClientEvent('kora_garages:propertyRemoved', -1, id)
        end
    end
end)

CreateThread(function()
    if not Kora.sql.ready(60000) then return end
    local ensured, schemaErr = Kora.sql.ensureTables(KoraGaragesSchema)
    if not ensured then return print('[kora_garages] Schema setup failed: ' .. tostring(schemaErr)) end
    local rows, err = Kora.sql.query('SELECT `id`,`provider`,`definition` FROM `kora_garages_property_garages`')
    if not rows or err then return end
    for _, row in ipairs(rows) do
        local ok, raw = pcall(json.decode, row.definition)
        local garage = ok and definition(row.id, raw)
        if not garage or Config.garages[row.id] then return print('[kora_garages] Invalid or conflicting property garage: ' .. tostring(row.id)) end
        garage.disabled = true
        Property.known[row.id], Config.garages[row.id] = row.provider, garage
    end
    Property.ready = true
    TriggerEvent('kora_garages:ready')
end)
