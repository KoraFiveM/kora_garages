local busy = false
local blips = {}

local function notify(message, kind)
    QB.notify.send({ title = 'Garage', message = message, type = kind or 'error' })
end

local function toVec3(coords)
    return vector3(coords.x, coords.y, coords.z)
end

local function normalPlate(plate)
    return (tostring(plate):gsub('%s+', ''):upper())
end

-- --- vehicles -----------------------------------------------------------------

local function waitForEntity(netId)
    local deadline = GetGameTimer() + 5000
    while GetGameTimer() < deadline do
        if NetworkDoesNetworkIdExist(netId) then
            local entity = NetworkGetEntityFromNetworkId(netId)
            if entity ~= 0 and DoesEntityExist(entity) then return entity end
        end
        Wait(50)
    end
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

    local deadline = GetGameTimer() + 2000
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(entity)
        Wait(50)
    end

    QB.vehicle.setProperties(entity, mods)
end

local function findVehicle(plate)
    local wanted = normalPlate(plate)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)

    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 and normalPlate(GetVehicleNumberPlateText(current)) == wanted then
        return current
    end

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(vehicle) - pedCoords) <= Config.interaction.storeDistance
            and normalPlate(GetVehicleNumberPlateText(vehicle)) == wanted then
            return vehicle
        end
    end
end

local function takeOut(garageId, plate)
    local result, err = QB.callback.trigger('qbgarages:takeOut', garageId, plate)
    if not result then return notify(err or 'You cannot take that out.') end

    local entity = waitForEntity(result.netId)
    if not entity then return notify('Your vehicle did not spawn.') end

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
        local deadline = GetGameTimer() + 3000
        while GetVehiclePedIsIn(ped, false) == entity and GetGameTimer() < deadline do Wait(100) end
    end

    -- mods live behind client-only natives; the server treats them as untrusted
    local stored, err = QB.callback.trigger('qbgarages:store', garageId, plate, NetworkGetNetworkIdFromEntity(entity), GetVehicleFuelLevel(entity), QB.vehicle.getProperties(entity))
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

local function openGarage(garageId)
    if busy then return end

    CreateThread(function()
        local payload, err = QB.callback.trigger('qbgarages:list', garageId)
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
                label = exports.qbcore:getShared('vehicles',vehicle.model).name,
                description = ('%s · %s'):format(vehicle.plate, status),
                image = 'https://docs-backend.fivem.net/vehicles/' .. vehicle.model .. '.webp',
                icon = icon,
                badge = badge,
                action = badge and 'garage:use' or nil,
            }
        end

        QB.nui.registerApp({
            id = 'qbgarages:garage',
            title = garage.label,
            description = policy.label or 'Garage',
            icon = impound and 'lock' or 'warehouse',
            accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
            layout = 'standard',
            width = 1200, height = 800,
            navigation = {
                { id = 'vehicles', label = 'Vehicles', icon = 'car-front', badge = #items,
                    content = {
                        title = garage.label,
                        description = 'Select a vehicle.',
                        blocks = {
                            { type = 'list', id = 'garage-vehicles', title = 'Your vehicles', layout = 'cards',
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
                QB.nui.closeApp('qbgarages:garage')

                CreateThread(function()
                    local ok, failure = pcall(function()
                        if vehicle.state == 'out' then store(garageId, plate) else takeOut(garageId, plate) end
                    end)
                    busy = false
                    if not ok then
                        notify('Something went wrong.')
                    end
                end)

                return {}
            end,
        })
        QB.nui.openApp('qbgarages:garage')
    end)
end


local function mayUse(garage)
    local policy = Config.garageTypes[garage.type]
    if not policy then return false end

    if garage.job then
        local job = exports.qbcore:getJob()
        if type(job) ~= 'table' or job.name ~= garage.job then return false end
        if policy.requireDuty and not job.onduty then return false end
        return true
    end

    if garage.gang then
        local gang = exports.qbcore:getGang()
        if type(gang) ~= 'table' or gang.name ~= garage.gang then return false end
        return true
    end

    return true
end

local function addZone(id, garage)
    local policy = Config.garageTypes[garage.type]
    if not policy then return end
    local impound = policy.shows == 'impounded'

    QB.interact.addBoxZone(('qbgarages:%s'):format(id), toVec3(garage.coords), toVec3(garage.size or Config.interaction.zoneSize), {
        {
            label = (impound and 'Collect from %s' or 'Open %s'):format(garage.label),
            icon = impound and 'car-front' or 'warehouse',
            canInteract = function()return mayUse(garage) end,
            action = function() openGarage(id) end,
        },
    }, Config.debug)
end

for id, garage in pairs(Config.garages) do addZone(id, garage) end

CreateThread(function()
    local extra = QB.callback.trigger('qbgarages:houseGarages')
    if type(extra) ~= 'table' then return end

    for id, garage in pairs(extra) do
        if not Config.garages[id] then
            Config.garages[id] = garage
            addZone(id, garage)
        end
    end
end)

local function createBlips()
    for _, blip in ipairs(blips) do QB.blips.remove(blip) end
    blips = {}

    for id, garage in pairs(Config.garages) do
        local policy = Config.garageTypes[garage.type]
        local isHouse = tostring(id):find('^house_') ~= nil

        if policy and not garage.noBlip and (Config.houseGarages.blip or not isHouse) then
            local blip = QB.blips.create(garage.coords, {
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
AddEventHandler('qbcore:client:playerLoaded', createBlips)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then createBlips() end
end)