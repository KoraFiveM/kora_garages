-- One configurable interaction zone per garage. `target` keeps the qbtarget
-- aim/Alt flow; `interact` uses qblib's nearby selector and E to confirm.
--
-- `canInteract` is a UX convenience ONLY. It reads the local mirror of
-- PlayerData so an officer's motor pool does not prompt every passing civilian;
-- the real gate is Garages.access.entitled, re-read from qbcore server-side on
-- every single action. Nothing is authorised by anything in this file.

local mode = Config.interaction.mode or 'target'
assert(mode == 'target' or mode == 'interact',
    "Config.interaction.mode must be 'target' or 'interact'")

local targetZones = {}
local interactZones = {}

---@return table|nil
local function localJob()
    local ok, job = pcall(function() return exports.qbcore:getJob() end)
    return ok and type(job) == 'table' and job or nil
end

---@return table|nil
local function localGang()
    local ok, gang = pcall(function() return exports.qbcore:getGang() end)
    return ok and type(gang) == 'table' and gang or nil
end

---@param garage table
---@return boolean
local function mayPrompt(garage)
    local policy = Config.garageTypes[garage.type]
    if not policy then return false end

    if garage.job then
        local job = localJob()
        if not job or job.name ~= garage.job then return false end
        -- qbcore's spelling is `onduty`, lowercase d -- `onDuty` reads nil and
        -- would hide the prompt from every officer who is actually on duty.
        if policy.requireDuty and not job.onduty then return false end
    end

    if garage.gang then
        local gang = localGang()
        if not gang or gang.name ~= garage.gang then return false end
    end

    return true
end

---@param id string
---@param garage table
---@return table
local function optionFor(id, garage)
    local policy = Config.garageTypes[garage.type]
    local function openGarage()
        -- The garage ID is a config key resolved on the SERVER. It travels as
        -- intent only; an invented id is refused as an unknown garage.
        Garages.ui.open(id)
    end

    return {
        label = policy and policy.shows == 'impounded'
            and ('Collect from %s'):format(garage.label)
            or ('Open %s'):format(garage.label),
        icon = policy and policy.shows == 'impounded' and 'car-front' or 'warehouse',
        canInteract = function()
            return mayPrompt(garage)
        end,
        -- qbtarget dispatches `onSelect`; QB.interact dispatches `action`.
        -- Supplying the same closure under both names keeps the two providers
        -- behaviourally identical without routing through a client event.
        onSelect = openGarage,
        action = openGarage,
    }
end

local function clearTargetZones()
    for _, registrationId in pairs(targetZones) do
        pcall(function() exports.qbtarget:removeZone(registrationId) end)
    end
    targetZones = {}
end

local function clearInteractZones()
    for _, zoneName in pairs(interactZones) do
        pcall(function() QB.interact.removeZone(zoneName) end)
    end
    interactZones = {}
end

local function registerTargetZones()
    -- Re-registration is intentionally idempotent. Without removing the old
    -- handles first, every repeat adds another identical option at Legion (and
    -- eventually at every other garage).
    clearTargetZones()

    for id, garage in pairs(Config.garages) do
        targetZones[id] = exports.qbtarget:addBoxZone({
            coords = garage.coords,
            size = garage.size or Config.interaction.zoneSize,
            rotation = garage.heading or 0.0,
            debug = Config.debug,
            -- The prompt reach, not the authorisation reach. The server's own
            -- Config.interaction.distance is what decides whether an action is
            -- allowed, and it is deliberately the tighter of the two.
            distance = tonumber(garage.distance) or Config.interaction.distance,
            options = { optionFor(id, garage) },
        })
    end
end

local function registerInteractZones()
    clearInteractZones()

    for id, garage in pairs(Config.garages) do
        local size = garage.size or Config.interaction.zoneSize
        local zoneName = ('qbgarages:%s'):format(id)

        QB.interact.addBoxZone(zoneName, garage.coords, {
            x = size.x,
            y = size.y,
            z = size.z,
            w = garage.heading or size.w or 0.0,
        }, { optionFor(id, garage) }, Config.debug)

        interactZones[id] = zoneName
    end
end

if mode == 'target' then
    registerTargetZones()
else
    registerInteractZones()
end

-- A qbtarget stop destroys its registrations itself. Forget those stale ids so
-- they can never collide with ids allocated by the newly-started instance.
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'qbtarget' then targetZones = {} end
end)

-- qbtarget restarting drops every registration it was holding, including ours.
-- Without this the garages silently stop prompting until this resource is
-- restarted too -- the same re-registration hook qbpolice and qbclothing use.
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'qbtarget' or mode ~= 'target' then return end
    registerTargetZones()
end)
