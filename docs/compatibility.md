---
title: Compatibility
sidebar_position: 9
---

# Compatibility

## qb-garages

The manifest has `provide 'qb-garages'`.

- Callback `qb-garages:server:GetPlayerVehicles` returns the caller's own vehicles (`fullname`, `brand`, `model`, `plate`, `garage`, `state`, `fuel`, `engine`, `body`), or `nil` when there are none or when called more than once per second per player. Arguments are ignored. Garage is `None` with no garage, the garage label, or `House` for an unknown garage id.
- `exports['qb-garages']:getAllGarages()` is built from `Config.garages` (excluding disabled ones).
- Client events `setHouseGarage`, `houseGarageConfig` and `addHouseGarage` are accepted and ignored.
- `updateVehicleState` and `updateVehicleStats` are not registered.

## Legacy houselocations

At start the server checks `information_schema` for a `houselocations` table. If present, each row with a JSON `garage` coordinate becomes a `private` garage `house_<name>`, with no job or property policy. Modern housing should register property garages instead ([Exports](./api/exports.md)). House garages get no blip unless `Config.houseGarages.blip` is true.

## Vehicle id state bag

After take-out, the entity gets the server-only `vehicleid` state bag via `exports.kora_core:tagVehicle` so stock `ox_inventory` can skip a plate lookup. If that kora_core export is missing, the step is skipped. The convar that disables it (`kora:vehicleIdStateBag`) is not read by this resource; any such switch would live in `kora_core`.
