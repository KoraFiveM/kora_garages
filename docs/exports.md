---
title: Exports
sidebar_position: 6
---

# Exports

## Server

### RegisterPropertyGarage

```lua
local ok, err = exports.kora_garages:RegisterPropertyGarage(id, definition, callback)
```

Registers or refreshes a runtime garage. Returns `true`, or `false, message`.

`definition` fields:

| Field | Rule |
| --- | --- |
| `coords` | Required point with `x`, `y`, `z` |
| `spawn` or `spawns` | At least one, at most 100 points; `spawns` wins |
| `slots` | Required integer from 1 to 1000 |
| `label` | Optional, truncated to 100 chars; defaults to the id |
| `retrievalOnly` | `true` disables storing |
| `capacityOwnerIds` | Optional list of citizen id strings (1 to 50 chars) to count toward capacity |

`id` is a string of 1 to 50 characters. `callback(source, action, id)` must return exactly `true` to allow; `action` is `list`, `store` or `retrieve`. Errors or any other value deny.

Rules from the code:

- It fails until the garage schema is ready (`kora_garages:ready`).
- A garage id may only be updated by the resource that registered it, and cannot reuse an id from `Config.garages`.
- The definition is saved in `kora_garages_property_garages` with the invoking resource as provider, and clients are told through `kora_garages:propertyRegistered`.
- After a restart, saved garages are loaded as disabled until the provider registers them again.

Example:

```lua
exports.kora_garages:RegisterPropertyGarage('home-1', {
    label = 'Home', coords = vector3(0.0, 0.0, 70.0),
    spawn = vector4(5.0, 0.0, 70.0, 90.0), slots = 2,
}, function(source, action, id)
    return hasPermission(source, id, action)
end)
```

### UnregisterPropertyGarage

```lua
exports.kora_garages:UnregisterPropertyGarage(id)
```

Only the owning resource may call it (`false, message` otherwise). It disables the garage and removes client zones; the database row and vehicles are kept. Garages are also disabled when the owning resource stops.

### getAllGarages

Provided as `exports['qb-garages']:getAllGarages()` (the manifest has `provide 'qb-garages'`). Returns a list of non-disabled garages in the qb-garages shape. See [Compatibility](./compatibility.md).

## Client

### openGarage

```lua
local ok, err = exports.kora_garages:openGarage(id)
```

Returns `true` after scheduling the garage UI, or `false, 'Garage is unavailable.'` for an unknown or disabled id. Server policies still check each operation.
