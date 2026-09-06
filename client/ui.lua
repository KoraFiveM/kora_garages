-- The NUI bridge.
--
-- IMPORTANT: every NUI native below is called RAW rather than through QB.nui.*.
-- This resource owns its own frame (`ui_page` in fxmanifest.lua), and each
-- `QB.<module>.<fn>` access is a cross-resource export call whose body runs in
-- QBLIB's Lua VM -- SendNUIMessage would post into qblib's frame, and
-- RegisterNUICallback would publish the callback at https://qblib/<name> while
-- this resource's page fetches https://qbgarages/<name>: a permanent 404. The
-- same rationale is documented at the head of qbhud/client/hud.lua and
-- qbdispatch/client/ui.lua.
--
-- QB.blips / QB.vehicle / QB.callback stay on the proxy; qbtheme is imported
-- directly -- they are
-- pure Lua (or plain natives) and touch no NUI native.

Garages = Garages or {}
Garages.ui = {}

local ready = false
local pending = {}

-- Whether THIS resource currently holds NUI focus.
--
-- SetNuiFocus is global, not per-resource: SetNuiFocus(false, false) releases
-- whoever actually has it. Releasing focus we never took steals the mouse from
-- another resource's open UI -- qbdispatch documents the login-screen version of
-- exactly this bug. So: only ever release focus this resource took.
local hasFocus = false

---@param focused boolean
local function setFocus(focused)
    if focused == hasFocus then return end
    hasFocus = focused
    SetNuiFocus(focused, focused)
end

---@param action string
---@param data any
function Garages.ui.send(action, data)
    -- SendNUIMessage is postMessage-like, not a mailbox: anything sent before
    -- the page mounts is lost permanently. Queued until the app reports in,
    -- which matters most on resource restart -- the first render routinely beats
    -- the browser to it.
    if not ready then
        pending[#pending + 1] = { action = action, data = data }
        return
    end
    SendNUIMessage({ action = action, data = data })
end

---Pushes the whole current view. A garage panel is a few dozen rows at most, so
---wholesale is both cheap and far easier to reason about than a diff.
function Garages.ui.render()
    local S = Garages.state.data

    Garages.ui.send('qbgarages:state', {
        open = S.open,
        garage = S.garage,
        vehicles = S.vehicles,
        busy = S.busy,
        error = S.error,
    })
end

function Garages.ui.pushTheme()
    local accent = Config.ui.accent
    QBTheme.apply(type(accent) == 'string' and accent or nil)
end

---Fetches the listing for `garageId` and opens the panel on success.
---
---The listing is what AUTHORISES the open: the server refuses it when the
---player is out of range, in the wrong bucket or not entitled, so there is no
---separate "may I open this" call to get out of step with the data.
---@param garageId string
function Garages.ui.open(garageId)
    CreateThread(function()
        local payload, err = QB.callback.trigger('qbgarages:list', garageId)

        -- A timed-out callback returns NOTHING, so `payload` is nil and `err` is
        -- nil too -- it is not a refusal and must not be reported as one. See
        -- the framework note: a nil result is "no answer", never "no".
        if payload == nil and err == nil then
            return QB.notify.send({ title = 'Garage', message = 'The garage did not answer.', type = 'error' })
        end

        if not payload or payload == false then
            return QB.notify.send({ title = 'Garage', message = err or 'You cannot use this garage.', type = 'error' })
        end

        Garages.state.adopt(payload)
        Garages.state.setOpen(true)
        setFocus(true)
        Garages.ui.pushTheme()
        Garages.ui.render()
    end)
end

---Re-fetches the current garage in place, after an action changed something.
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
    -- Focus is released even when this resource already believes the panel is
    -- shut: setFocus is a no-op when we never held it, so this cannot disturb
    -- another resource's UI, and it means a player can never be left with their
    -- mouse locked to a frame that no longer renders anything.
    setFocus(false)
    if not Garages.state.isOpen() then return end

    Garages.state.setOpen(false)
    Garages.ui.render()
end

-- Answered first and unconditionally, so a failure inside the initial render
-- cannot leave the browser's fetch hanging forever.
RegisterNUICallback('qbgarages:ready', function(_, cb)
    cb({})
    ready = true

    for _, message in ipairs(pending) do
        SendNUIMessage({ action = message.action, data = message.data })
    end
    pending = {}

    Garages.ui.pushTheme()
    Garages.ui.render()
end)

RegisterNUICallback('qbgarages:close', function(_, cb)
    cb({})
    Garages.ui.close()
end)

RegisterNUICallback('qbgarages:takeOut', function(data, cb)
    cb({})
    -- `data.plate` is INTENT. It is forwarded untouched and the server
    -- re-resolves it against the DB and against the garage the server itself
    -- re-resolves -- this client never looks the plate up to "check" it first,
    -- because a client-side check is decoration, not a gate.
    Garages.actions.takeOut(data and data.plate)
end)

RegisterNUICallback('qbgarages:store', function(data, cb)
    cb({})
    Garages.actions.store(data and data.plate)
end)

RegisterNUICallback('qbgarages:retrieveImpound', function(data, cb)
    cb({})
    Garages.actions.retrieveImpound(data and data.plate)
end)

-- Refusals raised by the legacy compat path, which has no callback to answer.
RegisterNetEvent('qbgarages:client:refused', function(message)
    QB.notify.send({ title = 'Garage', message = tostring(message), type = 'error' })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Leaving NUI focus set would lock the player's mouse into a frame that no
    -- longer exists, with no way out but a reconnect. Gated the same way: if we
    -- did not take focus, someone else holds it and it is not ours to drop.
    setFocus(false)
end)
