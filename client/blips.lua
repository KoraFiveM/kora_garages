-- Map blips, one per garage.
--
-- THE LEGEND GROUPING IS THE POINT. Seven garages would otherwise be seven
-- identical rows in the pause-map legend. `category = 11` is the grouped
-- category: the game collapses every blip in it under one heading taken from the
-- blips' own NAME -- so the heading comes from the garage TYPE
-- (Config.garageTypes[type].blipLabel) and is deliberately identical across
-- every garage of that type. A per-garage label would split the group and undo
-- the whole mechanism. See qblib/modules/blips/docs.md.
--
-- The per-garage label still reaches the player: it is the qbtarget prompt they
-- read when they walk up to it, which is where a specific name is actually
-- useful.

local created = {}

local function clearBlips()
    for _, blip in ipairs(created) do QB.blips.remove(blip) end
    created = {}
end

local function createBlips()
    clearBlips()

    for _, garage in pairs(Config.garages) do
        local policy = Config.garageTypes[garage.type]
        -- A garage with an unknown type gets no blip rather than a blip under
        -- some other type's heading: an unlabelled blip in category 11 would
        -- join whichever group the game happens to put it in.
        if policy then
            local blip = QB.blips.create(garage.coords, {
                sprite = policy.blipSprite,
                color = policy.blipColor,
                scale = 0.8,
                shortRange = true,
                label = policy.blipLabel, -- identical across the type: this IS the heading
                category = 11,
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
