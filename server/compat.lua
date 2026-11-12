local statusLabels = { out = 'Out', garaged = 'Garaged', impounded = 'Impounded By Police' }
local lastCall = {}

local function sharedVehicle(model)
    local ok, shared = pcall(function() return exports.kora_core:getShared('vehicles', model) end)
    return ok and type(shared) == 'table' and shared or {}
end

Kora.callback.register('qb-garages:server:GetPlayerVehicles', function(src)
    local now = GetGameTimer()
    if lastCall[src] and now - lastCall[src] < 1000 then return nil end
    lastCall[src] = now

    local citizenid = exports.kora_core:getPlayerData(src, { 'citizenid' })
    if not citizenid then return nil end
    local rows = exports.kora_core:getByOwner(citizenid)
    if not rows or not rows[1] then return nil end

    local vehicles = {}
    for _, row in ipairs(rows) do
        local data = sharedVehicle(row.model)
        local garage = 'None'
        if row.garage_id ~= nil then
            garage = Config.garages[row.garage_id] and Config.garages[row.garage_id].label or 'House'
        end
        vehicles[#vehicles + 1] = {
            fullname = data.name and ((data.brand and data.brand .. ' ' or '') .. data.name) or 'Unknown Vehicle',
            brand = data.brand or '',
            model = data.name or '',
            plate = row.plate,
            garage = garage,
            state = statusLabels[row.state],
            fuel = row.fuel,
            engine = row.engine_health,
            body = row.body_health,
        }
    end
    return vehicles
end)

AddEventHandler('playerDropped', function() lastCall[source] = nil end)

exports('getAllGarages', function()
    local garages = {}
    for name, garage in pairs(Config.garages) do
        if not garage.disabled then
            local spawn = garage.spawns and garage.spawns[1] or garage.spawn
            local kind = Config.garageTypes[garage.type] or {}
            garages[#garages + 1] = {
                name = name,
                label = garage.label,
                type = garage.type,
                takeVehicle = garage.coords,
                putVehicle = garage.coords,
                spawnPoint = spawn,
                showBlip = true,
                blipName = kind.blipLabel or garage.label,
                blipNumber = kind.blipSprite,
                blipColor = kind.blipColor,
                vehicle = 'car',
            }
        end
    end
    return garages
end)
