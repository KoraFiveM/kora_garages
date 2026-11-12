---
title: Events and callbacks
sidebar_position: 7
---

# Events and callbacks

## Server callbacks (Kora.callback)

| Name | Arguments | Result |
| --- | --- | --- |
| `kora_garages:getGarages` | none | The full `Config.garages` table |
| `kora_garages:houseGarages` | none | The full `Config.garages` table (used by the client to pick up garages it does not know) |
| `kora_garages:list` | garageId | `{ garage, vehicles }` or `false, message` |
| `kora_garages:takeOut` | garageId, plate | `{ netId, mods, timeout }` or `false, message` |
| `kora_garages:confirmOut` | plate, netId | `true` or `false, message` |
| `kora_garages:cancelOut` | plate | `true` |
| `kora_garages:store` | garageId, plate, netId, fuel, mods | `true` or `false, message` |
| `qb-garages:server:GetPlayerVehicles` | none | Stock qb-garages vehicle list; see [Compatibility](./compatibility.md) |

All garage callbacks validate on the server; see [Using garages](./how-to-use.md).

## Client net events

Sent by the server only.

| Event | Arguments | Effect |
| --- | --- | --- |
| `kora_garages:propertyRegistered` | id, garage | Adds or replaces the property garage zone |
| `kora_garages:propertyRemoved` | id | Removes the zone and marks the garage disabled |
| `qb-garages:client:setHouseGarage` | any | No-op |
| `qb-garages:client:houseGarageConfig` | any | No-op |
| `qb-garages:client:addHouseGarage` | any | No-op |

## Local events

| Event | Side | Meaning |
| --- | --- | --- |
| `kora_garages:ready` | server | Triggered after the property garage schema is ensured and saved garages are loaded. Providers should re-register their garages here. |

The client listens to `QBCore:Client:OnPlayerLoaded` and `kora_core:client:playerLoaded` to (re)create blips, and to `onResourceStart` for this resource.
