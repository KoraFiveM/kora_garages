-- The local cache of whatever panel is currently open.
--
-- Nothing here is authority. Every field is a copy of what the server last
-- answered, kept only so the UI can re-render without another round trip -- and
-- discarded wholesale on close, so a stale plate can never be replayed into an
-- action after the player has walked away.

Garages = Garages or {}
Garages.state = {}

local State = {
    open = false,
    garage = nil,   ---@type table|nil the server's own garage descriptor
    vehicles = {},  ---@type table[]
    busy = false,   -- an action is in flight; the UI disables its buttons
    error = nil,    ---@type string|nil the last refusal, shown verbatim
}

Garages.state.data = State

---@return boolean
function Garages.state.isOpen()
    return State.open
end

---@return string|nil
function Garages.state.garageId()
    return State.garage and State.garage.id or nil
end

---Adopts a server listing payload.
---@param payload table `{ garage, vehicles }`
function Garages.state.adopt(payload)
    State.garage = payload.garage
    State.vehicles = payload.vehicles or {}
    State.error = nil
end

---@param open boolean
function Garages.state.setOpen(open)
    State.open = open and true or false
    if not State.open then
        -- Cleared, not kept: the plates in this list are only meaningful while
        -- the player is standing at the garage that produced them.
        State.garage = nil
        State.vehicles = {}
        State.busy = false
        State.error = nil
    end
end

---@param busy boolean
function Garages.state.setBusy(busy)
    State.busy = busy and true or false
end

---@param message string|nil
function Garages.state.setError(message)
    State.error = type(message) == 'string' and message or nil
end

---@param plate string
---@return table|nil
function Garages.state.vehicle(plate)
    for _, vehicle in ipairs(State.vehicles) do
        if vehicle.plate == plate then return vehicle end
    end
    return nil
end
