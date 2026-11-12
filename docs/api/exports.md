---
title: "Exports"
sidebar_position: 2
---


# Exports

## Server

Server-side exports for registering property garages and for legacy qb-garages-shaped integrations.

Namespace: `exports.kora_garages` · Source: `server/property.lua, server/compat.lua`

### Functions

Three server exports.

#### `exports.kora_garages:RegisterPropertyGarage(id, definition, callback)`

Server export. Registers (or updates, if your own resource already owns `id`) a persistent, capacity-limited garage backed by `kora_garages_property_garages`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | 1-50 characters, must not collide with an existing non-property garage or one owned by another resource. |
| `definition` | table | `{ coords, spawns? \| spawn, slots, retrievalOnly?, capacityOwnerIds? }`. `coords`/each spawn must be a finite vector3/vector4-like table. `slots` is a positive integer ≤ 1000. `spawns` defaults to a single-element list from `spawn`. `capacityOwnerIds?` restricts the slot count to only those citizenids' stored vehicles. |
| `callback` | function | Called as `callback(src, action, id)` for every `'store'`, `'retrieve'` or `'list'` attempt; must return `true` to allow it. |

**Returns**

- **ok** — `true` on success.
- **err** — `false, <message>` if persistence is not ready yet, the callback is not callable, the id is already owned elsewhere or collides with a built-in garage, or the definition is invalid.

**Example**

```lua
-- another resource, e.g. kora_housing, registering a persistent garage
local ok, err = exports.kora_garages:RegisterPropertyGarage('house_123', {
    coords = vector4(120.0, -800.0, 30.0, 180.0),
    spawns = { vector4(118.0, -805.0, 30.0, 180.0) },
    slots = 4,
    retrievalOnly = false,
    capacityOwnerIds = { 'ABC12345' }, -- optional: only these citizenids count against 'slots'
}, function(src, action, id)
    -- action is 'store', 'retrieve' or 'list'; return true to allow
    return exports.kora_housing:hasKeyToProperty(src, id)
end)
if not ok then print('garage registration failed:', err) end
```

**Representative console output**

```text
Blocks (via `Kora.sql`) until the registration is written to `kora_garages_property_garages`; a second write for the same id updates the stored definition. Broadcasts `kora_garages:propertyRegistered` to every client so their zone appears.
```

#### `exports.kora_garages:UnregisterPropertyGarage(id)`

Server export. Disables a garage this resource previously registered.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | A garage id this resource owns (per `Property.known`). |

**Returns**

- **ok** — `true` on success.
- **err** — `false, 'Garage is not owned by this resource.'` otherwise.

**Example**

```lua
exports.kora_garages:UnregisterPropertyGarage('house_123')
```

**Representative console output**

```text
Also runs automatically for every garage owned by a resource when that resource stops (`onResourceStop`). Marks the garage `disabled` and broadcasts `kora_garages:propertyRemoved`; it is not deleted from the database, so re-registering the same id restores it.
```

#### `exports.kora_garages:getAllGarages()`

Server export (defined in `server/compat.lua`). Returns every non-disabled garage reshaped for older qb-garages-style blip/UI code.

**Parameters**



**Returns**

- **garages** — array of `{ name, label, type, takeVehicle, putVehicle, spawnPoint, showBlip, blipName, blipNumber, blipColor, vehicle }`. `takeVehicle`/`putVehicle` are both the garage's `coords`.

**Example**

```lua
local garages = exports.kora_garages:getAllGarages()
```

**Representative console output**

```text
`vehicle` is hardcoded to `'car'` regardless of the garage's actual vehicle types — unclear whether any consumer relies on that field.
```

### Limits and related APIs

Server only.

## Client

One client-side export to open the garage UI programmatically.

Namespace: `exports.kora_garages` · Source: `client/client.lua`

### Functions

One client export.

#### `exports.kora_garages:openGarage(id)`

Client export. Opens the garage NUI app for `id` as if the player had interacted with its zone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | Key into `Config.garages`. |

**Returns**

- **ok** — `true` if the garage exists and is not disabled.
- **err** — `false, 'Garage is unavailable.'` otherwise.

**Example**

```lua
exports.kora_garages:openGarage('legionsquare')
```

**Representative console output**

```text
Useful for a custom interaction (e.g. a different prompt/keybind) that still wants the stock garage UI and store/take-out flow.
```

### Limits and related APIs

Client only.

## Additional details from the code

### RegisterPropertyGarage rules

`definition` field rules:

| Field | Rule |
| --- | --- |
| `coords` | Required point with `x`, `y`, `z` |
| `spawn` or `spawns` | At least one, at most 100 points; `spawns` wins |
| `slots` | Required integer from 1 to 1000 |
| `label` | Optional, truncated to 100 chars; defaults to the id |
| `retrievalOnly` | `true` disables storing |
| `capacityOwnerIds` | Optional list of citizen id strings (1 to 50 chars) to count toward capacity |

- `callback(source, action, id)` must return exactly `true` to allow; `action` is `list`, `store` or `retrieve`. Errors or any other value deny.
- It fails until the garage schema is ready (`kora_garages:ready`).
- A garage id may only be updated by the resource that registered it, and cannot reuse an id from `Config.garages`.
- The definition is saved in `kora_garages_property_garages` with the invoking resource as provider, and clients are told through `kora_garages:propertyRegistered`.
- After a restart, saved garages are loaded as disabled until the provider registers them again.

### UnregisterPropertyGarage rules

Only the owning resource may call it (`false, message` otherwise). It disables the garage and removes client zones; the database row and vehicles are kept. Garages are also disabled when the owning resource stops.

### getAllGarages and qb-garages

The manifest has `provide 'qb-garages'`, so the same export is reachable as `exports['qb-garages']:getAllGarages()`. See [Compatibility](../compatibility.md).

### openGarage

Returns `true` after scheduling the garage UI, or `false, 'Garage is unavailable.'` for an unknown or disabled id. Server policies still check each operation.
