-- Client presentation smoke: interact mode uses stable qblib box-zone names,
-- passes the configured heading through, and never registers with qbtarget.
local h = dofile('test/harness.lua')
dofile('config.lua')

Config.interaction.mode = 'interact'

local handlers, zones, targetCalls = {}, {}, 0
local openedGarage

local function on(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end

local qbtarget = {}
function qbtarget:addBoxZone()
    targetCalls = targetCalls + 1
end

local qbcore = {}
function qbcore:getJob() return { name = 'unemployed', onduty = false } end
function qbcore:getGang() return { name = 'none' } end

_G.exports = { qbtarget = qbtarget, qbcore = qbcore }
_G.QB = {
    interact = {
        addBoxZone = function(name, coords, size, options, debug)
            zones[name] = { coords = coords, size = size, options = options, debug = debug }
        end,
        removeZone = function(name)
            zones[name] = nil
            return true
        end,
    },
}
_G.Garages = { ui = { open = function(id) openedGarage = id end } }
_G.AddEventHandler = on

dofile('client/zones.lua')

local function count(values)
    local total = 0
    for _ in pairs(values) do total = total + 1 end
    return total
end

h.test('interact mode registers one named box per garage', function()
    h.assertEqual(targetCalls, 0, 'interact mode must not add qbtarget zones')
    h.assertEqual(count(zones), count(Config.garages), 'every garage needs one interact box')
end)

h.test('the Legion interact option opens Legion with E-compatible action', function()
    local legion = zones['qbgarages:legionsquare']
    h.assertTrue(legion ~= nil, 'Legion needs a stable interact zone name')
    h.assertEqual(#legion.options, 1, 'Legion needs exactly one interact option')
    h.assertEqual(legion.size.w, Config.garages.legionsquare.heading or 0.0,
        'the interact box must preserve its heading')

    legion.options[1].action()
    h.assertEqual(openedGarage, 'legionsquare', 'the Legion action must open Legion')
end)

h.test('qbtarget restarts do not duplicate interact zones', function()
    for _, callback in ipairs(handlers.onClientResourceStart or {}) do callback('qbtarget') end
    h.assertEqual(targetCalls, 0, 'interact mode stays independent of qbtarget restarts')
    h.assertEqual(count(zones), count(Config.garages), 'interact zones remain unique')
end)

h.report('zones interact')
