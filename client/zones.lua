-- One qbtarget box zone per garage.
--
-- NOTE THE SIGNATURE. The ZONE apis take a SINGLE options object with an
-- `options` key inside it -- `addBoxZone({ coords = .., size = .., options = {
-- .. } })` -- unlike addEntity/addModel, which take the option array
-- positionally as their second argument. Passing the array positionally here
-- registers a zone with no options at all: the box exists, nothing ever
-- prompts, and there is no error to find.
--
-- `canInteract` below is a UX convenience ONLY. It reads the local mirror of
-- PlayerData so an officer's motor pool does not prompt every passing civilian;
-- the real gate is Garages.access.entitled, re-read from qbcore server-side on
-- every single action. Nothing is authorised by anything in this file.

local registered = {}

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

local function registerZones()
    for id, garage in pairs(Config.garages) do
        local policy = Config.garageTypes[garage.type]

        registered[id] = exports.qbtarget:addBoxZone({
            coords = garage.coords,
            size = garage.size or Config.interaction.zoneSize,
            heading = garage.heading or 0.0,
            debug = Config.debug,
            -- The prompt reach, not the authorisation reach. The server's own
            -- Config.interaction.distance is what decides whether an action is
            -- allowed, and it is deliberately the tighter of the two.
            distance = tonumber(garage.distance) or Config.interaction.distance,
            options = {
                {
                    label = policy and policy.shows == 'impounded'
                        and ('Collect from %s'):format(garage.label)
                        or ('Open %s'):format(garage.label),
                    icon = policy and policy.shows == 'impounded' and 'car-front' or 'warehouse',
                    canInteract = function()
                        return mayPrompt(garage)
                    end,
                    onSelect = function()
                        -- The garage ID is a config key resolved on the SERVER.
                        -- It travels as a string because it is intent; the server
                        -- looks it up in its own Config.garages, so a client
                        -- inventing an id gets 'unknown garage'.
                        Garages.ui.open(id)
                    end,
                },
            },
        })
    end
end

registerZones()

-- qbtarget restarting drops every registration it was holding, including ours.
-- Without this the garages silently stop prompting until this resource is
-- restarted too -- the same re-registration hook qbpolice and qbclothing use.
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'qbtarget' then return end
    registered = {}
    registerZones()
end)
