-- Garage presentation through qblib's shared AppShell. This resource supplies
-- only a server-authorised listing and intent actions; qblib owns the browser
-- frame, focus and navigation.

Garages = Garages or {}
Garages.ui = {}

local function vehicleAction(vehicle, garage)
    if vehicle.state == 'impounded' then return garage.isImpound and 'release' or nil end
    if vehicle.state == 'out' then return garage.canStore and 'store' or nil end
    return vehicle.accepted and 'takeOut' or nil
end

local function actionLabel(action, vehicle)
    if action == 'release' then return ('Pay $%d & release'):format(tonumber(vehicle.fee) or 0) end
    return action == 'store' and 'Store vehicle' or 'Take out'
end

local function appDefinition()
    local S, garage = Garages.state.data, Garages.state.data.garage
    local items = {}
    for _, vehicle in ipairs(S.vehicles) do
        local action = garage and vehicleAction(vehicle, garage)
        local state = vehicle.state == 'impounded' and 'Impounded' or vehicle.state == 'out' and 'Out on the street' or 'In the garage'
        if not vehicle.accepted then state = state .. (' · This garage does not accept %s'):format(vehicle.category or 'this vehicle') end
        items[#items + 1] = {
            id = vehicle.plate, label = vehicle.label,
            description = ('%s · %s'):format(vehicle.plate, state),
            icon = vehicle.state == 'impounded' and 'lock' or 'car-front',
            badge = action and actionLabel(action, vehicle) or nil,
            tone = vehicle.state == 'impounded' and 'warning' or vehicle.state == 'out' and 'neutral' or 'primary',
            action = action and ('garage:' .. action) or nil,
            metadata = {
                { label = 'Fuel', value = ('%d%%'):format(math.floor(tonumber(vehicle.fuel) or 0)),
                    tone = tonumber(vehicle.fuel) and tonumber(vehicle.fuel) < 20 and 'warning' or 'neutral' },
                { label = 'Engine', value = ('%d%%'):format(math.floor(tonumber(vehicle.engine) or 0)),
                    tone = tonumber(vehicle.engine) and tonumber(vehicle.engine) < 40 and 'destructive' or 'neutral' },
                { label = 'Body', value = ('%d%%'):format(math.floor(tonumber(vehicle.body) or 0)) },
                { label = 'Category', value = vehicle.category or 'vehicle' },
            },
        }
    end

    return {
        id = 'qbgarages:garage', title = garage and garage.label or 'Garage',
        description = garage and garage.typeLabel or 'Vehicle garage', icon = garage and garage.isImpound and 'lock' or 'warehouse',
        accent = type(Config.ui.accent) == 'string' and Config.ui.accent or nil,
        width = 920, height = 720,
        navigation = {
            { id = 'vehicles', label = 'Vehicles', icon = 'car-front', badge = #S.vehicles,
                content = { title = garage and garage.label or 'Garage',
                    description = S.error or (S.busy and 'Working…' or 'Select a vehicle to use the available action.'),
                    blocks = {
                        { type = 'stats', items = {
                            { label = 'Vehicles', value = #S.vehicles, icon = 'car-front' },
                            { label = 'Garage type', value = garage and garage.typeLabel or '—', icon = 'warehouse' },
                        } },
                        { type = 'list', id = 'garage-vehicles', title = 'Your vehicles', layout = 'cards',
                            searchable = true, searchPlaceholder = 'Search name, plate, state, or category…', pageSize = 9, items = items,
                            empty = garage and (garage.isImpound and 'Nothing of yours is being held here.' or 'You have no vehicles at this garage.') or 'No garage is open.' },
                    },
                },
            },
        },
        footer = 'Vehicle access is verified by the server.',
        onAction = function(actionId, context)
            local action, plate = actionId:match('^garage:(.+)$'), context and context.itemId
            -- Re-resolve the browser-supplied plate against the authorised
            -- listing; the server repeats all ownership and proximity checks.
            local vehicle = type(plate) == 'string' and Garages.state.vehicle(plate) or nil
            local currentGarage = Garages.state.data.garage
            if not vehicle or not currentGarage or vehicleAction(vehicle, currentGarage) ~= action then
                error('That vehicle action is no longer available.')
            end
            if action == 'takeOut' then Garages.actions.takeOut(plate)
            elseif action == 'store' then Garages.actions.store(plate)
            elseif action == 'release' then Garages.actions.retrieveImpound(plate)
            else error('Unknown garage action.') end
            return {}
        end,
    }
end

function Garages.ui.render()
    if Garages.state.isOpen() then QB.nui.registerApp(appDefinition()) end
end

---@param garageId string
function Garages.ui.open(garageId)
    CreateThread(function()
        local payload, err = QB.callback.trigger('qbgarages:list', garageId)
        if payload == nil and err == nil then
            return QB.notify.send({ title = 'Garage', message = 'The garage did not answer.', type = 'error' })
        end
        if not payload or payload == false then
            return QB.notify.send({ title = 'Garage', message = err or 'You cannot use this garage.', type = 'error' })
        end
        Garages.state.adopt(payload)
        Garages.state.setOpen(true)
        QB.nui.registerApp(appDefinition())
        QB.nui.openApp('qbgarages:garage')
        Garages.state.setOpen(false)
    end)
end

function Garages.ui.refresh()
    local garageId = Garages.state.garageId()
    if not garageId then return end
    CreateThread(function()
        local payload = QB.callback.trigger('qbgarages:list', garageId)
        if type(payload) ~= 'table' then return Garages.ui.close() end
        Garages.state.adopt(payload)
        Garages.ui.render()
    end)
end

function Garages.ui.close()
    if not Garages.state.isOpen() then return end
    Garages.state.setOpen(false)
    QB.nui.closeApp('qbgarages:garage')
end
