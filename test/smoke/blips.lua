-- Each map marker has a meaningful location name while matching garage types
-- share a legend category. This prevents the pause map from listing a run of
-- indistinguishable "Garage" entries.
local h = dofile('test/harness.lua')
dofile('config.lua')

local handlers, created, removed = {}, {}, {}

local function on(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end

local function emit(name, ...)
    for _, callback in ipairs(handlers[name] or {}) do callback(...) end
end

_G.QB = {
    blips = {
        create = function(_, options)
            local handle = #created + 1
            created[handle] = options
            return handle
        end,
        remove = function(handle)
            removed[#removed + 1] = handle
            return true
        end,
    },
}
_G.RegisterNetEvent = on
_G.AddEventHandler = on
_G.GetCurrentResourceName = function() return 'qbgarages' end

dofile('client/blips.lua')
emit('onClientResourceStart', 'qbgarages')

local function count(values)
    local total = 0
    for _ in pairs(values) do total = total + 1 end
    return total
end

h.test('garage markers use their location labels and shared type categories', function()
    local garageCount = count(Config.garages)
    h.assertEqual(#created, garageCount, 'one marker per configured garage')

    local names, publicCategories = {}, {}
    for _, options in ipairs(created) do
        names[options.name] = true
        if options.category == Config.garageTypes.public.blipLabel then
            publicCategories[options.category] = true
        end
    end

    h.assertTrue(names['Legion Square Parking'], 'Legion has a distinct map label')
    h.assertTrue(names['Pink Cage Motel Parking'], 'Pink Cage has a distinct map label')
    h.assertEqual(count(names), garageCount, 'no two configured markers have an indistinguishable map label')
    h.assertEqual(count(publicCategories), 1, 'public garages share one legend category')
    h.assertEqual(created[1].label, nil, 'qblib composes map labels from category and location name')
end)

h.test('rebuilding markers removes the previous set before adding another', function()
    local before = #created
    emit('QBCore:Client:OnPlayerLoaded')
    h.assertEqual(#removed, before, 'every old marker is removed')
    h.assertEqual(#created, before * 2, 'the rebuilt set has one marker per garage')
end)

h.report('blips')
