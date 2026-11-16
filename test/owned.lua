local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local exported, queried = {}, {}
local rows = {
    { plate = 'ZZZ999', model = 'blista', state = 'garaged', garage_id = 'legion', fuel = 80, engine_health = 900, body_health = 950 },
    { plate = 'AAA111', model = 'mystery', state = 'out', garage_id = 'house_x', fuel = 10, engine_health = 500, body_health = 400 },
    { plate = 'MMM555', model = 'blista', state = 'impounded', fuel = 5, engine_health = 1, body_health = 2 },
    { plate = 'BBB222', model = 'blista', state = 'weird' },
}
local many = {}
for i = 1, 250 do many[i] = { plate = string.format('P%04d', i), model = 'blista', state = 'garaged' } end

local env = {
    Config = { garages = { legion = { label = 'Legion Square' } } },
    exports = setmetatable({}, { __call = function(_, name, fn) exported[name] = fn end, __index = function()
        return {
            getByOwner = function(_, cid)
                queried[#queried + 1] = cid
                if cid == 'MANY' then return many end
                return cid == 'CID1' and rows or nil
            end,
            getShared = function(_, _, model)
                if model == 'blista' then return { brand = 'Dinka', name = 'Blista' } end
                error('unknown model')
            end,
        }
    end }),
}
setmetatable(env, { __index = _G })
assert(loadfile(root .. 'server/owned.lua', 't', env))()

local passed = 0
local function check(name, ok) assert(ok, name) passed = passed + 1 end

local list = exported.getOwnedVehicles('CID1')
check('four rows sorted by plate', #list == 4 and list[1].plate == 'AAA111' and list[4].plate == 'ZZZ999')
check('known model gets brand and name', list[4].label == 'Dinka Blista' and list[4].model == 'blista')
check('unresolvable model falls back to the model', list[1].label == 'mystery')
check('garage id and label', list[4].garage == 'legion' and list[4].garageLabel == 'Legion Square')
check('unlisted garage id is a house', list[1].garage == 'house_x' and list[1].garageLabel == 'House')
check('no garage', list[3].garage == '' and list[3].garageLabel == 'None')
check('states', list[4].state == 'garaged' and list[1].state == 'out' and list[3].state == 'impounded')
check('unknown state is out', list[2].state == 'out')
check('fuel engine body', list[4].fuel == 80 and list[4].engine == 900 and list[4].body == 950)
check('missing numbers default to 0', list[2].fuel == 0 and list[2].engine == 0)

local none = exported.getOwnedVehicles('NOBODY')
check('no rows gives empty list', type(none) == 'table' and #none == 0)
check('capped at 200', #exported.getOwnedVehicles('MANY') == 200)

local queriedBefore = #queried
for _, bad in ipairs({ 42, '', string.rep('x', 51), {}, true }) do
    local result, err = exported.getOwnedVehicles(bad)
    check('rejects invalid citizen id', result == false and err ~= nil)
end
check('invalid ids never reach the database', #queried == queriedBefore)
print(string.format('kora_garages owned vehicles: %d passed, 0 failed', passed))
