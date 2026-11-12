---
title: kora_garages
sidebar_position: 1
---

# kora_garages

`kora_garages` is the player vehicle garage for Kora servers. Players open a garage through a `kora_target` zone (via `Kora.interact`), see their owned vehicles in a `kora_lib` NUI app, take them out (with an impound fee at the impound lot) or park them again. It supports public garages, job and gang fleets, an impound lot, and runtime "property" garages that other resources (for example a housing resource) register through exports. The resource provides `qb-garages`, so legacy callers keep working.

Current version: see `version` in `fxmanifest.lua`.

## Features

- **Public, private, job, gang and impound garages** - defined in `Config.garages`, each with a type from `Config.garageTypes`. See [Configuration](./configuration.md).
- **Take out and park** - the server checks distance, garage access, ownership, spawn clearance, routing bucket, plate and occupancy. See [Using garages](./how-to-use.md).
- **Impound lot** - impounded vehicles are only listed at `impound` garages and cost a fee (stored `impound_fee` or `Config.impound.defaultFee`, capped by `Config.impound.maxFee`) taken from cash.
- **Property garages** - other resources register garages at runtime with `RegisterPropertyGarage`. See [Exports](./api/exports.md).
- **Cosmetic protection** - parking does not overwrite the stored vehicle look unless configured. See [Cosmetic protection](./how-to-use.md#cosmetic-protection).
- **Optional ground markers** - see [Configuration](./configuration.md#markers).
- **qb-garages compatibility** - see [Compatibility](./compatibility.md).

## Documentation map

- [Installation](./installation.md) - dependencies, manifest, schema and setup
- [How to use](./how-to-use.md) - store and take-out flows, impound, property garages, and detailed garage behaviour
- [Commands](./commands.md) - the `garage:storeAll` admin command
- [API reference](./api/index.md) - exports overview
  - [Exports](./api/exports.md) - server and client exports with parameters, returns and examples
- [Configuration](./configuration.md) - all `Config` options and which are actually used
- [Events and callbacks](./events.md) - callbacks, net events and local events
- [Database](./database.md) - tables and columns used
- [Compatibility](./compatibility.md) - qb-garages and legacy housing
- [Testing](./testing.md) - offline Lua tests and QA scenarios
- [Troubleshooting](./troubleshooting.md) - known caveats and problems
