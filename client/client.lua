local busy = false
local blips = {}
local markerZones = {}
local markerNear = {}
local markerLoopRunning = false

local function notify(message, kind)
    Kora.notify.send({ title = 'Garage', message = message, type = kind or 'error' })
end

local function toVec3(coords)
    return vector3(coords.x, coords.y, coords.z)
end

local function normalPlate(plate)
    return Kora.vehicle.normalizePlate(plate, { whitespace = 'remove' })
end

local function waitForEntity(netId, timeout)
    return Kora.loops.controlled(function()
        if not NetworkDoesNetworkIdExist(netId) then return false end
        local entity = NetworkGetEntityFromNetworkId(netId)
        return entity ~= 0 and DoesEntityExist(entity) and entity or false
    end, false, timeout or 5000, 50)
end

local toggleFields = { 'modTurbo', 'modSmokeEnabled', 'modXenon', 'modCustomTiresF', 'modCustomTiresR' }
local flagTables = { 'extras', 'tireBurstState', 'tireBurstCompletely', 'windowStatus', 'doorStatus', 'neonEnabled' }

local function asBoolean(value)
    return value == true or value == 1 or value == '1' or value == 'true'
end

local function normalizeMods(mods)
    for _, field in ipairs(toggleFields) do
        if mods[field] ~= nil then mods[field] = asBoolean(mods[field]) end
    end
    for _, field in ipairs(flagTables) do
        if type(mods[field]) == 'table' then
            for key, value in pairs(mods[field]) do mods[field][key] = asBoolean(value) end
        end
    end
end

local function applyMods(entity, mods)
    if not Config.spawn.applyMods then return end
    if type(mods) == 'string' then
        local ok, decoded = pcall(json.decode, mods)
        mods = ok and decoded or nil
    end
    if type(mods) ~= 'table' then return end
    normalizeMods(mods)

    Kora.vehicle.setProperties(entity, mods)
end

local function findVehicle(plate)
    local wanted = normalPlate(plate)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)

    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 and normalPlate(GetVehicleNumberPlateText(current)) == wanted then
        return current
    end

    local nearby = Kora.world.getNearbyEntities('vehicle', pedCoords, Config.interaction.storeDistance, { includeInvisible = true })
    for _, match in ipairs(nearby) do
        if normalPlate(GetVehicleNumberPlateText(match.entity)) == wanted then
            return match.entity
        end
    end
end

local function takeOut(garageId, plate)
    local result, err = Kora.callback.trigger('kora_garages:takeOut', garageId, plate)
    if not result then return notify(err or 'You cannot take that out.') end

    local entity = waitForEntity(result.netId, result.timeout)
    if not entity then
        Kora.callback.trigger('kora_garages:cancelOut', plate)
        return notify('Your vehicle did not spawn, it is still in the garage.')
    end

    local confirmed, confirmErr = Kora.callback.trigger('kora_garages:confirmOut', plate, result.netId)
    if not confirmed then return notify(confirmErr or 'Your vehicle did not spawn.') end

    applyMods(entity, result.mods)
    if Config.spawn.warpIntoVehicle then SetPedIntoVehicle(PlayerPedId(), entity, -1) end

    notify(('%s is ready.'):format(plate), 'success')
end

local function store(garageId, plate)
    local entity = findVehicle(plate)
    if not entity then return notify('That vehicle is not here.') end

    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == entity then
        TaskLeaveVehicle(ped, entity, 0)
        Kora.loops.controlled(function() return GetVehiclePedIsIn(ped, false) ~= entity end, false, 3000, 100)
    end

    -- mods live behind client-only natives; the server treats them as untrusted
    local stored, err = Kora.callback.trigger('kora_garages:store', garageId, plate, NetworkGetNetworkIdFromEntity(entity), GetVehicleFuelLevel(entity), Kora.vehicle.getProperties(entity))
    if not stored then return notify(err or 'You cannot store that here.') end

    notify(('%s is parked.'):format(plate), 'success')
end

local function describe(vehicle, policy)
    if vehicle.state == 'impounded' then
        local fee = tonumber(vehicle.fee) or Config.impound.defaultFee
        return 'Impounded', ('Pay $%d & release'):format(fee), 'lock'
    end
    if vehicle.state == 'out' then
        return 'Out on the street', policy.allowStore ~= false and 'Store' or nil, 'car-front'
    end
    return 'In the garage', 'Take out', 'car-front'
end

local function getModelName(model)
    local veh = exports.kora_core:getShared('vehicles', model)
    return veh and veh.name or 'Unknown Vehicle'
end

local function openGarage(garageId)
    if busy then return end

    CreateThread(function()
        local payload, err = Kora.callback.trigger('kora_garages:list', garageId)
        if not payload then return notify(err or 'You cannot use this garage.') end

        local garage = payload.garage
        local policy = Config.garageTypes[garage.type] or {}
        local impound = policy.shows == 'impounded'
        local items, usable = {}, {}

        for _, vehicle in ipairs(payload.vehicles or {}) do
            local status, badge, icon = describe(vehicle, policy)
            if badge then usable[vehicle.plate] = vehicle end
            items[#items + 1] = {
                id = vehicle.plate,
                label = getModelName(vehicle.model),
                description = ('%s · %s'):format(vehicle.plate, status),
                image = 'https://docs-backend.fivem.net/vehicles/' .. vehicle.model .. '.webp',
                icon = icon,
                badge = badge,
                action = badge and 'garage:use' or nil,
            }
        end

        Kora.nui.registerApp({
            id = 'kora_garages:garage',
            title = garage.label,
            description = policy.label or 'Garage',
            icon = impound and 'lock' or 'warehouse',
            accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
            layout = 'standard',
            width = 1200, height = 850,
            navigation = {
                { id = 'vehicles', label = 'Vehicles', icon = 'car-front', badge = #items,
                    content = {
                        title = garage.label,
                        description = 'Select a vehicle.',
                        blocks = {
                            { type = 'list', id = 'garage-vehicles', title = 'Your vehicles', layout = 'cards', cardStyle = 'media', columns = 3,
                                searchable = true, pageSize = 9, items = items,
                                empty = impound and 'Nothing of yours is being held here.' or 'You have no vehicles at this garage.' },
                        },
                    },
                },
            },
            onAction = function(actionId, context)
                local plate = context and context.itemId
                local vehicle = type(plate) == 'string' and usable[plate] or nil
                if actionId ~= 'garage:use' or not vehicle or busy then return {} end
                busy = true
                Kora.nui.closeApp('kora_garages:garage')

                CreateThread(function()
                    local ok = pcall(function()
                        if vehicle.state == 'out' then store(garageId, plate) else takeOut(garageId, plate) end
                    end)
                    busy = false
                    if not ok then notify('Something went wrong.') end
                end)

                return {}
            end,
        })
        Kora.nui.openApp('kora_garages:garage')
    end)
end

local function mayUse(garage)
    local policy = Config.garageTypes[garage.type]
    if not policy then return false end

    if garage.job then
        local job = exports.kora_core:getJob()
        if type(job) ~= 'table' or job.name ~= garage.job then return false end
        if policy.requireDuty and not job.onduty then return false end
        return true
    end

    if garage.gang then
        local gang = exports.kora_core:getGang()
        return type(gang) == 'table' and gang.name == garage.gang
    end

    return true
end

local function markerLoop()
    if markerLoopRunning then return end
    markerLoopRunning = true

    CreateThread(function()
        local cfg = Config.markers
        local size, color = cfg.size, cfg.color
        while next(markerNear) do
            for _, coords in pairs(markerNear) do
                DrawMarker(cfg.type, coords.x, coords.y, coords.z + cfg.zOffset, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    size.x, size.y, size.z, color.r, color.g, color.b, color.a,
                    cfg.bobUpAndDown == true, false, 2, cfg.rotate == true, nil, nil, false)
            end
            Wait(0)
        end
        markerLoopRunning = false
    end)
end

local function removeMarkerZone(id)
    local zone = markerZones[id]
    if not zone then return end
    markerZones[id] = nil
    markerNear[id] = nil
    zone.remove()
end

local function addMarkerZone(id, garage)
    local cfg = Config.markers
    if not cfg or cfg.enabled ~= true then return end
    if garage.disabled or garage.noMarker or not Config.garageTypes[garage.type] then return end
    if garage.property and not cfg.houseGarages then return end

    removeMarkerZone(id)
    markerZones[id] = Kora.zones.sphere({
        coords = toVec3(garage.coords),
        radius = cfg.drawDistance,
        onEnter = function()
            if not mayUse(garage) then return end
            markerNear[id] = toVec3(garage.coords)
            markerLoop()
        end,
        onExit = function() markerNear[id] = nil end,
    })
end

local function addZone(id, garage)
    if garage.disabled then return end
    local policy = Config.garageTypes[garage.type]
    if not policy then return end
    local impound = policy.shows == 'impounded'

    Kora.interact.addBoxZone(('kora_garages:%s'):format(id), toVec3(garage.coords), toVec3(garage.size or Config.interaction.zoneSize), {
        {
            label = (impound and 'Collect from %s' or 'Open %s'):format(garage.label),
            icon = impound and 'car-front' or 'warehouse',
            canInteract = function() return mayUse(garage) end,
            action = function() openGarage(id) end,
        },
    }, Config.debug)
    addMarkerZone(id, garage)
end

exports('openGarage', function(id)
    if not Config.garages[id] or Config.garages[id].disabled then return false, 'Garage is unavailable.' end
    openGarage(id)
    return true
end)

for id, garage in pairs(Config.garages) do addZone(id, garage) end

CreateThread(function()
    local extra = Kora.callback.trigger('kora_garages:houseGarages')
    if type(extra) ~= 'table' then return end

    for id, garage in pairs(extra) do
        if not Config.garages[id] then
            Config.garages[id] = garage
            addZone(id, garage)
        end
    end
end)

local function createBlips()
    for _, blip in ipairs(blips) do Kora.blips.remove(blip) end
    blips = {}

    for id, garage in pairs(Config.garages) do
        local policy = Config.garageTypes[garage.type]
        local isHouse = tostring(id):find('^house_') ~= nil

        if policy and not garage.noBlip and (Config.houseGarages.blip or not isHouse) then
            local blip = Kora.blips.create(garage.coords, {
                sprite = policy.blipSprite,
                color = policy.blipColor,
                scale = 0.8,
                shortRange = true,
                category = policy.blipLabel,
                name = garage.label,
            })
            if blip then blips[#blips + 1] = blip end
        end
    end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', createBlips)
AddEventHandler('kora_core:client:playerLoaded', createBlips)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then createBlips() end
end)

RegisterNetEvent('kora_garages:propertyRegistered', function(id, garage)
    if type(id) ~= 'string' or type(garage) ~= 'table' or garage.property ~= true then return end
    Kora.interact.removeZone(('kora_garages:%s'):format(id))
    removeMarkerZone(id)
    Config.garages[id] = garage
    addZone(id, garage)
end)

RegisterNetEvent('kora_garages:propertyRemoved', function(id)
    if type(id) ~= 'string' or not Config.garages[id] or not Config.garages[id].property then return end
    Kora.interact.removeZone(('kora_garages:%s'):format(id))
    removeMarkerZone(id)
    Config.garages[id].disabled = true
end)
