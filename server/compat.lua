-- The real qb-garages wire protocol.
--
-- These are the literal callback and event names in
-- github.com/qbcore-framework/qb-garages, so a resource written against it (a
-- tow script, a police impound command, a housing resource that opens a garage)
-- keeps working with no edit. Same posture as qbinventory's own
-- server/compat/qb_callbacks.lua:
--
--   * REGISTRATION goes straight onto qblib's callback registry, which is the
--     one qbcore's `QBCore.Functions.TriggerCallback` compat actually awaits.
--     qbcore's `CreateCallback` forwards a handler's RETURN VALUES rather than
--     handing it upstream's `cb` continuation, so upstream's literal
--     `function(source, cb, plate)` shape would bind `cb` to the first real
--     argument and the caller's promise would never resolve. The bodies here are
--     therefore return-value shaped.
--
--   * SECURITY is not relaxed for legacy callers. Every one of these funnels
--     into the same Garages.api/Garages.access functions the native path uses,
--     so a legacy consumer gets the same ownership, distance and routing-bucket
--     checks. Nothing here is a new mutation primitive.
--
-- Upstream's `type`/`category`/`gang` arguments are accepted and IGNORED where
-- this resource resolves the same fact authoritatively. They were the client
-- telling the server what kind of garage it was standing in, which is precisely
-- the class of claim this design refuses.

if not Config.compat.legacy then return end

local api = Garages.api
local A = Garages.access
local S = Garages.shared

---Upstream sends its own garage name. It is looked up in Config.garages, and an
---unknown one is refused rather than defaulted: silently answering for some
---other garage would authorise an action at the wrong location.
---@param src integer
---@param garageId any
---@return table|nil resolved, string|nil error
local function resolve(src, garageId)
    return A.resolve(src, garageId)
end

-- --- callbacks --------------------------------------------------------------

-- Upstream: (garage, type, category) -> a plate-keyed table of vehicle rows.
-- Answered with this resource's own wire records, which are a strict subset of
-- upstream's row shape plus `label`/`engine`/`body` percentages -- a legacy UI
-- reads `plate`, `model` and `fuel` off them exactly as before.
QB.callback.register('qb-garage:server:GetGarageVehicles', function(src, garageId)
    local payload = api.list(src, garageId)
    if not payload then return nil end

    local byPlate = {}
    for _, vehicle in ipairs(payload.vehicles) do byPlate[vehicle.plate] = vehicle end
    return byPlate
end, { rateLimit = { max = 15, window = 5000 } })

-- Upstream's "depot" is this resource's impound lot. Upstream took no garage
-- argument at all (it had one global depot), so the lot is found in config by
-- type -- which is why Config.garageTypes.impound.shows exists as data rather
-- than as an `if garage.type == 'impound'` somewhere.
QB.callback.register('qb-garage:server:GetDepotVehicles', function(src)
    for id, garage in pairs(Config.garages) do
        if garage.type == 'impound' then
            local payload = api.list(src, id)
            if payload then
                local byPlate = {}
                for _, vehicle in ipairs(payload.vehicles) do byPlate[vehicle.plate] = vehicle end
                return byPlate
            end
        end
    end
    return {}
end, { rateLimit = { max = 15, window = 5000 } })

-- Upstream: (plate, garage, type, gang) -> (owned, vehicleRow). The `gang`
-- argument is dropped: gang membership is read out of qbcore here, never taken
-- from the caller.
QB.callback.register('qb-garage:server:checkOwner', function(src, plate, garageId)
    local resolved, err = resolve(src, garageId)
    if not resolved then return false, err end

    local row, rowErr = A.ownedRowFor(resolved, plate)
    if not row then return false, rowErr end

    return true, S.wire(row, resolved.garage)
end, { rateLimit = { max = 20, window = 5000 } })

-- Upstream: (plate, type) -> whether the vehicle may be spawned right now.
-- Upstream answered this by asking the CLIENT whether a spawn point looked
-- clear; here it is the server's own free-space search, so a client that lies
-- about congestion gains nothing.
QB.callback.register('qb-garage:server:IsSpawnOk', function(src, plate, garageId)
    local resolved = resolve(src, garageId)
    if not resolved then return false end

    local row = A.ownedRowFor(resolved, plate)
    if not row or row.state == 'out' or row.state == 'impounded' then return false end

    return api.freeSpawn(resolved.garage) ~= nil
end, { rateLimit = { max = 20, window = 5000 } })

-- Upstream: (plate) -> the stored mods blob, for a client to apply after it
-- spawned the vehicle itself. Ownership-gated, because the blob is a fair
-- description of somebody's car.
QB.callback.register('qb-garage:server:GetVehicleProperties', function(src, plate)
    local citizenid = A.citizenid(src)
    if not citizenid then return nil end

    local row = A.ownedRow(citizenid, plate)
    if not row then return nil end

    return row.mods
end, { rateLimit = { max = 20, window = 5000 } })

-- --- events -----------------------------------------------------------------

-- Upstream: (state, plate, fuel, engine, body, garage, type, gang). The
-- condition values are DROPPED -- they are exactly the client-supplied readings
-- this resource refuses, and the real ones are read off the entity server-side.
--
-- `state` is upstream's 0 = out / 1 = garaged integer. Only the garage-in
-- transition is honoured: a legacy "state 0" write would be a free
-- un-impound/spawn-nothing primitive with no location proof behind it.
RegisterNetEvent('qb-garage:server:updateVehicleState', function(state, plate, netId, garageId)
    local src = source

    if Config.compat.strictLegacyState and tonumber(state) ~= 1 then
        -- Nothing is thrown: a legacy resource mid-flow must not die because
        -- its own protocol asked for something this one will not do.
        return
    end

    -- netId is not part of upstream's signature at all (it had no need: the
    -- client deleted the car itself). It is accepted here as an optional trailing
    -- argument so an updated consumer can pass it; without one there is no entity
    -- to verify, and a store with no verifiable entity is refused.
    if not netId then return end

    api.store(src, garageId, plate, netId, nil)
end)

-- Upstream: (data) with `data.vehicle` / `data.depotPrice`. The PRICE is ignored
-- -- the fee is the one recorded on the row, clamped by Config.impound.maxFee.
-- Honouring a caller-supplied price would let a client pay one dollar for its
-- own impound release, which is the single most valuable thing to fake here.
RegisterNetEvent('qb-garage:server:PayDepotPrice', function(data)
    local src = source
    local plate = type(data) == 'table' and (data.plate or (type(data.vehicle) == 'table' and data.vehicle.plate)) or nil
    if not plate then return end

    for id, garage in pairs(Config.garages) do
        if garage.type == 'impound' then
            local result, err = api.retrieveImpound(src, id, plate)
            if result then return end
            -- Only reported once, against the lot the player is actually at:
            -- A.resolve inside retrieveImpound refuses every other lot on
            -- distance, so a multi-lot server would otherwise notify per lot.
            if err and err ~= 'too far from the garage' then
                TriggerClientEvent('qbgarages:client:refused', src, err)
                return
            end
        end
    end
end)
