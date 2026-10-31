local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
for _, exists in ipairs({ 0, 1 }) do
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
                        queries = queries + 1
                        return {{ name = 'test', garage = 'position' }}
                    end
                end,
            },
        },
        CreateThread = function(fn) threads[#threads + 1] = fn end,
        RegisterCommand = function() end,
        json = { decode = function() return { x = 1, y = 2, z = 3, w = 4 } end },
        vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
    }
    setmetatable(env, { __index = _G })
    assert(loadfile(root .. 'server/server.lua', 't', env))()
    threads[1]()
    assert(queries == exists)
    assert((env.Config.garages.house_test ~= nil) == (exists == 1))
end
print('qbgarages: missing legacy housing skipped; existing garage data retained')
