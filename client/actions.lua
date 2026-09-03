-- Take out, store, and impound release, from the client's side.
--
-- What this file is allowed to do is narrow on purpose: find the entity the
-- player means, read its network id, ask the server, and then apply the
-- presentation work (mods, seating) to whatever the server created. It does not
-- decide anything. Every refusal below is the SERVER's own message, shown
-- verbatim rather than reworded -- a player who is told "too far from the
-- garage" can act on it; one told "something went wrong" cannot.

Garages = Garages or {}
Garages.actions = {}

local Actions = Garages.actions

---@param message string
---@param variant string|nil
local function notify(message, variant)
    QB.notify.send({ title = 'Garage', message = message, type = variant or 'error' })
end

---A timed-out QB.callback.trigger returns NO values at all -- so `nil` means
---"the server never answered", which is NOT a refusal and must never be
---reported as one. Only an explicit `false` is a refusal.
---@param result any
---@param err any
---@return boolean answered
local function answered(result, err)
    if result == nil and err == nil then
        notify('The garage did not answer. Try again.')
        return false
    end
    return true
end

-- --- take out ---------------------------------------------------------------

---Waits for a server-created entity to stream in to this client.
---
---The server has already created and networked the vehicle by the time the
---callback returns, but the entity does not exist LOCALLY until the client is
---told about it -- reading it immediately yields 0, and every SetVehicleMod
---against handle 0 is silently dropped, which is why a retrieved car sometimes
---came back the wrong colour.
---@param netId integer
---@param timeout integer|nil ms
---@return integer|nil entity
local function awaitEntity(netId, timeout)
    local deadline = GetGameTimer() + (timeout or 5000)

    while GetGameTimer() < deadline do
        if NetworkDoesNetworkIdExist(netId) then
            local entity = NetworkGetEntityFromNetworkId(netId)
            if entity ~= 0 and DoesEntityExist(entity) then return entity end
        end
        Wait(50)
    end

    return nil
end

---Applies the SERVER's stored mods blob and (optionally) seats the player.
---@param entity integer
---@param result table
local function dress(entity, result)
    if Config.spawn.applyMods and type(result.mods) == 'table' then
        -- Every key in here passed the server's cosmetic allow-list on the way
        -- IN (Garages.api.filterMods), so applying it wholesale cannot install a
        -- performance upgrade -- see the Config.mods comment.
        pcall(function() QB.vehicle.setProperties(entity, result.mods) end)
    end

    if result.warp then
        SetPedIntoVehicle(PlayerPedId(), entity, -1)
    end
end

---@param plate any Whatever the browser sent. Forwarded as intent only.
function Actions.takeOut(plate)
    local garageId = Garages.state.garageId()
    if not garageId or type(plate) ~= 'string' then return end
    if Garages.state.data.busy then return end

    Garages.state.setBusy(true)
    Garages.ui.render()

    CreateThread(function()
        local result, err = QB.callback.trigger('qbgarages:takeOut', garageId, plate)

        Garages.state.setBusy(false)

        if not answered(result, err) then return Garages.ui.render() end
        if not result or result == false then
            Garages.state.setError(err or 'You cannot take that out.')
            Garages.ui.render()
            return notify(err or 'You cannot take that out.')
        end

        -- Closed on success, not left open: the vehicle is now in the world and
        -- the listing the panel is showing is already wrong.
        Garages.ui.close()

        local entity = awaitEntity(result.netId)
        if entity then dress(entity, result) end

        notify(('%s is ready.'):format(result.plate), 'success')
    end)
end

-- --- store ------------------------------------------------------------------

---The entity the player means when they press Store on `plate`.
---
---Preference order: the vehicle they are sitting in, then the nearest vehicle
---carrying that plate. Both are checked against the plate so pressing Store on
---one car while sitting in another cannot store the wrong one -- and the server
---re-checks the same thing against the entity it resolves from the network id,
---so this is convenience, not the gate.
---@param plate string
---@return integer|nil entity, string|nil error
local function vehicleFor(plate)
    local ped = PlayerPedId()

    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 and DoesEntityExist(current) then
        if QB.vehicle.plate(current):gsub('%s+', ''):upper() == plate then return current end
    end

    -- QB.world.getNearbyEntities reads the live entity pool and returns matches
    -- nearest-first, so the first plate match is also the closest one. Written
    -- against that rather than a hand-rolled GetGamePool loop: the pool call and
    -- its distance sort are already implemented once, in qblib.
    local radius = tonumber(Config.interaction.storeDistance) or 12.0
    local ok, nearby = pcall(function()
        return QB.world.getNearbyEntities('vehicle', GetEntityCoords(ped), radius)
    end)
    if not ok or type(nearby) ~= 'table' then return nil, 'that vehicle is not here' end

    for _, match in ipairs(nearby) do
        if DoesEntityExist(match.entity) then
            local read, matches = pcall(function()
                return QB.vehicle.plate(match.entity):gsub('%s+', ''):upper() == plate
            end)
            if read and matches then return match.entity end
        end
    end

    return nil, 'that vehicle is not here'
end

---Gets the player out of a vehicle before it is deleted underneath them.
---
---The SERVER deletes the entity (qbcore's storeVehicle deliberately leaves the
---handle to the caller), and deleting a vehicle with a ped inside leaves that
---ped in a broken seated state for a moment. Bounded so a player wedged against
---geometry is not stuck in this loop forever -- the store still goes ahead.
---@param entity integer
local function stepOut(entity)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= entity then return end

    TaskLeaveVehicle(ped, entity, 0)

    local deadline = GetGameTimer() + 3000
    while GetGameTimer() < deadline and GetVehiclePedIsIn(ped, false) == entity do
        Wait(100)
    end
end

---@param plate any Intent only.
function Actions.store(plate)
    local garageId = Garages.state.garageId()
    if not garageId or type(plate) ~= 'string' then return end
    if Garages.state.data.busy then return end

    local entity, findErr = vehicleFor(plate)
    if not entity then
        Garages.state.setError(findErr)
        Garages.ui.render()
        return notify(findErr or 'That vehicle is not here.')
    end

    Garages.state.setBusy(true)
    Garages.ui.render()

    CreateThread(function()
        stepOut(entity)

        -- The mods blob is the ONE thing the server cannot read for itself: mod
        -- state lives behind client-only natives. It is sent as an untrusted
        -- claim and filtered to the cosmetic allow-list server-side; the
        -- condition (fuel/engine/body) is deliberately NOT sent, because the
        -- server reads all three off the networked entity itself.
        local mods
        local ok, properties = pcall(function() return QB.vehicle.getProperties(entity) end)
        if ok and type(properties) == 'table' then mods = properties end

        local netId = NetworkGetNetworkIdFromEntity(entity)
        local stored, err = QB.callback.trigger('qbgarages:store', garageId, plate, netId, mods)

        Garages.state.setBusy(false)

        if not answered(stored, err) then return Garages.ui.render() end
        if not stored then
            Garages.state.setError(err or 'You cannot store that here.')
            Garages.ui.render()
            return notify(err or 'You cannot store that here.')
        end

        notify(('%s is parked.'):format(plate), 'success')
        Garages.ui.refresh()
    end)
end

-- --- impound ----------------------------------------------------------------

---@param plate any Intent only.
function Actions.retrieveImpound(plate)
    local garageId = Garages.state.garageId()
    if not garageId or type(plate) ~= 'string' then return end
    if Garages.state.data.busy then return end

    Garages.state.setBusy(true)
    Garages.ui.render()

    CreateThread(function()
        local result, err = QB.callback.trigger('qbgarages:retrieveImpound', garageId, plate)

        Garages.state.setBusy(false)

        if not answered(result, err) then return Garages.ui.render() end
        if not result or result == false then
            Garages.state.setError(err or 'You cannot release that vehicle.')
            Garages.ui.render()
            return notify(err or 'You cannot release that vehicle.')
        end

        Garages.ui.close()

        local entity = awaitEntity(result.netId)
        if entity then dress(entity, result) end

        notify(('Released %s for $%d.'):format(result.plate, result.fee or 0), 'success')
    end)
end
