-- Mocks for smoke-testing qbgarages under plain lua5.4 (no FiveM, no qbcore, no DB).
--
-- The whole point of this file is that the REFUSALS are testable. A garage's
-- security is a stack of five re-reads -- character, job/gang, routing bucket,
-- distance, ownership -- and every one of them is a server native or a qbcore
-- export. So this installs a small, fully controllable world: a players table
-- with coordinates and buckets, an entities table with plates and buckets, a
-- vehicles table standing in for `player_vehicles`, and a money ledger.
--
-- The qbcore surface below mirrors qbcore/modules/garage/server.lua's real
-- SEMANTICS, not just its signatures: spawnVehicle refuses an impounded or
-- already-out row, storeVehicle refuses an impounded one and does NOT delete the
-- entity, and retrieveImpound checks the requester's citizenid itself. A mock
-- that was merely shaped right would let a regression that leans on the wrong
-- layer pass here and then misbehave in game.

local M = {}

function M.install()
    local players = {}   ---@type table<integer, table>
    local entities = {}  ---@type table<integer, table>
    local byNetId = {}   ---@type table<integer, integer>
    local vehicles = {}  ---@type table<string, table>
    local deleted = {}   ---@type integer[]
    local money = {}     ---@type table<integer, table<string, number>>
    local nextEntity, nextNetId = 100, 500

    local clientEvents = {}
    local netHandlers = {}
    local callbacks = {}

    -- --- natives ------------------------------------------------------------

    function _G.GetGameTimer() return 0 end
    function _G.CreateThread(fn) fn() end
    function _G.Wait(_) end
    function _G.GetCurrentResourceName() return 'qbgarages' end
    function _G.GetInvokingResource() return nil end

    -- Peds are entity handles too, so one table serves both. A player with no
    -- entry has no ped, which is the "player entity unavailable" path.
    function _G.GetPlayerPed(src)
        local p = players[src]
        return p and p.ped or 0
    end

    function _G.DoesEntityExist(entity)
        if not entity or entity == 0 then return false end
        local record = entities[entity]
        return record ~= nil and record.exists ~= false
    end

    function _G.GetEntityCoords(entity)
        local record = entities[entity]
        return record and record.coords or nil
    end

    function _G.GetEntityType(entity)
        local record = entities[entity]
        return record and record.entityType or 0
    end

    function _G.GetPlayerRoutingBucket(src)
        local p = players[src]
        return p and p.bucket or 0
    end

    function _G.GetEntityRoutingBucket(entity)
        local record = entities[entity]
        return record and record.bucket or 0
    end

    function _G.NetworkGetEntityFromNetworkId(netId)
        return byNetId[netId] or 0
    end

    function _G.GetVehicleNumberPlateText(entity)
        local record = entities[entity]
        -- Returned SPACE-PADDED to eight characters, exactly as GTA does. This
        -- is not decoration: it is why Garages.shared.normalisePlate exists, and
        -- a mock that returned a tidy plate would hide every place the
        -- comparison was done against a raw read.
        if not record or not record.plate then return '' end
        return record.plate .. string.rep(' ', 8 - #record.plate)
    end

    function _G.GetVehicleEngineHealth(entity)
        local record = entities[entity]
        return record and record.engine or 0
    end

    function _G.GetVehicleBodyHealth(entity)
        local record = entities[entity]
        return record and record.body or 0
    end

    function _G.GetVehicleFuelLevel(entity)
        local record = entities[entity]
        return record and record.fuel or 0
    end

    function _G.DeleteEntity(entity)
        deleted[#deleted + 1] = entity
        if entities[entity] then entities[entity].exists = false end
    end

    function _G.GetAllVehicles()
        local out = {}
        for handle, record in pairs(entities) do
            if record.entityType == 2 and record.exists ~= false then out[#out + 1] = handle end
        end
        table.sort(out)
        return out
    end

    function _G.RegisterNetEvent(name, cb)
        if not cb then return end
        netHandlers[name] = netHandlers[name] or {}
        table.insert(netHandlers[name], cb)
    end

    function _G.AddEventHandler(name, cb) _G.RegisterNetEvent(name, cb) end

    function _G.TriggerEvent(name, ...)
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end

    function _G.TriggerClientEvent(name, target, ...)
        clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } }
    end

    -- --- the qbcore export surface -----------------------------------------

    local qbcore = {}

    function qbcore:getPlayerData(src, path)
        local p = players[src]
        if not p then return nil end
        if type(path) == 'table' and path[1] == 'citizenid' then return p.citizenid end
        return p
    end

    function qbcore:getJob(src)
        local p = players[src]
        return p and p.job or nil
    end

    function qbcore:getGang(src)
        local p = players[src]
        return p and p.gang or nil
    end

    -- Registry contents mirror qbcore/shared/vehicles.lua's real shape, because
    -- the category allow-list is enforced against real model->category
    -- relationships and a mock keyed differently would test nothing.
    local sharedVehicles = {
        sultan = { model = 'sultan', name = 'Sultan', brand = 'Karin', category = 'sedans' },
        police = { model = 'police', name = 'Cruiser', brand = 'Vapid', category = 'emergency' },
        buzzard = { model = 'buzzard', name = 'Buzzard', brand = 'Nagasaki', category = 'helicopters' },
    }

    function qbcore:getShared(registry, key)
        if registry ~= 'vehicles' then return nil end
        return sharedVehicles[key]
    end

    function qbcore:getByPlate(plate)
        return vehicles[plate]
    end

    function qbcore:getByOwner(citizenid)
        local out = {}
        for _, row in pairs(vehicles) do
            if row.citizenid == citizenid then out[#out + 1] = row end
        end
        table.sort(out, function(a, b) return a.plate < b.plate end)
        return out
    end

    function qbcore:spawnVehicle(src, plate, coords, heading)
        local row = vehicles[plate]
        if not row then return false, 'unknown vehicle' end
        if row.state == 'impounded' then return false, 'vehicle is impounded' end
        if row.state == 'out' then return false, 'vehicle is already out' end

        row.state = 'out'

        local handle = nextEntity; nextEntity = nextEntity + 1
        local netId = nextNetId; nextNetId = nextNetId + 1
        entities[handle] = {
            entityType = 2, plate = plate, exists = true,
            coords = { x = coords.x, y = coords.y, z = coords.z },
            bucket = GetPlayerRoutingBucket(src),
            engine = row.engine_health, body = row.body_health, fuel = row.fuel,
            heading = heading,
        }
        byNetId[netId] = handle
        return netId
    end

    function qbcore:storeVehicle(plate, snapshot)
        local row = vehicles[plate]
        if not row then return false, 'unknown vehicle' end
        if row.state == 'impounded' then return false, 'vehicle is impounded' end

        row.state = 'garaged'
        snapshot = snapshot or {}
        -- COALESCE semantics: an absent reading keeps the stored value.
        if snapshot.fuel then row.fuel = snapshot.fuel end
        if snapshot.engineHealth then row.engine_health = snapshot.engineHealth end
        if snapshot.bodyHealth then row.body_health = snapshot.bodyHealth end
        if snapshot.mods then row.mods = snapshot.mods end
        if snapshot.position then row.last_position = snapshot.position end
        return true
    end

    function qbcore:impound(plate, fee, lot)
        local row = vehicles[plate]
        if not row then return false, 'unknown vehicle' end
        row.state = 'impounded'
        row.impound_fee = fee
        row.impound_lot = lot
        return true
    end

    function qbcore:retrieveImpound(src, plate)
        local row = vehicles[plate]
        if not row then return false, 'unknown vehicle' end
        if row.state ~= 'impounded' then return false, 'vehicle is not impounded' end
        if row.citizenid then
            local p = players[src]
            if not p or p.citizenid ~= row.citizenid then return false, 'not your vehicle' end
        end
        -- A test can make the clear fail, to prove the fee is refunded rather
        -- than pocketed. There is no other way to reach that branch.
        if row.failClear then return false, 'write failed' end

        row.state = 'garaged'
        row.impound_fee = nil
        row.impound_lot = nil
        return true
    end

    function qbcore:getMoney(src, account)
        return (money[src] or {})[account] or 0
    end

    function qbcore:removeMoney(src, account, amount, _reason)
        local balance = (money[src] or {})[account] or 0
        if amount <= 0 then return false, 'amount must be positive' end
        if balance - amount < 0 then return false, 'insufficient funds' end
        money[src][account] = balance - amount
        return true
    end

    function qbcore:addMoney(src, account, amount, _reason)
        money[src] = money[src] or {}
        money[src][account] = (money[src][account] or 0) + amount
        return true
    end

    -- FXServer's `exports` is both callable (exports('name', fn) registers) and
    -- indexable (exports.qbcore:fn(...) calls). Mocked as a callable table so
    -- both forms work, and the registrations are recorded so a test can assert
    -- the public export surface.
    --
    -- Colon-call dispatch passes the receiver as `self`, which the
    -- `function qbcore:fn(...)` sugar already declares -- so each method's named
    -- parameters line up with the real export's signature exactly.
    local registered = {}
    _G.exports = setmetatable({ qbcore = qbcore }, {
        __call = function(_, name, fn) registered[name] = fn end,
    })

    _G.QB = {
        callback = {
            register = function(name, handler, opts)
                callbacks[name] = { handler = handler, opts = opts }
            end,
            trigger = function() end,
        },
        notify = { send = function() end },
    }

    return {
        registeredExports = registered,
        callbacks = callbacks,
        clientEvents = clientEvents,
        vehicles = vehicles,
        deleted = deleted,

        ---Invokes a registered server callback the way a client would.
        callback = function(name, src, ...)
            local entry = callbacks[name]
            if not entry then error(('no callback registered as %s'):format(name)) end
            return entry.handler(src, ...)
        end,

        ---@param src integer
        ---@param opts table {citizenid?, job?, gang?, coords, bucket?, money?}
        setPlayer = function(src, opts)
            local handle = nextEntity; nextEntity = nextEntity + 1
            entities[handle] = {
                entityType = 1, exists = true,
                coords = opts.coords, bucket = opts.bucket or 0,
            }
            players[src] = {
                ped = handle, citizenid = opts.citizenid, job = opts.job, gang = opts.gang,
                bucket = opts.bucket or 0,
            }
            money[src] = opts.money or { cash = 0, bank = 0 }
        end,

        ---Moves a player (and their ped) without rebuilding them.
        movePlayer = function(src, coords)
            local p = players[src]
            entities[p.ped].coords = coords
        end,

        setBucket = function(src, bucket)
            players[src].bucket = bucket
            entities[players[src].ped].bucket = bucket
        end,

        removePlayer = function(src) players[src] = nil end,

        ---@param row table {plate, model, citizenid?, job?, state?, fuel?, engine?, body?, impound_fee?}
        addVehicle = function(row)
            vehicles[row.plate] = {
                plate = row.plate, model = row.model,
                citizenid = row.citizenid, job = row.job,
                state = row.state or 'garaged',
                fuel = row.fuel or 100, engine_health = row.engine or 1000, body_health = row.body or 1000,
                impound_fee = row.impound_fee, impound_lot = row.impound_lot,
                mods = row.mods,
            }
            return vehicles[row.plate]
        end,

        ---Puts a live vehicle in the world, as if something else had spawned it.
        ---@param opts table {plate, coords, bucket?, engine?, body?, fuel?}
        spawnEntity = function(opts)
            local handle = nextEntity; nextEntity = nextEntity + 1
            local netId = nextNetId; nextNetId = nextNetId + 1
            entities[handle] = {
                entityType = opts.entityType or 2, plate = opts.plate, exists = true,
                coords = opts.coords, bucket = opts.bucket or 0,
                engine = opts.engine or 1000, body = opts.body or 1000, fuel = opts.fuel or 100,
            }
            byNetId[netId] = handle
            return netId, handle
        end,

        entity = function(handle) return entities[handle] end,
        wasDeleted = function(handle)
            for _, deletedHandle in ipairs(deleted) do
                if deletedHandle == handle then return true end
            end
            return false
        end,

        balance = function(src, account) return (money[src] or {})[account] or 0 end,
    }
end

return M
