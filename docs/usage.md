---
title: Using garages
sidebar_position: 4
---

# Using garages

## Opening a garage

Every garage in `Config.garages` gets a `kora_target` box zone through `Kora.interact.addBoxZone`. The option reads "Open (label)", or "Collect from (label)" at an impound. It only shows when the player may use the garage:

- job garage: the player has the job, and is on duty if `Config.garageTypes.job.requireDuty` is true;
- gang garage: the player is in the gang;
- anything else: always.

The server repeats these checks (and the distance check) for every callback. Opening shows a `kora_lib` NUI app "kora_garages:garage" with a searchable card list (9 per page) and a count badge. Other resources can open it with the `openGarage` export.

## Vehicle list

The server lists the caller's vehicles from `kora_core`:

- At a normal garage: vehicles not impounded and not parked in a protected property garage.
- At an impound garage: only impounded vehicles.
- At a property garage: only vehicles whose `garage_id` equals that garage.

Each entry has plate, model, state and, if impounded, the fee. The client shows state "In the garage", "Out on the street" or "Impounded". Actions: "Take out" for garaged vehicles, "Pay (fee) and release" for impounded ones, "Store" for vehicles that are out (hidden when the garage type has `allowStore = false`).

## Taking a vehicle out

1. Server `kora_garages:takeOut` checks garage, distance, access and ownership, refuses vehicles already out, and refuses impounded vehicles outside an impound garage.
2. It picks the first spawn point with no vehicle within `Config.spawn.clearance` and spawns the vehicle server-side in the player's routing bucket.
3. The client waits for the entity (up to `Config.spawn.timeout`) and calls `kora_garages:confirmOut`. If it never appears, `cancelOut` is called and nothing changes.
4. On confirm, an impounded vehicle charges the fee from cash. The `player_vehicles.state` is then set to `out`; if that update does not affect exactly one row the entity is deleted. On success the server tags the entity with the `vehicleid` state bag via `kora_core:tagVehicle` (ignored if that export is missing) and gives keys through `kora_vehiclekeys`.
5. The client re-applies stored mods (`Config.spawn.applyMods`) and optionally warps the player in.

Property garages use `kora_core:spawnVehicle` instead and also give keys.

On resource start, all vehicles whose state is `out` are set back to `garaged`.

## Storing a vehicle

The client finds the vehicle by plate (current vehicle or nearby within `storeDistance`), makes the player leave it, and sends fuel and vehicle properties to `kora_garages:store`. The server verifies:

- garage access and distance, ownership;
- the entity is a vehicle with a matching plate, in the same routing bucket, within `storeDistance`, and not occupied by another player;
- fuel is a number from 0 to 100 and mods are a table of at most 131072 JSON bytes.

It then writes state `garaged`, mods, engine and body health and fuel, records `garage_id` when `Config.RecordGarageId` is on (not for impound garages), and deletes the entity. Impound garages with `allowStore = false` only hide the button on the client; the server store callback has no `allowStore` check.

Property garages additionally check capacity (`slots`, counted from `garaged` vehicles with that `garage_id`, optionally only `capacityOwnerIds`) and use `kora_core:storeVehicle`.

### Recovery from a property garage

A vehicle that is out, and whose last garage is a registered property garage, may be stored at a public garage regardless of property access. This moves its garage association to the public garage. A vehicle still parked in a property garage cannot be listed or taken out at public garages.

## Cosmetic protection

With `Config.TrustClientCosmetics = false` (default), parking never changes the stored look. Keys in `Config.mods.cosmetic`, every key starting with `mod` plus an uppercase letter, and numeric mod indexes 0 to 49 are kept from the database; other state comes from the client. If a vehicle has no stored look, nothing cosmetic is stored unless `Config.SaveUnstoredLook = true`. Setting `TrustClientCosmetics = true` stores whatever the client sends.

## Impound fee

The fee is the vehicle's `impound_fee` column or `Config.impound.defaultFee`, never above `Config.impound.maxFee`. It is removed from `cash` with reason `impound-fee`.

## Property garage registration

See [Exports](./exports.md). Registered garages are saved in the database, are disabled after a restart until their provider registers them again, and are disabled immediately when the provider stops or unregisters.
