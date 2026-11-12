local root = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "../"

local function run(markers)
    local zones, threads, draws, removed = {}, 0, 0, 0
    local env = {
        Config = {
            debug = false,
            interaction = { zoneSize = { x = 2, y = 2, z = 2 } },
            houseGarages = { blip = false },
            markers = markers,
            garageTypes = { public = { label = "Public" } },
            garages = {
                g1 = { type = "public", label = "G1", coords = { x = 0, y = 0, z = 0 } },
                h1 = { type = "public", label = "H1", property = true, coords = { x = 5, y = 5, z = 5 } },
            },
        },
        Kora = {
            interact = { addBoxZone = function() end, removeZone = function() end },
            blips = setmetatable({}, { __index = function() return function() end end }),
            callback = { trigger = function() end },
            zones = {
                sphere = function(opts)
                    local zone = { opts = opts }
                    zone.remove = function() removed = removed + 1 end
                    zones[#zones + 1] = zone
                    return zone
                end,
            },
        },
        exports = setmetatable({}, { __call = function() end }),
        vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        vector4 = function(x, y, z) return { x = x, y = y, z = z } end,
        CreateThread = function(fn) threads = threads + 1; fn() end,
        RegisterNetEvent = function() end,
        AddEventHandler = function() end,
        GetCurrentResourceName = function() return "kora_garages" end,
        DrawMarker = function() draws = draws + 1 end,
    }
    setmetatable(env, { __index = _G })
    return env, zones, function() return threads, draws, removed end
end

-- disabled: no zones, no threads (the callback thread for house garages is the only one allowed)
local env, zones, stats = run({ enabled = false })
assert(loadfile(root .. "client/client.lua", "t", env))()
assert(#zones == 0, "disabled creates no marker zones")

-- enabled: one zone per non-house garage; the draw loop runs only while inside
local cfg = { enabled = true, type = 36, size = { x = 1, y = 1, z = 1 }, color = { r = 1, g = 2, b = 3, a = 4 },
    drawDistance = 15.0, zOffset = 0.0 }
env, zones, stats = run(cfg)
local waits = 0
env.Wait = function() waits = waits + 1; if waits >= 3 then zones[1].opts.onExit() end end
assert(loadfile(root .. "client/client.lua", "t", env))()
assert(#zones == 1, "house garages skipped by default")
assert(zones[1].opts.radius == 15.0, "zone radius is drawDistance")
local before = stats()
zones[1].opts.onEnter()
local threads, draws = stats()
assert(threads == before + 1, "entering starts exactly one draw thread")
assert(draws == 3 and waits == 3, "draws every frame until exit, then stops")
print("markers ok")
