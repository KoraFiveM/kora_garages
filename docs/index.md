# qbgarages

Player-owned vehicle garages for the qblib framework: store and retrieve your own
cars, a job motor pool, a gang lockup, and an impound lot that charges to release
what it is holding.

qbgarages owns **no vehicle data at all**. Ownership, condition and impound state
live in qbcore's `player_vehicles` table and are reached only through
`Core.garage.*` (`exports.qbcore:getByPlate`, `getByOwner`, `spawnVehicle`,
`storeVehicle`, `impound`, `retrieveImpound`). This resource is the gameplay and
UI layer on top: zones, blips, a React panel, and the rules about *who may do
what, where*.

---

## The authority rule

> The browser sends a **garage id** and a **plate**. That is the complete list.

Both are intent, never data. On every single action the server re-resolves:

| Fact | Where it is re-read from | Refusal |
| --- | --- | --- |
| The garage | `Config.garages[id]` | `unknown garage` |
| The character | `exports.qbcore:getPlayerData(src, {'citizenid'})` | `no loaded character` |
| Job / gang / duty | `exports.qbcore:getJob` / `getGang` | `this garage is not for your job`, `you must be on duty`, `this garage is not for your gang` |
| Routing bucket | `GetPlayerRoutingBucket(src)` vs `garage.bucket` | `garage is not in your world` |
| Position | `GetEntityCoords(GetPlayerPed(src))` | `too far from the garage` |
| Ownership | `exports.qbcore:getByPlate(plate).citizenid` | `not your vehicle` |
| The live vehicle (store) | `NetworkGetEntityFromNetworkId`, then its own plate | `that is not the same vehicle` |
| Condition (store) | `GetVehicleEngineHealth`/`BodyHealth`/`FuelLevel` on the entity | — |

No coordinate, condition value, fee or vehicle record is ever accepted from a
client. Every native is reached through a `type(...) == 'function'` guard and a
missing one **fails the check** rather than skipping it, so a future FXServer
that moved a native client-side degrades into "refused", not "unchecked".

### The one exception: mods

Mod state is only readable through client-only natives, so the properties blob a
client sends on store is the only possible source. It is filtered to a
**cosmetic allow-list** (`Config.mods.cosmetic`) server-side, which is what makes
it harmless: colours, wheels, liveries and extras survive; `modEngine`,
`modBrakes`, `modTransmission`, `modSuspension`, `modArmor` and `modTurbo` are
dropped, as are `plate`, `model`, `engineHealth`, `bodyHealth` and `fuelLevel`.

A garage must never be a free performance-upgrade shop — that is a tuner's job,
and a tuner charges for it.

---

## Garage types

A **type** is a policy, not a location. It decides who may use a garage, whether
the listing shows garaged or impounded vehicles, and which pause-map legend
heading the blips collapse under.

| Type | Who | Lists | Store |
| --- | --- | --- | --- |
| `public` | anyone | garaged | yes |
| `private` | anyone (a `categories` allow-list is the usual point) | garaged | yes |
| `job` | the garage's own `job`, on duty | garaged | yes |
| `gang` | the garage's own `gang` | garaged | yes |
| `impound` | anyone, for their own held vehicles | impounded | **no** |

Storing at an impound lot is refused deliberately: the row is already held by the
lot, and a store would clear the impound state without charging for it.

### Allowed vehicles are **categories**, not GTA classes

`garage.categories` is an allow-list of qbcore shared-vehicle categories (the
`category` field in `qbcore/shared/vehicles.lua`). GTA's own vehicle class comes
from `GetVehicleClass`, which needs a live entity — and on take-out there is no
entity yet, so a class check would only ever run on *store* and a boat-only
garage could still be used to retrieve a jet. The category is on the row's model,
so one rule applies in both directions.

A model that is **not in the registry** is accepted anywhere. The allow-list
exists to keep a plane out of a street garage, not to be a whitelist of
purchasable cars — refusing unregistered models would make every addon vehicle
unretrievable the moment one garage grew a `categories` list.

### Job and gang garages list your OWN vehicles

A job or gang garage is an **access policy** (who may park here, and which
categories), not a separate fleet view. Fleet rows — the ones qbcore keys by
`job` with no `citizenid` — are reachable by plate through take-out, store and
the legacy `checkOwner` callback, but they are **not listed**, because qbcore
exposes no `getByJob` and reaching into `player_vehicles` behind its back is
exactly what this resource must not do. See "Known gaps" below.

---

## Blips and the pause-map legend

Every blip supplies its own location name (for example,
`Legion Square Parking`) and the label from its **type**
(`Config.garageTypes[type].blipLabel`) as its named category. qblib composes
the visible label (`Garage: Legion Square Parking`) while grouping Garage, Job
Garage, Gang Garage, and Impound locations beneath their respective
pause-map legend headings — see `qblib/modules/blips/docs.md`.

`public` and `private` deliberately share the label `Garage`: to a player, both
are just a garage. The specific name still appears in whichever interaction
prompt the server has configured.

---

## Interaction

`Config.interaction.mode` selects one of two client presentations while keeping
the same server-side distance, entitlement and routing-bucket checks:

| Mode | Player flow |
| --- | --- |
| `target` (default) | Aim at the garage zone with qbtarget, then release Alt. |
| `interact` | Enter the garage box, then press E on qblib's nearby selector. |

Target registrations are removed before they are rebuilt, so a repeated
registration cannot leave two identical options at Legion Square. They are also
re-created after a `qbtarget` restart. Interact zones use stable
`qbgarages:<garage-id>` names, which qblib replaces rather than duplicates.

`canInteract` is a UX convenience only. It reads the local `PlayerData` mirror so
a motor pool does not prompt every passing civilian; the real gate is
`Garages.access.entitled`, re-read from qbcore server-side. The interaction box
may cover more of the apron than `Config.interaction.distance`; the tighter
server distance is what authorises the action. **"The prompt appeared" is never
proof of range.**

---

## Impound

Retrieval charges the fee **before** clearing the flag:

1. `Garages.api.impoundFee(row)` — the row's own `impound_fee`, falling back to
   `Config.impound.defaultFee`, clamped to `Config.impound.maxFee`.
2. `exports.qbcore:removeMoney(src, Config.impound.account, fee, reason)`.
   A refusal (`insufficient funds`) ends the action here, with the vehicle still
   held.
3. `exports.qbcore:retrieveImpound(src, plate)` clears the flag.
4. An ordinary take-out spawns it.

The order is the whole design. Clearing first and charging afterwards makes an
unaffordable retrieval into a *free* one, because the row is already `garaged` by
the time the charge fails. If step 3 fails after step 2 succeeded, the fee is
**refunded** — a player who is charged and gets nothing has no way to recover.

If step 4 fails, the vehicle is already released and paid for, so it is
retrievable from any garage. That is a far better failure than a paid fee and a
still-impounded row.

---

## Server exports

### `exports.qbgarages:impound(plate, fee, impoundLot)`

Impounds a plate and records the fee on the row. Clamps to
`Config.impound.maxFee`. Returns `true`, or `false, reason`.

Charges nothing — the fee is collected at the lot, when the player is standing
there and can actually afford it.

### `exports.qbgarages:isOwner(src, plate)`

Whether `src`'s character owns `plate`. Answers with a boolean rather than the
row, which carries the owner citizenid and the vehicle's last known position.

### `exports.qbgarages:getGarages()`

A fresh copy of the garage config: `id`, `label`, `type`, `job`, `gang`, `coords`.
A copy, so a consumer cannot edit this resource's live config through the
reference.

## Client exports

| Export | Notes |
| --- | --- |
| `exports.qbgarages:openGarage(id)` | Opens the panel. Returns `false` for an unknown id; the server still decides everything else. |
| `exports.qbgarages:closeGarage()` | Closes it and releases NUI focus. |
| `exports.qbgarages:isGarageOpen()` | — |

---

## Callbacks (client → server)

The complete client-facing surface. Anything else appearing here is a new attack
surface that needs its own review.

| Callback | Arguments | Returns |
| --- | --- | --- |
| `qbgarages:list` | `garageId` | `{ garage, vehicles }` or `false, reason` |
| `qbgarages:takeOut` | `garageId, plate` | `{ netId, plate, spawn, mods, warp }` or `false, reason` |
| `qbgarages:store` | `garageId, plate, netId, mods` | `true` or `false, reason` |
| `qbgarages:retrieveImpound` | `garageId, plate` | `{ netId, plate, fee, ... }` or `false, reason` |

All four are rate limited per player.

> A timed-out `QB.callback.trigger` returns **no values at all** — `nil`, not
> `false`. The client treats that as "the garage did not answer", never as a
> refusal. Reporting a timeout as a refusal is the classic version of this bug.

---

## qb-garages compatibility

`provide 'qb-garages'` plus the real `qb-garage:*` names, so a resource written
against [qbcore-framework/qb-garages](https://github.com/qbcore-framework/qb-garages)
keeps working unmodified. Toggle with `Config.compat.legacy`.

| Legacy name | Kind | Notes |
| --- | --- | --- |
| `qb-garage:server:GetGarageVehicles` | callback | Plate-keyed table, as upstream. |
| `qb-garage:server:GetDepotVehicles` | callback | Finds the impound lot by *type*; upstream had one global depot and took no argument. |
| `qb-garage:server:checkOwner` | callback | `(owned, wireRecord)`. The `gang` argument is dropped — membership is read from qbcore. |
| `qb-garage:server:IsSpawnOk` | callback | Answered by the server's own free-space search. Upstream asked the *client*. |
| `qb-garage:server:GetVehicleProperties` | callback | Ownership-gated: the mods blob is a fair description of somebody's car. |
| `qb-garage:server:updateVehicleState` | event | Only the garage-**in** transition (`state == 1`) is honoured, and only with a network id. Condition values are dropped. |
| `qb-garage:server:PayDepotPrice` | event | The caller's `depotPrice` is **ignored**; the row's fee is charged. |
| `qb-garage:client:takeOutGarage` | event | Reads the plate only, and requires an open panel for garage context. |

Every one funnels into the same `Garages.access`/`Garages.api` functions the
native path uses, so a legacy consumer gets the same ownership, distance and
routing-bucket checks. **Nothing in the compat layer is a new mutation
primitive.**

Upstream's `type`/`category`/`gang` arguments are accepted and ignored wherever
this resource resolves the same fact authoritatively — they were the client
telling the server what kind of garage it was standing in, which is precisely
the class of claim this design refuses.

`exports['qb-garages']:*` is **not** provided. Real qb-garages exposes its API as
events and callbacks, which are all bridged above; the export-identity hijack
qbcore uses for `exports['qb-core']:GetCoreObject()` is not replicated here
because there is no upstream export surface to replicate.

---

## Configuration

Everything lives in `config.lua`, one sub-table per area, every value commented.
The load-bearing ones:

| Key | Meaning |
| --- | --- |
| `interaction.distance` | Metres the server allows an action from the garage point. |
| `interaction.storeDistance` | Metres a stored vehicle may be from it. Wider on purpose — a player at the marker can legitimately have parked a few spaces away. |
| `interaction.requireSameBucket` | Bucket separation. Fails closed if the natives are missing. |
| `garages[id].bucket` | **Explicit and numeric.** A missing bucket is a config error and refuses every action: "any bucket" must not be something a garage can mean by omission, or an instanced apartment garage becomes reachable from the open world. |
| `garages[id].spawns` | A list even where one point would do. One point puts the second player to retrieve a car inside the first one's bumper. |
| `spawn.clearance` | Metres a spawn point must be clear of other vehicles. Checked against the server's own entity list. |
| `spawn.warpIntoVehicle` | Off by default: a garage that teleports you into a plane you asked to *look at* is a surprise. |
| `impound.defaultFee` | Applied when the impounding resource recorded none. Non-zero on purpose — a zero default makes every impound free by accident. |
| `mods.cosmetic` | The allow-list described above. |

`test/smoke/config.lua` checks the shipped config against the rules the code
relies on: every garage has a known type and a numeric bucket, every spawn point
has a heading, spawn points are far enough apart to be separate spaces and close
enough to be storable, and every type shares one blip label.

---

## Known gaps

* **Job fleet listings.** qbcore exposes no `Core.garage.getByJob`, so a job
  garage lists the officer's own vehicles rather than the department's fleet.
  Fleet rows work by plate through every other path. Adding the listing needs a
  qbcore export, not a query in this resource.
* **Coordinates are plausible, not surveyed.** The seven shipped garages use
  well-known GTA V locations, and `test/smoke/config.lua` proves they are
  internally consistent (spawns reachable, spaced, headed), but no z-height has
  been confirmed against the live map.

---

## Tests

```
./test/run.sh
```

Plain lua5.4, no busted, no FXServer, no database. `test/mocks.lua` installs a
fully driven world — players with coordinates and buckets, entities with plates
and buckets, a vehicles table standing in for `player_vehicles`, and a money
ledger — so every refusal is reached deliberately rather than by luck. The
qbcore surface it mocks mirrors `qbcore/modules/garage/server.lua`'s real
*semantics*, not just its signatures.

| Suite | Covers |
| --- | --- |
| `access` | Unknown garage, unconfigured type, no character, out of range, wrong bucket, missing bucket native, wrong job, off duty, wrong gang, wrong owner, plate normalisation, fleet-row scoping. |
| `actions` | Listing scope and wire shape, the impound listing inversion, take-out, already-out, impounded, category refusal, a full garage, the server-side condition snapshot, plate/bucket/distance/entity-type refusals on store, storing at a lot, the mods filter. |
| `impound` | An unaffordable fee (nothing charged, still held), the charge-then-clear order, the fee refund on a failed clear, fee fallback and clamping, wrong garage type, wrong owner, out of range. |
| `compat` | Every legacy callback and event, and that each gets the same refusals as the native path — including that `PayDepotPrice` ignores the caller's price. |
| `config` | The shipped config against the rules the code relies on. |
