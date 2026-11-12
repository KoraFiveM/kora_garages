---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Garages handles storing and retrieving player-owned vehicles: public/private/job/gang garages, an impound lot with a release fee, and a `RegisterPropertyGarage` export that lets another resource (housing, businesses) register its own persistent garages. It also answers to the legacy resource names `kora_garages` and `qb-garages`.

## Install Kora Garages

1. **Add the folder** — Place `kora_garages` in your resources directory. Keep the folder name: other resources call `exports.kora_garages`.

2. **Dependencies** — Kora Garages declares `dependency` on `kora_theme`, `kora_lib`, `kora_core`, `kora_target` and `kora_sql`, and loads `@kora_lib/init.lua` and `@kora_core/init.lua` as shared scripts. Start it after all five.

   ```lua title="fxmanifest.lua"
   provide 'qb-garages'

   dependency 'kora_theme'
   dependency 'kora_lib'
   dependency 'kora_core'
   dependency 'kora_target'
   dependency 'kora_sql'

   shared_script '@kora_lib/init.lua'
   shared_script '@kora_core/init.lua'

   shared_scripts {
       'shared/config.lua',
   }

   server_scripts {
       '@kora_sql/init.lua',
       'server/schema.lua',
       'server/property.lua',
       'server/server.lua',
       'server/compat.lua',
   }

   client_scripts {
       'client/client.lua',
       'client/compat.lua',
   }
   ```

3. **Vehicle keys** — Taking a vehicle out calls `exports.kora_vehiclekeys:giveKeys(src, plate)`. kora_vehiclekeys does not need to be a declared dependency, but it must be running for keys to be handed over.

4. **Schema** — On boot, `server/property.lua` waits for `Kora.sql.ready()` and runs `Kora.sql.ensureTables(KoraGaragesSchema)`, which creates `kora_garages_property_garages` (`id` varchar(50) primary key, `provider` varchar(64), `definition` longtext) if missing. Vehicle rows themselves (`player_vehicles`) belong to kora_core, not this resource.

5. **Start it** — Add it to server.cfg after its dependencies.

   ```bash title="server.cfg"
   ensure kora_garages
   ```

## Legacy housing garages

On boot, `server/server.lua` checks whether a `houselocations` table exists (owned by an older housing resource, not kora_garages). If it does, every row with a non-null `garage` column (JSON `{x,y,z,w}`) is added as a `private` garage keyed `house_<name>`. This is purely additive and optional: on a database without that table nothing happens.

## Dependency details (from the code)


`fxmanifest.lua` declares these dependencies:

| Resource | Used for |
| --- | --- |
| `kora_theme` | Declared in the manifest. Not referenced in Lua code; per the `Config.ui.accent` comment the UI accent colour follows the theme unless `accent` is set |
| `kora_lib` | `Kora.callback`, `Kora.nui`, `Kora.notify`, `Kora.zones`, `Kora.interact`, `Kora.blips`, `Kora.vehicle`, `Kora.distance`, `Kora.sql` helpers |
| `kora_core` | Player data, job and gang, owned vehicles (`getByOwner`, `getByPlate`, `storeVehicle`, `spawnVehicle`), money, shared vehicle data |
| `kora_target` | Interaction zones |
| `kora_sql` | Database access and schema creation |

### Used but not declared

| Resource | Used for |
| --- | --- |
| `kora_vehiclekeys` | `exports.kora_vehiclekeys:giveKeys` is called after a vehicle is taken out. It is not listed as a dependency. |

### Setup notes

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
