-- The four garage actions, all server-authoritative.
--
-- PERSISTENCE IS NOT OWNED HERE. Every read and write of a vehicle row goes
-- through qbcore's Core.garage.* exports (getByPlate/getByOwner/spawnVehicle/
-- storeVehicle/impound/retrieveImpound). This file never touches
-- `player_vehicles`, never writes SQL, and holds no vehicle state of its own --
-- it is the gameplay and UI layer on top. If a rule here needs a new column,
-- that is a qbcore change, not a table this resource may reach into.

Garages = Garages or {}
Garages.api = {}

local S = Garages.shared
local A = Garages.access
local api = Garages.api

---One call into qbcore's flat export surface, with the pcall the framework
---convention expects around a cross-resource call: qbcore restarting mid-shift
---must surface as "persistence unavailable", not as an error thrown out of a
---client-facing callback and a promise that never resolves.
---@param name string
---@param ... any
---@return any value, string|nil error
local function core(name, ...)
    local args = { ... }
    local ok, a, b = pcall(function() return exports.qbcore[name](exports.qbcore, table.unpack(args)) end)
    if not ok then return nil, 'qbcore garage persistence unavailable' end
    return a, b
end

-- --- mods -------------------------------------------------------------------

local cosmeticKeys
local function isCosmetic(key)
    if not cosmeticKeys then
        cosmeticKeys = {}
        for _, name in ipairs(Config.mods.cosmetic) do cosmeticKeys[name] = true end
    end
    return cosmeticKeys[key] == true
end

---Strips a client-supplied properties blob down to the cosmetic allow-list.
---
---Returns nil for anything that is not a table or that carries more keys than
---Config.mods.entryCap -- an oversized blob is a client trying to grow a DB
---column, and dropping it costs the player their wheel colour, not their car.
---@param mods any
---@return table|nil
function api.filterMods(mods)
    if type(mods) ~= 'table' then return nil end

    local out, count = {}, 0
    for key, value in pairs(mods) do
        count = count + 1
        if count > Config.mods.entryCap then return nil end
        if type(key) == 'string' and isCosmetic(key) then out[key] = value end
    end

    if next(out) == nil then return nil end
    return out
end

-- --- spawn points -----------------------------------------------------------

---The first configured spawn point with nothing parked on it.
---
---Occupancy is checked against the SERVER's own entity list, not against
---anything a client reported. When GetAllVehicles is unavailable the first point
---is used unchecked: a garage that refused to hand over any vehicle because it
---could not enumerate entities would be worse than one that occasionally spawns
---a car close to another.
---@param garage table
---@return table|nil spawn, string|nil error
function api.freeSpawn(garage)
    local spawns = garage.spawns
    if type(spawns) ~= 'table' or #spawns == 0 then return nil, 'garage has no spawn point' end

    if type(GetAllVehicles) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return spawns[1]
    end

    local clearance = tonumber(Config.spawn.clearance) or 3.0
    local parked = {}
    for _, vehicle in ipairs(GetAllVehicles() or {}) do
        -- Only vehicles in the garage's own world can block it; a car parked on
        -- the same coordinates in another routing bucket is somewhere else.
        local sameBucket = type(GetEntityRoutingBucket) ~= 'function'
            or GetEntityRoutingBucket(vehicle) == (tonumber(garage.bucket) or 0)
        if sameBucket then parked[#parked + 1] = GetEntityCoords(vehicle) end
    end

    for _, spawn in ipairs(spawns) do
        local blocked = false
        for _, coords in ipairs(parked) do
            local separation = S.distance(coords, spawn)
            if separation and separation < clearance then
                blocked = true
                break
            end
        end
        if not blocked then return spawn end
    end

    return nil, 'every space is taken'
end

-- --- list -------------------------------------------------------------------

---Everything the player may see at `garageId`, already narrowed to the wire
---shape. The citizenid is resolved server-side, so this cannot be asked on
---somebody else's behalf.
---@param src integer
---@param garageId any
---@return table|nil payload, string|nil error
function api.list(src, garageId)
    local resolved, err = A.resolve(src, garageId)
    if not resolved then return nil, err end

    -- Always the caller's OWN vehicles. A job or gang garage is an ACCESS
    -- POLICY over them (who may park here, and which categories), not a
    -- separate fleet listing -- see docs/index.md "Job and gang garages" for
    -- why the fleet view is deliberately absent rather than half-built.
    local rows = core('getByOwner', resolved.citizenid) or {}

    local vehicles = {}
    for _, row in ipairs(rows) do
        if S.listedIn(resolved.garage, row) then
            vehicles[#vehicles + 1] = S.wire(row, resolved.garage)
            if #vehicles >= (tonumber(Config.listing.max) or 50) then break end
        end
    end

    return {
        garage = {
            id = resolved.id,
            label = resolved.garage.label,
            type = resolved.garage.type,
            typeLabel = resolved.policy.label,
            -- Whether the STORE button exists at all. Sent as a fact about the
            -- garage rather than inferred in the browser from the type string,
            -- so a new type does not need a matching branch in TypeScript.
            canStore = resolved.policy.allowStore ~= false,
            isImpound = resolved.policy.shows == 'impounded',
        },
        vehicles = vehicles,
    }
end

-- --- take out ---------------------------------------------------------------

---@param src integer
---@param garageId any
---@param plate any
---@return table|false result `{ netId, plate, spawn, mods }`
---@return string? error
function api.takeOut(src, garageId, plate)
    local resolved, err = A.resolve(src, garageId)
    if not resolved then return false, err end

    local row, rowErr = A.ownedRowFor(resolved, plate)
    if not row then return false, rowErr end

    -- Refused HERE as well as inside Core.garage.spawnVehicle: this one carries
    -- the fee in its message, and reaching the core's bare "vehicle is
    -- impounded" would tell the player nothing about how to get it back.
    if row.state == 'impounded' then
        return false, ('vehicle is impounded (%s)'):format(resolved.policy.shows == 'impounded'
            and 'retrieve it here' or 'collect it from the impound lot')
    end
    if row.state == 'out' then return false, 'vehicle is already out' end

    local accepted, acceptErr = S.accepts(resolved.garage, row.model)
    if not accepted then return false, acceptErr end

    local spawn, spawnErr = api.freeSpawn(resolved.garage)
    if not spawn then return false, spawnErr end

    local netId, coreErr = core('spawnVehicle', src, row.plate, spawn, spawn.w or 0.0)
    if not netId or netId == false then return false, coreErr or 'failed to spawn vehicle' end

    return {
        netId = netId,
        plate = row.plate,
        spawn = spawn,
        -- The mods blob the SERVER read out of the DB. The client applies it,
        -- but it never chose it -- which is what keeps the round trip honest:
        -- what comes back out is what the allow-list let in.
        mods = Config.spawn.applyMods and row.mods or nil,
        warp = Config.spawn.warpIntoVehicle == true,
    }
end

-- --- store ------------------------------------------------------------------

---Resolves the live entity a client is asking to store, by network id.
---
---`expectedPlate` is the plate the SERVER already resolved from the DB, not one
---the client sent: the entity's own plate must match it, or a player could park
---any car in the world against a row they happen to own.
---@param src integer
---@param resolved table From A.resolve.
---@param netId any
---@param expectedPlate string
---@return integer|nil entity, string|nil error
function api.resolveEntity(src, resolved, netId, expectedPlate)
    netId = tonumber(netId)
    if not netId or netId < 1 or type(NetworkGetEntityFromNetworkId) ~= 'function' then
        return nil, 'invalid vehicle entity'
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or type(DoesEntityExist) ~= 'function' or not DoesEntityExist(entity) then
        return nil, 'vehicle does not exist'
    end
    if type(GetEntityType) ~= 'function' or GetEntityType(entity) ~= 2 then
        return nil, 'entity is not a vehicle'
    end

    if Config.interaction.requireSameBucket ~= false then
        if type(GetEntityRoutingBucket) ~= 'function' then return nil, 'routing bucket validation unavailable' end
        if GetEntityRoutingBucket(entity) ~= (tonumber(resolved.garage.bucket) or 0) then
            return nil, 'vehicle is not in your world'
        end
    end

    if type(GetVehicleNumberPlateText) ~= 'function' then return nil, 'vehicle details unavailable' end
    local plate = S.normalisePlate(GetVehicleNumberPlateText(entity))
    if plate ~= expectedPlate then return nil, 'that is not the same vehicle' end

    local coords = GetEntityCoords(entity)
    local separation = S.distance(coords, resolved.garage.coords)
    if not separation then return nil, 'vehicle coordinates unavailable' end
    if separation > (tonumber(Config.interaction.storeDistance) or 12.0) then
        return nil, 'the vehicle is not at this garage'
    end

    return entity
end

---The condition snapshot, read off the entity by the SERVER.
---
---Nothing here comes from the client. A missing native leaves its field nil,
---and Core.garage.storeVehicle COALESCEs a nil onto the stored value -- so an
---unreadable reading keeps the last known one instead of writing a zero and
---telling the player their engine is destroyed.
---@param entity integer
---@return table
function api.snapshot(entity)
    local snapshot = {}

    if type(GetVehicleEngineHealth) == 'function' then
        snapshot.engineHealth = math.floor(tonumber(GetVehicleEngineHealth(entity)) or 0)
    end
    if type(GetVehicleBodyHealth) == 'function' then
        snapshot.bodyHealth = math.floor(tonumber(GetVehicleBodyHealth(entity)) or 0)
    end
    if type(GetVehicleFuelLevel) == 'function' then
        snapshot.fuel = math.floor(tonumber(GetVehicleFuelLevel(entity)) or 0)
    end
    if type(GetEntityCoords) == 'function' then
        local coords = GetEntityCoords(entity)
        if coords then snapshot.position = { x = coords.x, y = coords.y, z = coords.z } end
    end

    return snapshot
end

---@param src integer
---@param garageId any
---@param plate any Intent: re-resolved against the DB and against the entity.
---@param netId any Intent: re-resolved to a real entity the server can see.
---@param mods any Client-supplied cosmetic blob; filtered, never trusted.
---@return boolean ok, string|nil error
function api.store(src, garageId, plate, netId, mods)
    local resolved, err = A.resolve(src, garageId)
    if not resolved then return false, err end

    if resolved.policy.allowStore == false then
        return false, 'you cannot store a vehicle here'
    end

    local row, rowErr = A.ownedRowFor(resolved, plate)
    if not row then return false, rowErr end

    if row.state == 'impounded' then return false, 'vehicle is impounded' end

    local accepted, acceptErr = S.accepts(resolved.garage, row.model)
    if not accepted then return false, acceptErr end

    local entity, entityErr = api.resolveEntity(src, resolved, netId, row.plate)
    if not entity then return false, entityErr end

    local snapshot = api.snapshot(entity)
    snapshot.mods = api.filterMods(mods)

    local ok, storeErr = core('storeVehicle', row.plate, snapshot)
    if not ok then return false, storeErr or 'failed to store vehicle' end

    -- qbcore's storeVehicle deliberately does NOT delete the entity -- it has no
    -- handle -- so the caller does, and the caller is this server, not the
    -- client. Deleting client-side would leave the row `garaged` while the car
    -- was still driveable for anyone whose client ignored the request.
    if type(DeleteEntity) == 'function' then DeleteEntity(entity) end

    return true
end

-- --- impound ----------------------------------------------------------------

---The fee for an impounded row, clamped to Config.impound.maxFee.
---@param row table
---@return integer
function api.impoundFee(row)
    local fee = tonumber(row.impound_fee)
    if not fee or fee <= 0 then fee = tonumber(Config.impound.defaultFee) or 0 end
    local ceiling = tonumber(Config.impound.maxFee) or fee
    if fee > ceiling then fee = ceiling end
    return math.floor(fee)
end

---Pays the fee, then clears the impound flag, then hands the vehicle over.
---
---ORDER MATTERS AND IT IS THIS WAY ROUND. The money leaves first: clearing the
---flag first and charging afterwards makes an unaffordable retrieval into a free
---one, because the row is already `garaged` by the time the charge fails. The
---brief's rule -- charge through qbcore's money export BEFORE clearing the
---impound flag -- is exactly this.
---
---If the flag-clear then fails, the fee is REFUNDED. A player who is charged and
---gets nothing has no way to recover; a double refund is a bug we would rather
---have than a stolen fee.
---@param src integer
---@param garageId any
---@param plate any
---@return table|false result, string|nil error
function api.retrieveImpound(src, garageId, plate)
    local resolved, err = A.resolve(src, garageId)
    if not resolved then return false, err end

    if resolved.policy.shows ~= 'impounded' then
        return false, 'impounded vehicles are only released at an impound lot'
    end

    local row, rowErr = A.ownedRowFor(resolved, plate)
    if not row then return false, rowErr end
    if row.state ~= 'impounded' then return false, 'vehicle is not impounded' end

    local fee = api.impoundFee(row)
    local charged = false

    if fee > 0 then
        local paid, payErr = core('removeMoney', src, Config.impound.account, fee, Config.impound.reason)
        if not paid then
            -- qbcore's own reason ('insufficient funds') is passed through
            -- rather than reworded: the player needs to know whether they are
            -- short of money or the account name is wrong.
            return false, payErr or 'you cannot afford the release fee'
        end
        charged = true
    end

    local cleared, clearErr = core('retrieveImpound', src, row.plate)
    if not cleared then
        if charged then core('addMoney', src, Config.impound.account, fee, Config.impound.reason .. '-refund') end
        return false, clearErr or 'failed to release the vehicle'
    end

    -- Now an ordinary take-out. If the spawn fails the vehicle is already
    -- `garaged` and paid for, so it is recoverable from any garage -- which is a
    -- far better failure than a paid fee and a still-impounded row.
    local result, takeErr = api.takeOut(src, garageId, row.plate)
    if not result then return false, takeErr or 'released, but could not be spawned' end

    result.fee = fee
    return result
end
