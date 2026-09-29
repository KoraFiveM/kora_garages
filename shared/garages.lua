-- Pure helpers shared by client and server. Nothing here touches a native,
-- a DB or the network, which is what makes it easy to reason about.

Garages = Garages or {}
Garages.shared = {}

local S = Garages.shared

-- GTA pads plates to 8 characters with spaces, so a plate off a live entity
-- and a plate out of the DB aren't equal until both go through this.
function S.normalisePlate(value)
    if type(value) ~= 'string' then return nil, 'plate must be a string' end
    local plate, reason = QB.vehicle.normalizePlate(value, { whitespace = 'remove', characters = 'any' })
    if reason == 'empty' then return nil, 'plate must not be empty' end
    if reason == 'too_long' then return nil, 'plate must be at most 8 characters' end
    if not plate then return nil, 'plate must be valid' end
    return plate
end

function S.garage(garageId)
    if type(garageId) ~= 'string' then return nil, 'unknown garage' end
    local garage = Config.garages[garageId]
    if not garage then return nil, 'unknown garage' end
    return garage
end

function S.policy(garage)
    local policy = garage and Config.garageTypes[garage.type]
    if not policy then return nil, 'garage has no known type' end
    return policy
end

function S.distance(a, b)
    if type(a) ~= 'table' and type(a) ~= 'vector3' and type(a) ~= 'vector4' then return nil end
    if type(b) ~= 'table' and type(b) ~= 'vector3' and type(b) ~= 'vector4' then return nil end
    local ok, result = pcall(function()
        local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return ok and result or nil
end

-- The qbcore shared-vehicle category for a model, or nil for one not in the
-- registry (an addon car nobody registered, for instance).
function S.category(model)
    if type(model) ~= 'string' or #model == 0 then return nil end
    local ok, record = pcall(function() return exports.qbcore:getShared('vehicles', model:lower()) end)
    if not ok or type(record) ~= 'table' then return nil end
    return record.category
end

-- Whether `garage` accepts `model`. An unregistered model is always accepted:
-- the category list keeps a plane out of a street garage, it isn't a
-- whitelist of purchasable cars.
function S.accepts(garage, model)
    local allowed = garage and garage.categories
    if not allowed or #allowed == 0 then return true end

    local category = S.category(model)
    if not category then return true end

    for _, name in ipairs(allowed) do
        if name == category then return true end
    end
    return false, 'this garage does not accept that vehicle'
end

local function number(value)
    return tonumber(value) or 0
end

-- Clamps a 0..Config.listing.healthScale reading to a 0-100 percentage.
function S.percent(value)
    local scale = tonumber(Config.listing.healthScale) or 1000.0
    local pct = math.floor((number(value) / scale) * 100 + 0.5)
    if pct < 0 then return 0 end
    if pct > 100 then return 100 end
    return pct
end

-- Whether a DB row belongs in this garage's listing. An impound lot only
-- lists impounded rows; every other garage only lists non-impounded ones.
function S.listedIn(garage, row)
    local policy = S.policy(garage)
    if not policy then return false end

    if policy.shows == 'impounded' then
        return row.state == 'impounded'
    end

    if row.state == 'impounded' then return false end
    if not S.accepts(garage, row.model) then return false end
    return true
end

-- The record the browser sees. Deliberately narrow: no citizenid, mods blob
-- or last known position, none of which a UI needs.
function S.wire(row, garage)
    local fee
    if row.state == 'impounded' then
        fee = math.min(
            math.max(number(row.impound_fee) > 0 and number(row.impound_fee) or Config.impound.defaultFee, 0),
            tonumber(Config.impound.maxFee) or math.huge
        )
    end

    return {
        plate = row.plate,
        model = row.model,
        label = S.label(row.model),
        category = S.category(row.model),
        state = row.state,
        fuel = math.floor(number(row.fuel) + 0.5),
        engine = S.percent(row.engine_health),
        body = S.percent(row.body_health),
        fee = fee,
        accepted = garage and (S.accepts(garage, row.model) and true or false) or true,
    }
end

function S.label(model)
    if type(model) ~= 'string' then return 'Vehicle' end
    local ok, record = pcall(function() return exports.qbcore:getShared('vehicles', model:lower()) end)
    if ok and type(record) == 'table' and type(record.name) == 'string' then
        if type(record.brand) == 'string' and #record.brand > 0 then
            return ('%s %s'):format(record.brand, record.name)
        end
        return record.name
    end
    return model
end
