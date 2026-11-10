local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local callbacks, exported, events, now = {}, {}, {}, 1000
local rows = {
    { plate = 'AAA111', model = 'blista', state = 'garaged', garage_id = 'legionsquare', fuel = 80, engine_health = 900, body_health = 950 },
    { plate = 'BBB222', model = 'unknownmodel', state = 'out', garage_id = 'house_x', fuel = 10, engine_health = 500, body_health = 400 },
    { plate = 'CCC333', model = 'blista', state = 'impounded', fuel = 5, engine_health = 1, body_health = 2 },
}
local queried
local env = {
    Config = {
        garageTypes = { public = { blipLabel = 'Garage', blipSprite = 357, blipColor = 3 } },
        garages = {
            legionsquare = { type = 'public', label = 'Legion', coords = 'c', spawns = { 's1', 's2' } },
            off = { type = 'public', label = 'Off', coords = 'c', spawn = 's', disabled = true },
        },
    },
    Kora = { callback = { register = function(name, fn) callbacks[name] = fn end } },
    exports = setmetatable({}, { __call = function(_, name, fn) exported[name] = fn end, __index = function()
        return {
            getPlayerData = function(_, src) return src == 1 and 'CID1' or nil end,
            getByOwner = function(_, cid) queried = cid; return cid == 'CID1' and rows or {} end,
            getShared = function(_, _, model) if model == 'blista' then return { brand = 'Dinka', name = 'Blista' } end return {} end,
        }
    end }),
    GetGameTimer = function() return now end,
    AddEventHandler = function(name, fn) events[name] = fn end,
}
setmetatable(env, { __index = _G })
assert(loadfile(root .. 'server/compat.lua', 't', env))()

local list = callbacks['qb-garages:server:GetPlayerVehicles'](1)
assert(queried == 'CID1' and #list == 3)
assert(list[1].fullname == 'Dinka Blista' and list[1].brand == 'Dinka' and list[1].model == 'Blista')
assert(list[1].garage == 'Legion' and list[1].state == 'Garaged' and list[1].fuel == 80 and list[1].engine == 900 and list[1].body == 950)
assert(list[2].fullname == 'Unknown Vehicle' and list[2].garage == 'House' and list[2].state == 'Out')
assert(list[3].garage == 'None' and list[3].state == 'Impounded By Police')
assert(callbacks['qb-garages:server:GetPlayerVehicles'](1) == nil, 'rate limited')
now = 3000
assert(callbacks['qb-garages:server:GetPlayerVehicles'](2) == nil, 'no character')
assert(callbacks['qb-garages:server:GetPlayerVehicles'](1, 'CID9') ~= nil, 'arguments never select another owner')
assert(queried == 'CID1')

local all = exported.getAllGarages()
assert(#all == 1 and all[1].name == 'legionsquare' and all[1].takeVehicle == 'c' and all[1].spawnPoint == 's1')
assert(all[1].blipNumber == 357 and all[1].blipColor == 3 and all[1].vehicle == 'car')

local registered = {}
local client = { RegisterNetEvent = function(name, fn) registered[name] = fn end }
setmetatable(client, { __index = _G })
assert(loadfile(root .. 'client/compat.lua', 't', client))()
for _, name in ipairs({ 'setHouseGarage', 'houseGarageConfig', 'addHouseGarage' }) do
    assert(registered['qb-garages:client:' .. name])
    assert(registered['qb-garages:client:' .. name]({}, {}) == nil)
end
print('kora_garages compat: 3 passed, 0 failed')
