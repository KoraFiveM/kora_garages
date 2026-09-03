-- Pure helpers shared by both realms.
--
-- Nothing here touches a native, a DB or the network: that is what makes the
-- garage rules (which plate belongs where, which vehicle a garage accepts, what
-- the browser is allowed to see) testable under plain lua5.4 with no FXServer.
-- Every function that can fail returns `(value, errorString)` -- the framework
-- convention -- rather than raising, because these run inside client-facing
-- callbacks where a raised error becomes a hung promise.

Garages = Garages or {}
Garages.shared = {}

local S = Garages.shared

---A plate as the DB stores it: uppercase, trimmed, no interior padding. GTA
---pads plates to 8 characters with spaces, so a plate read off a live entity
---and the same plate read out of SQL are NOT equal strings until both go
---through here -- comparing them raw is the classic reason a store action
---reports "not your vehicle" for a car the player is sitting in.
---@param value any
---@return string|nil plate, string|nil error
function S.normalisePlate(value)
    if type(value) ~= 'string' then return nil, 'plate must be a string' end
    local plate = value:gsub('%s+', ''):upper()
    if #plate == 0 then return nil, 'plate must not be empty' end
    if #plate > 8 then return nil, 'plate must be at most 8 characters' end
    return plate
end

---@param garageId any
---@return table|nil garage, string|nil error
function S.garage(garageId)
    if type(garageId) ~= 'string' then return nil, 'unknown garage' end
    local garage = Config.garages[garageId]
    if not garage then return nil, 'unknown garage' end
    return garage
end

---The type policy behind a garage.
---@param garage table
---@return table|nil policy, string|nil error
function S.policy(garage)
    local policy = garage and Config.garageTypes[garage.type]
    -- A garage naming a type that does not exist is a configuration error, and
    -- it fails CLOSED: an unknown policy has no idea who may use the garage, so
    -- guessing "everyone" would open it to the whole server.
    if not policy then return nil, 'garage has no known type' end
    return policy
end

---@param a table|nil {x,y,z}
---@param b table|nil {x,y,z}
---@return number|nil
function S.distance(a, b)
    if type(a) ~= 'table' and type(a) ~= 'vector3' then return nil end
    if type(b) ~= 'table' and type(b) ~= 'vector3' then return nil end
    local ok, result = pcall(function()
        local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return ok and result or nil
end

---The qbcore shared-vehicle category for a model, or nil when the model is not
---in the registry (an addon car nobody registered, for instance).
---@param model any
---@return string|nil
function S.category(model)
    if type(model) ~= 'string' or #model == 0 then return nil end
    -- Wrapped: `exports` does not exist at all in the smoke harness unless a
    -- test installs it, and a registry lookup must never be the reason a garage
    -- panel fails to open.
    local ok, record = pcall(function()
        return exports.qbcore:getShared('vehicles', model:lower())
    end)
    if not ok or type(record) ~= 'table' then return nil end
    return record.category
end

---Whether `garage` accepts a vehicle of `model`.
---
---An UNREGISTERED model is accepted. The allow-list exists to keep a plane out
---of a street garage, not to be a whitelist of purchasable cars -- refusing
---anything absent from the registry would make every addon vehicle
---unretrievable the moment one garage in the config grew a `categories` list.
---@param garage table
---@param model any
---@return boolean ok, string|nil error
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

---@param value any
---@return number
local function number(value)
    return tonumber(value) or 0
end

---Clamps a 0..Config.listing.healthScale reading to a whole 0-100 percentage.
---@param value any
---@return integer
function S.percent(value)
    local scale = tonumber(Config.listing.healthScale) or 1000.0
    local pct = math.floor((number(value) / scale) * 100 + 0.5)
    if pct < 0 then return 0 end
    if pct > 100 then return 100 end
    return pct
end

---Whether a DB row belongs in `garage`'s listing.
---
---This is the one place the impound inversion lives: an impound lot lists ONLY
---impounded rows and an ordinary garage lists only non-impounded ones, so
---neither view can offer an action the other owns.
---@param garage table
---@param row table
---@return boolean
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

---The record the BROWSER sees. Deliberately narrow: the DB row also carries the
---owner citizenid, the raw mods blob and the last known world position, none of
---which a UI needs and all of which are either identity or a hint about where
---to find somebody's car.
---@param row table
---@param garage table|nil
---@return table
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
        -- The friendly name when the model is in the registry, the raw spawn
        -- code when it is not. A UI showing "sultan" is worse than one showing
        -- "Sultan", but a UI showing nothing at all is unusable.
        label = S.label(row.model),
        category = S.category(row.model),
        state = row.state,
        fuel = math.floor(number(row.fuel) + 0.5),
        engine = S.percent(row.engine_health),
        body = S.percent(row.body_health),
        fee = fee,
        -- Whether THIS garage would let the vehicle in, so the panel can grey
        -- out a plane in a street garage instead of letting the player press a
        -- button the server is certain to refuse.
        accepted = garage and (S.accepts(garage, row.model) and true or false) or true,
    }
end

---@param model any
---@return string
function S.label(model)
    if type(model) ~= 'string' then return 'Vehicle' end
    local ok, record = pcall(function()
        return exports.qbcore:getShared('vehicles', model:lower())
    end)
    if ok and type(record) == 'table' and type(record.name) == 'string' then
        if type(record.brand) == 'string' and #record.brand > 0 then
            return ('%s %s'):format(record.brand, record.name)
        end
        return record.name
    end
    return model
end
