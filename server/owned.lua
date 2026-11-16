local MAX_ROWS = 200
local MAX_CITIZENID = 50
local NO_GARAGE_LABEL = 'None'
local HOUSE_GARAGE_LABEL = 'House'
local STATES = { out = true, garaged = true, impounded = true }

local function sharedVehicle(model)
    local ok, shared = pcall(function() return exports.kora_core:getShared('vehicles', model) end)
    return ok and type(shared) == 'table' and shared or {}
end

---Display name for a vehicle model, `Brand Name` when kora_core knows it, else the model itself.
---@param model string
---@return string
local function vehicleLabel(model)
    local data = sharedVehicle(model)
    if type(data.name) ~= 'string' or data.name == '' then return model end
    if type(data.brand) == 'string' and data.brand ~= '' then return data.brand .. ' ' .. data.name end
    return data.name
end

---Garage id and its display name. Ids that are not configured garages (houses) are labelled 'House'.
---@param row table
---@return string id
---@return string label
local function garageOf(row)
    local id = row.garage_id
    if type(id) ~= 'string' or id == '' then return '', NO_GARAGE_LABEL end
    local garage = Config.garages[id]
    return id, garage and garage.label or HOUSE_GARAGE_LABEL
end

---One owned vehicle row in the public export shape.
---@param row table player_vehicles row from kora_core
---@return table
local function publicVehicle(row)
    local model = tostring(row.model or '')
    local garage, garageLabel = garageOf(row)
    return {
        plate = tostring(row.plate or ''),
        model = model,
        label = vehicleLabel(model),
        garage = garage,
        garageLabel = garageLabel,
        state = STATES[row.state] and row.state or 'out',
        fuel = tonumber(row.fuel) or 0,
        engine = tonumber(row.engine_health) or 0,
        body = tonumber(row.body_health) or 0,
    }
end

---Server export. Lists the vehicles a character owns, sorted by plate, at most 200 rows.
---Yields: it reads through `exports.kora_core:getByOwner`, which queries the database.
---Server-side only; `citizenid` must come from trusted server code, never from a client argument.
---@param citizenid string
---@return table[]|false vehicles `{ plate, model, label, garage, garageLabel, state, fuel, engine, body }`
---@return string? err
exports('getOwnedVehicles', function(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > MAX_CITIZENID then
        return false, 'Invalid citizen id.'
    end
    local rows = exports.kora_core:getByOwner(citizenid)
    if type(rows) ~= 'table' then return {} end

    local owned = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' then owned[#owned + 1] = row end
    end
    table.sort(owned, function(a, b) return tostring(a.plate) < tostring(b.plate) end)

    local vehicles = {}
    for index = 1, math.min(#owned, MAX_ROWS) do
        vehicles[index] = publicVehicle(owned[index])
    end
    return vehicles
end)
