-- Client presentation smoke: target mode registers exactly one removable
-- qbtarget box per garage and re-registration cannot duplicate Legion.
local h = dofile('test/harness.lua')
dofile('config.lua')

Config.interaction.mode = 'target'

local handlers, active, added, removed = {}, {}, {}, {}
local nextId, openedGarage = 0, nil

local function on(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end

local function emit(name, ...)
    for _, callback in ipairs(handlers[name] or {}) do callback(...) end
end

local qbtarget = {}
function qbtarget:addBoxZone(options)
    nextId = nextId + 1
    active[nextId] = options
    added[#added + 1] = options
    return nextId
end
function qbtarget:removeZone(id)
    removed[#removed + 1] = id
    active[id] = nil
    return true
end

local qbcore = {}
function qbcore:getJob() return { name = 'unemployed', onduty = false } end
function qbcore:getGang() return { name = 'none' } end

_G.exports = { qbtarget = qbtarget, qbcore = qbcore }
_G.QB = { interact = { removeZone = function() error('target mode touched QB.interact') end } }
_G.Garages = { ui = { open = function(id) openedGarage = id end } }
_G.AddEventHandler = on

dofile('client/zones.lua')

local function count(values)
    local total = 0
    for _ in pairs(values) do total = total + 1 end
    return total
end

local garageCount = count(Config.garages)

h.test('target mode registers one box per garage', function()
    h.assertEqual(#added, garageCount, 'every garage needs one target box')
    h.assertEqual(count(active), garageCount, 'target registry must not contain duplicates')
end)

h.test('the Legion target opens only Legion', function()
    local legion
    for _, options in ipairs(added) do
        if options.coords == Config.garages.legionsquare.coords then legion = options end
    end

    h.assertTrue(legion ~= nil, 'Legion needs a target box')
    h.assertEqual(#legion.options, 1, 'Legion needs exactly one target option')
    h.assertEqual(legion.rotation, Config.garages.legionsquare.heading or 0.0,
        'the target box must preserve its heading as rotation')
    legion.options[1].onSelect()
    h.assertEqual(openedGarage, 'legionsquare', 'the Legion option must open Legion')
end)

h.test('target re-registration replaces its previous handles', function()
    emit('onClientResourceStart', 'qbtarget')
    h.assertEqual(#removed, garageCount, 'every old target handle must be removed')
    h.assertEqual(count(active), garageCount, 're-registration must leave one box per garage')
end)

h.test('a real qbtarget restart forgets stale ids before rebuilding', function()
    active = {} -- qbtarget itself clears these as it stops
    local removalsBefore = #removed
    emit('onClientResourceStop', 'qbtarget')
    emit('onClientResourceStart', 'qbtarget')

    h.assertEqual(#removed, removalsBefore, 'stale ids must not be removed from the new qbtarget instance')
    h.assertEqual(count(active), garageCount, 'the restarted target gets one fresh box per garage')
end)

h.report('zones target')
