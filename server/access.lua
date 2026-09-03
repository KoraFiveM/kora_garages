-- The gate every garage action funnels through.
--
-- AUTHORITY BOUNDARY. The browser sends a garage id and a plate, and that is
-- ALL it sends -- both are intent, never data. This file re-resolves the garage
-- out of Config, re-reads the player's citizenid/job/gang out of qbcore, re-reads
-- the player's position and routing bucket off the server-side ped, and
-- re-reads the vehicle row out of the DB by plate. Nothing a client sent is ever
-- stored, echoed back as authority, or used in place of one of those reads.
--
-- Every native is reached through a `type(...) == 'function'` guard and a
-- missing one FAILS THE CHECK rather than skipping it. Two reasons: the plain-Lua
-- smoke suite can then install exactly the natives a scenario needs, and a
-- future FXServer that moves a native client-side degrades into "refused" rather
-- than into "unchecked".

Garages = Garages or {}
Garages.access = {}

local S = Garages.shared
local A = Garages.access

---@param src integer
---@return string|nil citizenid, string|nil error
function A.citizenid(src)
    local ok, citizenid = pcall(function()
        return exports.qbcore:getPlayerData(src, { 'citizenid' })
    end)
    if not ok or type(citizenid) ~= 'string' or #citizenid == 0 then
        return nil, 'no loaded character'
    end
    return citizenid
end

---@param src integer
---@return table|nil
local function jobOf(src)
    local ok, job = pcall(function() return exports.qbcore:getJob(src) end)
    return ok and type(job) == 'table' and job or nil
end

---@param src integer
---@return table|nil
local function gangOf(src)
    local ok, gang = pcall(function() return exports.qbcore:getGang(src) end)
    return ok and type(gang) == 'table' and gang or nil
end

---Whether `src` satisfies a garage's job/gang policy. Split out from `resolve`
---so the client can ask the same question for a `canInteract` gate without
---also being told how far away it thinks the player is.
---@param src integer
---@param garage table
---@return boolean ok, string|nil error
function A.entitled(src, garage)
    local policy, policyErr = S.policy(garage)
    if not policy then return false, policyErr end

    if garage.job then
        local job = jobOf(src)
        if not job or job.name ~= garage.job then return false, 'this garage is not for your job' end
        -- `onduty` is qbcore's spelling (PlayerData.job.onduty), not `onDuty`.
        -- Reading the wrong one yields nil, which is falsy, which would refuse
        -- every on-duty officer -- so this is checked explicitly against false.
        if policy.requireDuty and not job.onduty then return false, 'you must be on duty' end
    end

    if garage.gang then
        local gang = gangOf(src)
        if not gang or gang.name ~= garage.gang then return false, 'this garage is not for your gang' end
    end

    return true
end

---@param src integer
---@return table|nil coords, string|nil error
function A.coords(src)
    if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function'
        or type(DoesEntityExist) ~= 'function' then
        return nil, 'position validation unavailable'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, 'player entity unavailable' end
    return GetEntityCoords(ped)
end

---@param src integer
---@param garage table
---@return boolean ok, string|nil error
function A.sameBucket(src, garage)
    if Config.interaction.requireSameBucket == false then return true end
    if type(GetPlayerRoutingBucket) ~= 'function' then return false, 'routing bucket validation unavailable' end

    -- A garage with no numeric bucket is a configuration error and fails
    -- closed: "any bucket" is not a thing a garage should be able to mean by
    -- omission, or an instanced apartment garage would be reachable from the
    -- open world.
    local bucket = tonumber(garage.bucket)
    if not bucket then return false, 'garage has no routing bucket' end

    if GetPlayerRoutingBucket(src) ~= bucket then return false, 'garage is not in your world' end
    return true
end

---The full gate: garage exists, character loaded, job/gang policy satisfied,
---same routing bucket, and standing at the garage.
---@param src integer
---@param garageId any The id the client sent. Re-resolved here, never trusted.
---@return table|nil resolved `{ id, garage, policy, citizenid, coords }`
---@return string|nil error
function A.resolve(src, garageId)
    local garage, garageErr = S.garage(garageId)
    if not garage then return nil, garageErr end

    local policy, policyErr = S.policy(garage)
    if not policy then return nil, policyErr end

    local citizenid, citizenErr = A.citizenid(src)
    if not citizenid then return nil, citizenErr end

    local entitled, entitledErr = A.entitled(src, garage)
    if not entitled then return nil, entitledErr end

    local bucketOk, bucketErr = A.sameBucket(src, garage)
    if not bucketOk then return nil, bucketErr end

    local coords, coordsErr = A.coords(src)
    if not coords then return nil, coordsErr end

    local separation = S.distance(coords, garage.coords)
    if not separation then return nil, 'garage coordinates unavailable' end

    local limit = tonumber(garage.distance) or tonumber(Config.interaction.distance) or 4.0
    if separation > limit then return nil, 'too far from the garage' end

    return { id = garageId, garage = garage, policy = policy, citizenid = citizenid, coords = coords }
end

---The vehicle row for `plate`, but only if `citizenid` owns it.
---
---Ownership is re-read from the DB every time rather than cached against a
---session: a vehicle can be sold, impounded or deleted between the panel
---opening and a button being pressed, and a cached row would authorise the
---action anyway.
---@param citizenid string
---@param plate any The plate the client sent. Normalised and re-looked-up here.
---@return table|nil row, string|nil error
function A.ownedRow(citizenid, plate)
    local normalised, plateErr = S.normalisePlate(plate)
    if not normalised then return nil, plateErr end

    local ok, row = pcall(function() return exports.qbcore:getByPlate(normalised) end)
    if not ok or type(row) ~= 'table' then return nil, 'unknown vehicle' end

    -- A job-fleet row has no citizenid at all (qbcore's garage module stores
    -- exactly one of citizenid/job). Those are reachable only through a job
    -- garage, which is authorised by A.entitled above -- so the ownership test
    -- here is deliberately "not somebody else's", not "mine".
    if row.citizenid and row.citizenid ~= citizenid then return nil, 'not your vehicle' end
    if not row.citizenid and not row.job then return nil, 'not your vehicle' end

    return row
end

---Ownership for a row reached through a garage: adds the job-fleet rule that
---A.ownedRow deliberately leaves to the caller.
---@param resolved table From A.resolve.
---@param plate any
---@return table|nil row, string|nil error
function A.ownedRowFor(resolved, plate)
    local row, err = A.ownedRow(resolved.citizenid, plate)
    if not row then return nil, err end

    -- A fleet vehicle belongs to a job, so it may only be handled at that job's
    -- own garage. Without this a police cruiser row would be retrievable from
    -- Legion Square by any officer who knew the plate.
    if row.job and row.job ~= resolved.garage.job then return nil, 'not your vehicle' end

    return row
end
