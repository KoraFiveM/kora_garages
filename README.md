# qbgarages

Existing configured garages retain their client/server callbacks and behavior.

Property providers may register runtime garages on the server:

```lua
local ok, err = exports.qbgarages:RegisterPropertyGarage('property-garage-id', {
    label = 'Home', coords = { x = 0, y = 0, z = 0 },
    spawn = { x = 5, y = 0, z = 0, w = 90 }, slots = 2,
}, function(source, action, id)
    -- Check current authoritative property permissions for list/store/retrieve.
    return hasPropertyPermission(source, id, action)
end)
```

IDs are stable strings of at most 50 characters. `spawns` may replace `spawn`.
Optional `capacityOwnerIds` restricts capacity counting to current occupants;
former occupants' vehicles stay recoverable. `retrievalOnly=true` disables
storage. Registration returns `true` or `false, error`; the invoking resource
owns the durable mapping. Refresh registration to update capacity or policy.
Restored garages remain disabled until their provider rebinds, and provider
stop/unregister immediately disables access. `UnregisterPropertyGarage(id)`
preserves mapping and vehicles. Listen for `qbgarages:ready` to rebind after
garage schema initialization/restart.

Clients use `exports.qbgarages:openGarage(id)` to open the existing garage UI.
It returns `true` when opening is scheduled or `false, error` for an unavailable
garage. Server policies still check each list, store, and retrieve operation.
Vehicles parked at protected property garages cannot be listed or retrieved
through a public garage. Property storage validates entity, plate, routing
bucket, proximity, capacity, and ownership, confirms an atomic state/garage
update, and then deletes the vehicle. Retrieval uses qbcore's per-plate spawn
serialization and checked state transition.
After retrieving a vehicle, its owner may store it at a public garage even
after property access ends. That checked transition moves its durable garage
association to the public garage; a still-parked protected vehicle cannot use
this recovery path.

Run `lua test/property.lua` from this resource to validate the property adapter.
These tests use
native/SQL fixtures; live multiplayer acceptance requires FXServer.
