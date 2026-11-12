---
title: "How to use"
sidebar_position: 3
---


# How to use

Vehicles are interacted with through kora_target zones (or a plain box interaction) drawn at each `Config.garages` entry. Opening a garage shows a kora_lib NUI app listing the player's vehicles there; picking one either stores it (if out) or takes it out (if garaged/impounded). All server-side validation happens in the `kora_garages:*` callbacks — the client never decides whether a store/take-out is allowed.

## Store flow

The client finds the vehicle near the player (by plate, including the one they are currently sitting in — it is tasked out first), reads its fuel and mod properties with kora_lib natives, and sends them to the server. The `kora_garages:store` callback is the authority: it re-resolves the entity from the given `netId` (falling back to a plate scan if the netId no longer matches), then rejects the call unless the entity is actually a vehicle, carries the claimed plate, sits in the player's own routing bucket, is within `Config.interaction.storeDistance`, and is unoccupied by anyone else. Fuel must be a finite 0–100 number and `mods` must be a table under 128KB of JSON.

```lua title="client/client.lua"
-- client/client.lua (simplified): mods/fuel come from client-only natives,
-- the server treats everything here as untrusted and re-validates it.
local stored, err = Kora.callback.trigger('kora_garages:store', garageId, plate,
    NetworkGetNetworkIdFromEntity(entity), GetVehicleFuelLevel(entity), Kora.vehicle.getProperties(entity))
if not stored then return notify(err or 'You cannot store that here.') end
```

- Cosmetic mod fields (`Config.mods.cosmetic`, every `mod*` key, and numeric mod indexes 0-49) are only trusted from the client when `Config.TrustClientCosmetics` is `true`. Otherwise the server keeps whatever look was already stored (see `PropertyGarages.resolveMods`), so an unpaid paint/tint preview is discarded on store.
- A job/gang garage now enforces `canUseGarage(..., 'store')` on the server (on-duty for job garages, correct gang for gang garages) — a client can no longer store into a restricted garage it merely sees the zone for.
- Storing writes `state = 'garaged'` plus the engine/body health and fuel snapshot. `Config.RecordGarageId` additionally writes `garage_id` unless the garage is an impound lot.

## Take-out flow (three-step handshake)

Taking a non-property vehicle out is a three-call handshake, not one callback, to avoid handing out a vehicle the client never actually saw spawn.

```lua title="client/client.lua"
-- client/client.lua (simplified three-step handshake)
local result, err = Kora.callback.trigger('kora_garages:takeOut', garageId, plate)
if not result then return notify(err or 'You cannot take that out.') end

local entity = waitForEntity(result.netId, result.timeout)
if not entity then
    Kora.callback.trigger('kora_garages:cancelOut', plate)  -- never confirmed: server discards the spawned entity
    return notify('Your vehicle did not spawn, it is still in the garage.')
end

local confirmed, confirmErr = Kora.callback.trigger('kora_garages:confirmOut', plate, result.netId)
if not confirmed then return notify(confirmErr or 'Your vehicle did not spawn.') end
```

1. **kora_garages:takeOut** — Server re-checks garage membership/on-duty/ACL (`canUseGarage`), ownership (`ownsVehicle`), and that the vehicle isn't already `out` or impounded-elsewhere. It claims a per-plate re-entrancy lock (`pendingOut[plate]`) before spawning, so a second take-out call for the same plate fails immediately with `'That vehicle is already being brought out'` instead of racing the first and producing two vehicles. The spawned entity is put in the player's own routing bucket and returned as `{ netId, mods, timeout }`.

2. **kora_garages:confirmOut (or cancelOut)** — If the client sees the entity within `timeout` it calls `confirmOut(plate, netId)`, which re-verifies the pending record belongs to that `src` and that the netId still matches the spawned entity, charges the impound fee if the vehicle was impounded, then writes `state = 'out'`. If that DB update does not affect exactly one row, the spawned entity is deleted and the call fails — a failed write no longer leaves a client holding keys to a vehicle the database still thinks is garaged. If the client never sees the entity in time, it calls `cancelOut(plate)` instead and the pending entity is discarded.

3. **Auto-discard** — A `SetTimeout` for `Config.spawn.timeout + 5000` ms also discards the pending entity server-side if neither confirm nor cancel ever arrives (e.g. the client disconnected).

## Impound

An impound-type garage (`Config.garageTypes.impound`, `allowStore = false`) lists only the player's impounded vehicles. Taking one out goes through the same `takeOut`/`confirmOut` handshake; `confirmOut` charges `tonumber(vehicle.impound_fee) or Config.impound.defaultFee` from the `cash` account via `exports.kora_core:removeMoney` before releasing it — if the player can't pay, the spawned entity is deleted and the vehicle stays impounded.

## Property (persistent) garages

A property garage (house, business, etc.) is registered at runtime with `RegisterPropertyGarage`, not written into `Config.garages` by hand. Once registered it behaves like any other garage client-side (zone, marker, NUI list), but store/retrieve calls are routed to `PropertyGarages.store`/`PropertyGarages.takeOut`, which call the registering resource's `callback(src, action, id)` for every store/retrieve/list and enforce a capacity (`slots`, optionally scoped to `capacityOwnerIds`) and a per-garage write lock so two simultaneous store/retrieve calls on the same garage or plate are serialized (`withWrite`).

```text title="any resource"
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

- A public (non-property) garage can still act as a one-time "recovery" path for a vehicle whose `garage_id` points at a property garage: if the vehicle is `out` and the garage is `public`, `kora_garages:store` calls `PropertyGarages.store(..., recovered = true)`, which re-checks that specific condition instead of the owning resource's callback.
- Property garage definitions persist in `kora_garages_property_garages` and are reloaded (as `disabled = true` placeholders, re-enabled once the owning resource re-registers) on every boot, so a restarted provider resource does not lose capacity bookkeeping.
- If the provider resource stops (`onResourceStop`) or calls `UnregisterPropertyGarage`, the garage is marked `disabled` and a `kora_garages:propertyRemoved` event tears down its client-side zone.

## Reference: garage behaviour in detail


### Opening a garage

Every garage in `Config.garages` gets a `kora_target` box zone through `Kora.interact.addBoxZone`. The option reads "Open (label)", or "Collect from (label)" at an impound. It only shows when the player may use the garage:

- job garage: the player has the job, and is on duty if `Config.garageTypes.job.requireDuty` is true;
- gang garage: the player is in the gang;
- anything else: always.

The server repeats these checks (and the distance check) for every callback. Opening shows a `kora_lib` NUI app "kora_garages:garage" with a searchable card list (9 per page) and a count badge. Other resources can open it with the `openGarage` export.

### Vehicle list

The server lists the caller's vehicles from `kora_core`:

- At a normal garage: vehicles not impounded and not parked in a protected property garage.
- At an impound garage: only impounded vehicles.
- At a property garage: only vehicles whose `garage_id` equals that garage.

Each entry has plate, model, state and, if impounded, the fee. The client shows state "In the garage", "Out on the street" or "Impounded". Actions: "Take out" for garaged vehicles, "Pay (fee) and release" for impounded ones, "Store" for vehicles that are out (hidden when the garage type has `allowStore = false`).

### Taking a vehicle out

1. Server `kora_garages:takeOut` checks garage, distance, access and ownership, refuses vehicles already out, and refuses impounded vehicles outside an impound garage.
2. It picks the first spawn point with no vehicle within `Config.spawn.clearance` and spawns the vehicle server-side in the player's routing bucket.
3. The client waits for the entity (up to `Config.spawn.timeout`) and calls `kora_garages:confirmOut`. If it never appears, `cancelOut` is called and nothing changes.
4. On confirm, an impounded vehicle charges the fee from cash. The `player_vehicles.state` is then set to `out`; if that update does not affect exactly one row the entity is deleted. On success the server tags the entity with the `vehicleid` state bag via `kora_core:tagVehicle` (ignored if that export is missing) and gives keys through `kora_vehiclekeys`.
5. The client re-applies stored mods (`Config.spawn.applyMods`) and optionally warps the player in.

Property garages use `kora_core:spawnVehicle` instead and also give keys.

On resource start, all vehicles whose state is `out` are set back to `garaged`.

### Storing a vehicle

The client finds the vehicle by plate (current vehicle or nearby within `storeDistance`), makes the player leave it, and sends fuel and vehicle properties to `kora_garages:store`. The server verifies:

- garage access and distance, ownership;
- the entity is a vehicle with a matching plate, in the same routing bucket, within `storeDistance`, and not occupied by another player;
- fuel is a number from 0 to 100 and mods are a table of at most 131072 JSON bytes.

It then writes state `garaged`, mods, engine and body health and fuel, records `garage_id` when `Config.RecordGarageId` is on (not for impound garages), and deletes the entity. Impound garages with `allowStore = false` only hide the button on the client; the server store callback has no `allowStore` check.

Property garages additionally check capacity (`slots`, counted from `garaged` vehicles with that `garage_id`, optionally only `capacityOwnerIds`) and use `kora_core:storeVehicle`.

#### Recovery from a property garage

A vehicle that is out, and whose last garage is a registered property garage, may be stored at a public garage regardless of property access. This moves its garage association to the public garage. A vehicle still parked in a property garage cannot be listed or taken out at public garages.

### Cosmetic protection

With `Config.TrustClientCosmetics = false` (default), parking never changes the stored look. Keys in `Config.mods.cosmetic`, every key starting with `mod` plus an uppercase letter, and numeric mod indexes 0 to 49 are kept from the database; other state comes from the client. If a vehicle has no stored look, nothing cosmetic is stored unless `Config.SaveUnstoredLook = true`. Setting `TrustClientCosmetics = true` stores whatever the client sends.

### Impound fee

The fee is the vehicle's `impound_fee` column or `Config.impound.defaultFee`, never above `Config.impound.maxFee`. It is removed from `cash` with reason `impound-fee`.

### Property garage registration

See [Exports](./api/exports.md). Registered garages are saved in the database, are disabled after a restart until their provider registers them again, and are disabled immediately when the provider stops or unregisters.
