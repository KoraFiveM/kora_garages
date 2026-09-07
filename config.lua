Config = {}

Config.debug = false -- draws the qbtarget zone outlines and enables /garagedebug

-- --- interaction ------------------------------------------------------------
--
-- One shared gate for every garage: the numbers here are what the SERVER
-- re-checks on every action, not just what the client uses to draw a zone. A
-- generous zone size with a tight `distance` is deliberate -- the box only has
-- to cover the parking apron so the prompt appears, while the distance is what
-- actually authorises the action.
Config.interaction = {
    -- `target` uses qbtarget's aim/Alt flow. `interact` opens qblib's nearby
    -- selector when the player enters the box, with E confirming the option.
    mode = 'target',
    zoneSize = { x = 6.0, y = 6.0, z = 3.0 }, -- box covering the apron; per-garage `size` overrides it
    distance = 4.0,                           -- metres; the server refuses any action beyond this from the garage point
    -- Metres a stored vehicle may be from the garage point. Wider than
    -- `distance` on purpose: a player standing at the marker can legitimately
    -- have parked the car a few spaces away, and forcing them to leave it on
    -- top of the marker makes a busy garage unusable.
    storeDistance = 12.0,
    -- Refuse an action when the player and the garage are in different routing
    -- buckets. Fails CLOSED when the natives are missing rather than skipping
    -- the check -- a garage that silently stopped enforcing bucket separation
    -- would let an instanced player pull vehicles into someone else's world.
    requireSameBucket = true,
}

-- --- garage types -----------------------------------------------------------
--
-- A type is a POLICY, not a location: it decides who may use a garage, whether
-- the vehicles listed there are the ones garaged or the ones impounded, and
-- which pause-map legend label its blips use.
--
-- `blipLabel` is shared across every garage of a type on purpose. It is also
-- used as the named legend category, so matching locations collapse beneath
-- one heading. The label therefore lives on the type, not the individual
-- garage, keeping map terms consistent.
Config.garageTypes = {
    public = {
        label = 'Public Garage',
        blipLabel = 'Garage',
        blipSprite = 357,
        blipColor = 3,
        -- Lists vehicles whose row is `garaged`; `impounded` ones are hidden
        -- here so a player is not offered a car the impound lot is holding.
        shows = 'garaged',
    },
    private = {
        label = 'Private Garage',
        blipLabel = 'Garage',      -- same heading as public: to a player both are just "a garage"
        blipSprite = 357,
        blipColor = 3,
        shows = 'garaged',
    },
    job = {
        label = 'Job Garage',
        blipLabel = 'Job Garage',
        blipSprite = 357,
        blipColor = 38,
        shows = 'garaged',
        -- Only shown/usable by the garage's own `job`, and only on duty. The
        -- duty check is what stops an off-duty officer parking the fleet.
        requireDuty = true,
    },
    gang = {
        label = 'Gang Garage',
        blipLabel = 'Gang Garage',
        blipSprite = 357,
        blipColor = 6,
        shows = 'garaged',
        -- Gangs have no duty concept in qbcore, so membership is the whole gate.
        requireDuty = false,
    },
    impound = {
        label = 'Impound Lot',
        blipLabel = 'Impound Lot',
        blipSprite = 67,
        blipColor = 5,
        -- The inverse listing: an impound lot shows ONLY impounded vehicles,
        -- which is what makes "where did my car go" answerable in one place.
        shows = 'impounded',
        -- Storing at an impound lot is meaningless (the row is already held by
        -- the lot) and would silently clear the impound without charging.
        allowStore = false,
    },
}

-- --- garages ----------------------------------------------------------------
--
-- Keyed by id, never an array: the id is the only thing the browser sends and
-- the server re-resolves it against this table, so it has to be a stable
-- string rather than a list position that shifts when a garage is added.
--
-- `spawns` is a LIST even where one point would do. A single spawn point puts
-- the second player to retrieve a car inside the first one's bumper, and FiveM
-- resolves that by launching one of them into the air; the server walks the list
-- for a point with nothing parked on it.
--
-- `categories` is an allow-list of qbcore shared-vehicle categories (the
-- `category` field in qbcore/shared/vehicles.lua), NOT GTA vehicle classes.
-- Class comes from GetVehicleClass, which needs a live entity -- and on take-out
-- there is no entity yet, so the check would only ever run on store and a
-- boat-only garage could still be used to retrieve a jet. The category is on the
-- DB row's model, so the same rule applies in both directions. `false` (or an
-- omitted field) accepts everything.
Config.garages = {
    legionsquare = {
        type = 'public',
        label = 'Legion Square Parking',
        coords = { x = 215.9, y = -809.4, z = 30.7 },
        spawns = {
            { x = 222.0, y = -804.0, z = 30.6, w = 159.0 },
            { x = 225.0, y = -807.5, z = 30.6, w = 159.0 },
            { x = 226.5, y = -811.5, z = 30.6, w = 159.0 },
        },
        categories = false,
        bucket = 0, -- explicit, so a missing bucket reads as a config error rather than "any bucket"
    },
    motel = {
        type = 'public',
        label = 'Pink Cage Motel Parking',
        coords = { x = 273.4, y = -343.2, z = 45.1 },
        spawns = {
            { x = 271.0, y = -334.8, z = 44.9, w = 159.0 },
            { x = 275.5, y = -338.6, z = 44.9, w = 159.0 },
        },
        categories = false,
        bucket = 0,
    },
    sandyshores = {
        type = 'public',
        label = 'Sandy Shores Parking',
        coords = { x = 1728.8, y = 3712.0, z = 34.2 },
        spawns = {
            { x = 1735.0, y = 3714.3, z = 34.1, w = 22.0 },
            { x = 1738.0, y = 3717.0, z = 34.1, w = 22.0 },
        },
        categories = false,
        bucket = 0,
    },
    paletoair = {
        type = 'private',
        label = 'Paleto Bay Hangar',
        coords = { x = 1734.2, y = 3305.4, z = 41.2 },
        spawns = {
            { x = 1729.0, y = 3299.0, z = 41.1, w = 106.0 },
        },
        -- A hangar is the clearest case for the allow-list: without it a player
        -- could park a Sultan in it and later retrieve it from a runway.
        categories = { 'planes', 'helicopters' },
        bucket = 0,
    },
    missionrow = {
        type = 'job',
        label = 'Mission Row Motor Pool',
        job = 'police',
        coords = { x = 454.6, y = -1017.4, z = 28.4 },
        spawns = {
            { x = 446.5, y = -1019.5, z = 27.7, w = 90.0 },
            { x = 446.5, y = -1024.5, z = 27.7, w = 90.0 },
        },
        categories = { 'emergency', 'sedans', 'suvs' },
        bucket = 0,
    },
    ballas = {
        type = 'gang',
        label = 'Forum Drive Lockup',
        gang = 'ballas',
        coords = { x = 85.0, y = -1959.7, z = 21.1 },
        spawns = {
            { x = 92.3, y = -1958.5, z = 20.7, w = 320.0 },
        },
        categories = false,
        bucket = 0,
    },
    impoundlot = {
        type = 'impound',
        label = 'Davis Impound Lot',
        coords = { x = 409.9, y = -1622.9, z = 29.3 },
        spawns = {
            { x = 403.5, y = -1627.5, z = 29.2, w = 230.0 },
            { x = 406.0, y = -1631.0, z = 29.2, w = 230.0 },
        },
        categories = false,
        bucket = 0,
    },
}

-- --- impound ----------------------------------------------------------------
Config.impound = {
    -- Charged when the impounding resource set no `impound_fee` on the row.
    -- Zero would make every impound free, which is the one outcome nobody
    -- configuring an impound lot wants by accident.
    defaultFee = 500,
    account = 'bank',  -- qbcore money account; 'cash' is the alternative
    maxFee = 100000,   -- a sanity ceiling: a bad impound writer cannot bankrupt a player
    reason = 'impound-fee', -- shows up in qbcore's money log
}

-- --- spawning ---------------------------------------------------------------
Config.spawn = {
    -- Metres a spawn point must be clear of other vehicles to be used. Roughly
    -- one car length: tighter than this and two saloons overlap, wider and a
    -- three-bay garage reports itself full with one car parked.
    clearance = 3.0,
    -- Put the retrieving player in the driver's seat. Off by default because a
    -- garage that teleports you into a plane you asked to *look at* is a
    -- surprise; servers that want the classic qb-garages feel turn it on.
    warpIntoVehicle = false,
    -- Applied by the CLIENT after spawn, from the mods blob the SERVER read out
    -- of the DB row -- qbcore's garage module stores mods as opaque JSON and
    -- deliberately does not apply them (that is ~50 SetVehicleMod calls of
    -- presentation work). This is the presentation layer, so it does.
    applyMods = true,
}

-- --- mods -------------------------------------------------------------------
--
-- The ONE thing a garage cannot read server-side. fuel, engine and body health
-- are all re-read off the networked entity by the server on store; a vehicle's
-- MOD state is only reachable through client natives (GetVehicleMod and
-- friends), so the client's QB.vehicle.getProperties blob is the only possible
-- source and it arrives over the wire like any other client claim.
--
-- Which means it cannot be trusted, and this is the allow-list that makes it
-- harmless: only COSMETIC fields survive `Garages.api.filterMods`. A client that
-- injects `modEngine = 3` gets it dropped on the floor, because a garage must
-- never be a free performance-upgrade shop -- that is a tuner's job and a tuner
-- charges for it. Colours, wheels, liveries and extras cost nothing to fake and
-- are exactly what a player expects a garage to remember.
--
-- qbcore's garage module stores mods as opaque JSON and deliberately never
-- applies them; qbgarages is the presentation layer that does, which is what
-- makes the distinction load-bearing rather than academic.
Config.mods = {
    -- Keys copied verbatim from qblib's QB.vehicle.getProperties output.
    cosmetic = {
        'plateIndex', 'color1', 'color2', 'pearlescentColor', 'dashboardColor',
        'wheelColor', 'wheels', 'wheelSize', 'wheelWidth', 'windowTint',
        'neonEnabled', 'neonColor', 'interiorColor', 'extras', 'tyreSmokeColor',
        'xenonColor', 'modXenon', 'modFrontWheels', 'modBackWheels',
        'modCustomTiresF', 'modCustomTiresR', 'modLivery', 'liveryRoof',
        'modSpoilers', 'modFrontBumper', 'modRearBumper', 'modSideSkirt',
        'modExhaust', 'modFrame', 'modGrille', 'modHood', 'modFender',
        'modRightFender', 'modRoof', 'modHorns', 'modPlateHolder',
        'modVanityPlate', 'modTrimA', 'modOrnaments', 'modDashboard', 'modDial',
        'modDoorSpeaker', 'modSeats', 'modSteeringWheel', 'modShifterLeavers',
        'modAPlate', 'modSpeakers', 'modTrunk', 'modHydrolic', 'modEngineBlock',
        'modAirFilter', 'modStruts', 'modArchCover', 'modAerials', 'modTrimB',
        'modTank', 'modWindows',
    },
    -- Deliberately ABSENT from the list above and named here so nobody
    -- "helpfully" adds them back: modEngine, modBrakes, modTransmission,
    -- modSuspension, modArmor, modTurbo. Also absent: plate, model,
    -- engineHealth, bodyHealth, fuelLevel -- the server owns all five, and
    -- letting a mods blob carry them would reintroduce exactly the
    -- client-supplied condition value this design refuses.
    entryCap = 80, -- keys accepted before the blob is treated as abuse and dropped
}

-- --- listing ----------------------------------------------------------------
Config.listing = {
    -- Vehicles shown in one garage panel. A player with a hundred cars is a
    -- server-economy problem, not a reason to serialise a hundred rows into the
    -- NUI on every open.
    max = 50,
    -- engine_health/body_health are stored on qbcore's 0..1000 scale. The NUI
    -- shows percentages, and doing that conversion server-side means the
    -- browser never has to know the storage scale.
    healthScale = 1000.0,
}

-- --- ui ---------------------------------------------------------------------
Config.ui = {
    -- `false` means follow qbtheme's configured primary. Set a '#RRGGBB' here
    -- only to make garages deliberately differ.
    accent = false,
}

-- --- compat -----------------------------------------------------------------
Config.compat = {
    -- The real qb-garages `qb-garage:*` callbacks and net events. On by
    -- default: the whole point of `provide 'qb-garages'` in the manifest is
    -- that an unmodified third-party consumer keeps working.
    legacy = true,
    -- Legacy `qb-garage:server:updateVehicleState` carries a state INTEGER and
    -- a plate from the client, with no ownership proof of its own. Honouring it
    -- as a raw write would be a free "un-impound any plate" primitive, so it is
    -- funnelled through the same ownership/distance checks as the native path
    -- and only the garage-in / garage-out transitions are accepted.
    strictLegacyState = true,
}

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
