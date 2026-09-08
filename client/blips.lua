-- Map blips, one per garage. The type label is its named category, so matching
-- locations share one pause-map legend heading. The individual blip label is
-- the location name, however: giving every public garage the label "Garage"
-- leaves the legend full of visually identical entries.

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
                category = policy.blipLabel,
                name = garage.label,
                info = {
                    title = garage.label,
                    rows = {
                        { kind = 'name', label = 'Service', value = policy.label },
                        { kind = 'wrappedText', value = policy.shows == 'impounded'
                            and 'Retrieve vehicles held by impound.' or 'Access and store eligible vehicles here.' },
                    },
                },
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
