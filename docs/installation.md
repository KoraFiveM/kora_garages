---
title: Installation
sidebar_position: 2
---

# Installation

## Declared dependencies

`fxmanifest.lua` declares these dependencies:

| Resource | Used for |
| --- | --- |
| `kora_theme` | Declared in the manifest; no direct use in this resource's code |
| `kora_lib` | `Kora.callback`, `Kora.nui`, `Kora.notify`, `Kora.zones`, `Kora.interact`, `Kora.blips`, `Kora.vehicle`, `Kora.distance`, `Kora.sql` helpers |
| `kora_core` | Player data, job and gang, owned vehicles (`getByOwner`, `getByPlate`, `storeVehicle`, `spawnVehicle`), money, shared vehicle data |
| `kora_target` | Interaction zones |
| `kora_sql` | Database access and schema creation |

## Used but not declared

| Resource | Used for |
| --- | --- |
| `kora_vehiclekeys` | `exports.kora_vehiclekeys:giveKeys` is called after a vehicle is taken out. It is not listed as a dependency. |

## Steps

1. Place the resource in your resources folder.
2. Start it after its dependencies:

   ```cfg
   ensure kora_theme
   ensure kora_lib
   ensure kora_core
   ensure kora_sql
   ensure kora_target
   ensure kora_vehiclekeys
   ensure kora_garages
   ```

3. No manual SQL import is needed. The resource creates `kora_garages_property_garages` itself (see [Database](./database.md)). It reads and updates `player_vehicles`, which is created by `kora_core`.
4. Edit [Configuration](./configuration.md) to define garages.
