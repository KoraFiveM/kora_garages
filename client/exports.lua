-- Client entry points.
--
-- These exist so a housing resource can open its own apartment garage, or a
-- keybind resource can close the panel, without duplicating the NUI focus
-- handling. They are entry points, not authority: `openGarage` still has to get
-- past the server's listing gate, so an external caller passing a garage the
-- player is nowhere near simply gets a refusal toast.

---Opens the panel for a configured garage id.
---@param garageId string
---@return boolean accepted Whether the id exists at all; the server still decides the rest.
exports('openGarage', function(garageId)
    if type(garageId) ~= 'string' or not Config.garages[garageId] then return false end
    Garages.ui.open(garageId)
    return true
end)

exports('closeGarage', function()
    Garages.ui.close()
end)

---@return boolean
exports('isGarageOpen', function()
    return Garages.state.isOpen()
end)

-- Legacy inbound. Real qb-garages fires this from its own client code when a
-- player picks a vehicle out of its menu, so a third-party menu replacement
-- still reaches a working take-out here. The payload's own coordinates and
-- vehicle record are IGNORED -- only the plate is read, and only as intent.
RegisterNetEvent('qb-garage:client:takeOutGarage', function(data)
    local plate = type(data) == 'table' and (data.plate or (type(data.vehicle) == 'table' and data.vehicle.plate)) or data
    if type(plate) ~= 'string' then return end

    -- Requires an open panel, because that is what established which garage the
    -- player is standing at -- and the server re-checks that garage's distance
    -- anyway. A take-out with no garage context has nowhere to spawn.
    if not Garages.state.isOpen() then return end
    Garages.actions.takeOut(plate:gsub('%s+', ''):upper())
end)

-- Development aid, self-disabling unless Config.debug is on: prints every
-- garage's id, type and distance from the player, which is the one thing you
-- need when a zone is not prompting and you cannot tell whether the problem is
-- the position or the policy.
if Config.debug then
    RegisterCommand('garagedebug', function()
        local coords = GetEntityCoords(PlayerPedId())
        for id, garage in pairs(Config.garages) do
            print(('[qbgarages] %-14s %-8s %.1fm'):format(id, garage.type, #(coords - vector3(garage.coords.x, garage.coords.y, garage.coords.z))))
        end
    end, false)
end
