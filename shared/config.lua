Config = {}

Config.debug = false -- draws qbtarget zone outlines and enables /garagedebug

Config.interaction = {
    mode = 'target',       -- 'target' or 'interact'
    zoneSize = vector3(6.0, 6.0, 3.0),
    distance = 4.0,        -- how close you must be to open a garage
    storeDistance = 12.0,  -- how close your vehicle must be to get stored
    requireSameBucket = true,
}

Config.garageTypes = {
    public = {
        label = 'Public Garage',
        blipLabel = 'Garage',
        blipSprite = 357,
        blipColor = 3,
        shows = 'garaged',
    },
    private = {
        label = 'Private Garage',
        blipLabel = 'Garage',
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
        requireDuty = true,
    },
    gang = {
        label = 'Gang Garage',
        blipLabel = 'Gang Garage',
        blipSprite = 357,
        blipColor = 6,
        shows = 'garaged',
        requireDuty = false,
    },
    impound = {
        label = 'Impound Lot',
        blipLabel = 'Impound',
        blipSprite = 67,
        blipColor = 5,
        shows = 'impounded',
        allowStore = false,
    },
}

Config.garages = {
    legionsquare = {
        type = 'public',
        label = 'Legion Square Parking',
        coords = vector4(211.52, -802.16, 30.89, 341.39),
        spawns = {
            vector4(222.0, -804.0, 30.6, 159.0),
            vector4(225.0, -807.5, 30.6, 159.0),
            vector4(226.5, -811.5, 30.6, 159.0),
        },
        bucket = 0,
    },
    motel = {
        type = 'public',
        label = 'Pink Cage Motel Parking',
        coords = vector4(273.4, -343.2, 45.1, 159.0),
        spawns = {
            vector4(271.0, -334.8, 44.9, 159.0),
            vector4(275.5, -338.6, 44.9, 159.0),
        },
        bucket = 0,
    },
    sandyshores = {
        type = 'public',
        label = 'Sandy Shores Parking',
        coords = vector4(1728.8, 3712.0, 34.2, 22.0),
        spawns = {
            vector4(1735.0, 3714.3, 34.1, 22.0),
            vector4(1738.0, 3717.0, 34.1, 22.0),
        },
        bucket = 0,
    },
    missionrow = {
        type = 'job',
        job = 'police',
        label = 'Mission Row Motor Pool',
        coords = vector4(456.01, -1017.22, 28.40, 89.70),
        spawns = {
            vector4(446.5, -1019.5, 27.7, 90.0),
            vector4(446.5, -1024.5, 27.7, 90.0),
        },
        categories = { 'emergency', 'sedans', 'suvs' },
        bucket = 0,
    },
    ballas = {
        type = 'gang',
        gang = 'ballas',
        label = 'Forum Drive Lockup',
        coords = vector4(85.0, -1959.7, 21.1, 320.0),
        spawns = {
            vector4(92.3, -1958.5, 20.7, 320.0),
        },
        bucket = 0,
    },
    impoundlot = {
        type = 'impound',
        label = 'Davis Impound Lot',
        coords = vector4(409.9, -1622.9, 29.3, 230.0),
        spawns = {
            vector4(403.5, -1627.5, 29.2, 230.0),
            vector4(406.0, -1631.0, 29.2, 230.0),
        },
        bucket = 0,
    },
}

-- Private lots, one per row in `houselocations` that has a garage set.
-- See server/houses.lua for the query and vector4 parsing.
Config.houseGarages = {
    query = 'SELECT * FROM houselocations WHERE garage IS NOT NULL',
    bucket = 0,      -- routing bucket house garages sit in
    blip = false,    -- one blip per house garage would flood the map
}

Config.impound = {
    defaultFee = 500,
    maxFee = 100000, -- ceiling so a bad impound write can't bankrupt someone
    account = 'bank',
    reason = 'impound-fee',
}

Config.spawn = {
    clearance = 3.0,          -- metres a spawn point must be clear to be used
    warpIntoVehicle = false,  -- put the player straight into the driver's seat
    applyMods = true,         -- reapply the stored cosmetic mods on take-out
}

-- Only cosmetic fields survive into a stored vehicle's mods. Performance
-- mods (engine, brakes, turbo...) are never trusted from the client.
Config.mods = {
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
    entryCap = 80, -- more keys than this and the whole blob is dropped
}

Config.listing = {
    max = 50,             -- vehicles shown per garage panel
    healthScale = 1000.0, -- qbcore stores engine/body health on a 0-1000 scale
}

Config.ui = {
    accent = false, -- '#RRGGBB' to override qbtheme's colour, or false to follow it
}

if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
