local root = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "../"

local plates = { [5] = "ZZZ 999", [7] = "AAA 111" }
local nearbyCall, storeArgs
local appOnAction, exported = nil, {}

local function stub(name)
    return setmetatable({}, { __index = function() return function() end end, __name = name })
end

local env = {
    Config = {
        debug = false,
        spawn = { applyMods = false, warpIntoVehicle = false },
        interaction = { storeDistance = 12.0, zoneSize = { x = 2, y = 2, z = 2 } },
        impound = { defaultFee = 0 },
        ui = {},
        houseGarages = { blip = false },
        garageTypes = { public = { label = "Public", blipSprite = 357, blipColor = 3 } },
        garages = { g1 = { type = "public", label = "G1", coords = { x = 0, y = 0, z = 0 } } },
    },
    Kora = {
        notify = { send = function() end },
        interact = { addBoxZone = function() end, removeZone = function() end },
        blips = stub("blips"),
        nui = {
            registerApp = function(app) appOnAction = app.onAction end,
            openApp = function() end,
            closeApp = function() end,
        },
        vehicle = { getProperties = function() return {} end },
        world = {
            getNearbyEntities = function(entityType, coords, radius, options)
                nearbyCall = { entityType = entityType, coords = coords, radius = radius, options = options }
                return { { entity = 5, distance = 1.0 }, { entity = 7, distance = 3.0 } }
            end,
        },
        callback = {
            trigger = function(name, ...)
                if name == "qbgarages:list" then
                    return { garage = { label = "G1", type = "public" }, vehicles = { { plate = "AAA 111", model = "blista", state = "out" } } }
                elseif name == "qbgarages:store" then
                    storeArgs = { ... }
                    return true
                end
            end,
        },
    },
    exports = setmetatable({}, {
        __call = function(_, name, fn) exported[name] = fn end,
        __index = function() return { getShared = function() return nil end } end,
    }),
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    json = { decode = function() end },
    CreateThread = function(fn) fn() end,
    Wait = function() end,
    RegisterNetEvent = function() end,
    AddEventHandler = function() end,
    GetCurrentResourceName = function() return "kora_garages" end,
    GetGameTimer = function() return 0 end,
    PlayerPedId = function() return 1 end,
    GetEntityCoords = function() return { x = 1, y = 2, z = 3 } end,
    GetVehiclePedIsIn = function() return 0 end,
    GetVehicleNumberPlateText = function(entity) return plates[entity] end,
    GetVehicleFuelLevel = function() return 50 end,
    NetworkGetNetworkIdFromEntity = function(entity) return entity + 1000 end,
    TaskLeaveVehicle = function() end,
    GetGamePool = function() error("findVehicle must use Kora.world, not scan the pool itself") end,
}
setmetatable(env, { __index = _G })
assert(loadfile(root .. "client/client.lua", "t", env))()

-- openGarage -> pick the "out" vehicle -> store() -> findVehicle()
assert(exported.openGarage, "openGarage export registered")

assert(exported.openGarage("g1") == true)
assert(appOnAction, "garage app registered")
appOnAction("garage:use", { itemId = "AAA 111" })

assert(nearbyCall, "findVehicle queries Kora.world.getNearbyEntities")
assert(nearbyCall.entityType == "vehicle")
assert(nearbyCall.radius == 12.0, "uses Config.interaction.storeDistance")
assert(nearbyCall.options.includeInvisible == true, "invisible vehicles stay eligible, as with the old pool scan")
assert(storeArgs and storeArgs[1] == "g1" and storeArgs[2] == "AAA 111", "store callback fired")
assert(storeArgs[3] == 1007, "matched the nearby vehicle with the wanted plate (spaces ignored)")
print("client ok")
