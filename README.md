# kora_garages

Existing configured garages retain their client/server callbacks and behavior.

Property providers may register runtime garages on the server:

```lua
local ok, err = exports.kora_garages:RegisterPropertyGarage('property-garage-id', {
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
preserves mapping and vehicles. Listen for `kora_garages:ready` to rebind after
garage schema initialization/restart.

Clients use `exports.kora_garages:openGarage(id)` to open the existing garage UI.
It returns `true` when opening is scheduled or `false, error` for an unavailable
garage. Server policies still check each list, store, and retrieve operation.
Vehicles parked at protected property garages cannot be listed or retrieved
through a public garage. Property storage validates entity, plate, routing
bucket, proximity, capacity, and ownership, confirms an atomic state/garage
update, and then deletes the vehicle. Retrieval uses kora_core's per-plate spawn
serialization and checked state transition.
After retrieving a vehicle, its owner may store it at a public garage even
after property access ends. That checked transition moves its durable garage
association to the public garage; a still-parked protected vehicle cannot use
this recovery path.

## Vehicle id state bag

When a garage take-out spawns an owned vehicle, the server sets the
`vehicleid` state bag (`player_vehicles.id`, integer) on the entity, so stock
ox_inventory can skip its per-open plate lookup. The bag is server-only
(non-replicated), set only after the entity exists and the `out` state update
succeeded. It is done by `exports.kora_core:tagVehicle`, which also tags the
property-garage path (`spawnVehicle`). With an older kora_core lacking that
export the call is skipped and take-out works unchanged. Set convar
`kora:vehicleIdStateBag 0` to disable (default `1`).

Run `lua test/property.lua` and `lua test/legacy-housing.lua` from this resource
to validate the property adapter, vehicle id tagging and legacy caller compatibility
(run from a sibling layout with `../kora_core` and `../kora_lib` present). These use
native/SQL fixtures; live multiplayer acceptance requires FXServer.

## qb-garages compatibility

The resource provides `qb-garages`. `qb-garages:server:GetPlayerVehicles` returns
the caller's own vehicles in the stock shape (`nil` when there are none; one call
per second per player; arguments are ignored). `exports['qb-garages']:getAllGarages()`
is built from `Config.garages`. The client events `setHouseGarage`,
`houseGarageConfig` and `addHouseGarage` are accepted as no-ops, since house
garages come from kora_housing via `RegisterPropertyGarage`. Stock
`updateVehicleState`/`updateVehicleStats` are not registered.

## Cosmetic protection

By default (`Config.TrustClientCosmetics = false`) parking a vehicle never changes its
stored look. Fields in `Config.mods.cosmetic`, every `mod*` slot and numeric mod
indexes 0-49 are kept from the database row; only non-cosmetic state (fuel, health,
dirt, damage) is taken from the client. A vehicle with no stored look yet (dealership
rows have no props) stores no cosmetics when parked, so an unpaid preview can't become
its look; it keeps the game's default look for its model until a paid order stores one.
`Config.SaveUnstoredLook = true` records the client's look on that first park instead. Set `Config.TrustClientCosmetics = true` to restore the old behaviour,
e.g. if a customs resource saves the look through the garage store event.

## Garage markers

Optional ground markers so garage points are easy to find. Off by default; when
`Config.markers.enabled = false` no zones or threads are created.

Proximity uses kora_lib sphere zones (`onEnter`/`onExit`, no polling in this
resource). A per-frame `DrawMarker` loop runs only while the player is within
`drawDistance` of a garage they may use, and ends when they leave.

| Option | Default | Meaning |
|---|---|---|
| `Config.markers.enabled` | `false` | Master switch |
| `type` | `36` | `DrawMarker` type id |
| `size` | `vector3(1,1,1)` | Marker scale |
| `color` | `{r=60,g=180,b=255,a=150}` | RGBA |
| `drawDistance` | `15.0` | Metres before the marker is drawn |
| `zOffset` | `0.0` | Added to the garage point's Z |
| `bobUpAndDown`, `rotate` | `false` | Marker animation |
| `houseGarages` | `false` | Also mark property garages |

Set `noMarker = true` on a garage entry to skip it. Run `lua test/markers.lua`.
