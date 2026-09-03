-- The client-facing surface, and the native server exports other resources use.
--
-- Every callback below takes a garage id and (where relevant) a plate and a
-- network id. That is the complete list of things a client may send. No
-- coordinates, no condition values, no vehicle record, no citizenid, no fee --
-- each of those is re-resolved inside Garages.access/Garages.api, which is the
-- only reason this surface is safe to expose at all.
--
-- Rate limits are sized for a player clicking buttons, not for a script: the
-- listing is the one a UI re-fetches (after every action), the actions are
-- deliberately tighter because each one is a DB write.

local api = Garages.api
local A = Garages.access

QB.callback.register('qbgarages:list', function(src, garageId)
    local payload, err = api.list(src, garageId)
    if not payload then return false, err end
    return payload
end, { rateLimit = { max = 15, window = 5000 } })

QB.callback.register('qbgarages:takeOut', function(src, garageId, plate)
    return api.takeOut(src, garageId, plate)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbgarages:store', function(src, garageId, plate, netId, mods)
    return api.store(src, garageId, plate, netId, mods)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbgarages:retrieveImpound', function(src, garageId, plate)
    return api.retrieveImpound(src, garageId, plate)
end, { rateLimit = { max = 5, window = 10000 } })

-- --- native exports ---------------------------------------------------------

---Impounds a plate. Wrapper over Core.garage.impound that clamps the fee and
---tells the OWNER, which is the part a police resource would otherwise have to
---reimplement (and the part players notice when it is missing).
---
---Deliberately does not charge anything: the fee is recorded on the row and
---collected at the lot by api.retrieveImpound, which is where the player is
---standing when they can actually afford it.
---@param plate any
---@param fee any
---@param impoundLot string|nil
---@return boolean ok, string|nil error
local function impound(plate, fee, impoundLot)
    local normalised, plateErr = Garages.shared.normalisePlate(plate)
    if not normalised then return false, plateErr end

    local amount = tonumber(fee) or tonumber(Config.impound.defaultFee) or 0
    local ceiling = tonumber(Config.impound.maxFee) or amount
    if amount < 0 then amount = 0 end
    if amount > ceiling then amount = ceiling end

    local ok, err = pcall(function()
        return exports.qbcore:impound(normalised, amount, impoundLot or 'impoundlot')
    end)
    if not ok then return false, 'qbcore garage persistence unavailable' end
    if err == false then return false, 'failed to impound vehicle' end

    return true
end

exports('impound', impound)

---Whether `src`'s character owns `plate`. The single question a job resource
---actually asks a garage ("is this their car?"), answered without handing out
---the row -- which carries the owner citizenid and last known position.
---@param src integer
---@param plate any
---@return boolean
exports('isOwner', function(src, plate)
    local citizenid = A.citizenid(src)
    if not citizenid then return false end
    return A.ownedRow(citizenid, plate) ~= nil
end)

---Config snapshot for tooling and for the legacy compat layer: id, label, type
---and coords per garage. Returns a fresh table each call so a consumer cannot
---mutate this resource's live config through the reference.
---@return table
exports('getGarages', function()
    local out = {}
    for id, garage in pairs(Config.garages) do
        out[id] = {
            id = id,
            label = garage.label,
            type = garage.type,
            job = garage.job,
            gang = garage.gang,
            coords = { x = garage.coords.x, y = garage.coords.y, z = garage.coords.z },
        }
    end
    return out
end)
