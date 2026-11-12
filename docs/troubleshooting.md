---
title: Troubleshooting
sidebar_position: 11
---

# Troubleshooting

- **No keys after take-out, or an error on take-out** - `kora_vehiclekeys` is called but not declared as a dependency; make sure it is started.
- **Option has no effect** - several `Config` entries are not read by the code, see [Configuration](./configuration.md) (for example `interaction.mode`, `impound.account`, `listing`, `houseGarages.query`).
- **Markers appear although you expected none** - `Config.markers.enabled` ships as `true`.
- **Impound fee charged from cash, not bank** - the fee always uses `cash`.
- **Property garage unavailable after restart** - saved garages stay disabled until the provider calls `RegisterPropertyGarage` again (listen for `kora_garages:ready`). Registration fails until the schema is ready.
- **"Invalid or conflicting property garage"** in the console - a saved id is invalid or clashes with `Config.garages`; loading stops at that row and the garage system stays not ready.
- **"Could not spawn that vehicle"** - spawn timed out, the entity id did not match, or the state update did not change exactly one row.
- **"There is no free spot"** - every spawn point has a vehicle within `Config.spawn.clearance`.
- **Vehicle left out after a restart** - on start every `out` vehicle is set back to `garaged`.
