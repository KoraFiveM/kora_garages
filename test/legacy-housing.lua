local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
for _, case in ipairs({ { 0, 'missing' }, { 1, 'missing' }, { 1, 'stopped' }, { 1, 'started' } }) do
    local exists, housingState = case[1], case[2]
    local native = housingState ~= 'missing'
    local threads, queries = {}, 0
    local env = {
        Config = { garages = {} },
        PropertyGarages = {},
        Kora = {
            callback = { register = function() end },
            sql = {
                scalar = function(sql, params)
                    assert(sql:find('information_schema.tables', 1, true))
                    assert(params[1] == 'houselocations')
                    return exists
                end,
                query = function(sql)
                    if sql:find('houselocations', 1, true) then
                        assert(exists == 1, 'Absent legacy housing must never be queried')
                    assert(not native, 'Stock tables must not be read while kora_housing is installed')
                        queries = queries + 1
                        return {{ name = 'test', garage = 'position' }}
                    end
                end,
            },
        },
        CreateThread = function(fn) threads[#threads + 1] = fn end,
        GetResourceState = function(name) assert(name == 'kora_housing'); return housingState end,
        RegisterCommand = function() end,
        json = { decode = function() return { x = 1, y = 2, z = 3, w = 4 } end },
        vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
    }
    setmetatable(env, { __index = _G })
    assert(loadfile(root .. 'server/server.lua', 't', env))()
    threads[1]()
    local expected = (exists == 1 and not native) and 1 or 0
    assert(queries == expected)
    assert((env.Config.garages.house_test ~= nil) == (expected == 1))
end
print('kora_garages: missing legacy housing skipped; existing garage data retained; skipped when kora_housing is installed')
