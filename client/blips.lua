-- Map blips, one per garage. Category 2 lists each service label in the
-- pause-map legend rather than placing every garage in GTA's built-in "Owned
-- Property" category (11). Type labels make the entries clear: "Garage", "Job
-- Garage", and "Impound Lot".

local created = {}

local function clearBlips()
    for _, blip in ipairs(created) do QB.blips.remove(blip) end
    created = {}
end

local function createBlips()
    clearBlips()

    for _, garage in pairs(Config.garages) do
        local policy = Config.garageTypes[garage.type]
        -- A garage with an unknown type gets no blip rather than an unlabelled
        -- marker that players cannot identify in the legend.
        if policy then
            local blip = QB.blips.create(garage.coords, {
                sprite = policy.blipSprite,
                color = policy.blipColor,
                scale = 0.8,
                shortRange = true,
                label = policy.blipLabel,
                category = 2,
            })
            if blip then created[#created + 1] = blip end
        end
    end
end

-- Deferred to the login gate rather than run at script load. Blips created
-- before the player exists briefly attach to nothing, and on a character switch
-- the set is rebuilt so a job/gang garage's blip follows the new character.
-- qbcore delivers this legacy lifecycle signal with TriggerClientEvent, so it
-- must be registered as a network event rather than a local-only handler.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', createBlips)
AddEventHandler('qbcore:client:playerLoaded', createBlips)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- A live restart of this resource happens while the player is already
    -- logged in, so the load event above will never fire again for them.
    createBlips()
end)
