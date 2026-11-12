---
title: Configuration
sidebar_position: 6
---

# Configuration

All options live in `shared/config.lua`. At the end of the file the table is passed through `Kora.config.adopt` when it exists.

## Interaction

| Option | Default | Used by code |
| --- | --- | --- |
| `Config.debug` | `false` | Yes: draws the `kora_target` zone outlines. |
| `Config.interaction.zoneSize` | `vector3(6, 6, 3)` | Yes: default box zone size; a garage may override with `size`. |
| `Config.interaction.distance` | `4.0` | Yes: server-side range check to open, list, take out or store at a garage. |
| `Config.interaction.storeDistance` | `12.0` | Yes: how close the vehicle must be to be stored. |
| `Config.interaction.mode` | `'target'` | No: not read anywhere. |
| `Config.interaction.requireSameBucket` | `true` | No: not read; the routing bucket check is always on. |

## Markers

Ground markers are drawn near garages the player may use. When `Config.markers.enabled` is not `true`, no marker zones are created. Proximity uses `Kora.zones.sphere` (`onEnter` and `onExit`); a per-frame `DrawMarker` loop only runs while at least one usable garage is within range.

| Option | Default in `shared/config.lua` | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Master switch. The comment in the file says off by default, but the shipped value is `true`. |
| `type` | `36` | `DrawMarker` type |
| `size` | `vector3(1, 1, 1)` | Marker scale |
| `color` | `r=60, g=180, b=255, a=150` | RGBA colour |
| `drawDistance` | `15.0` | Radius of the proximity sphere |
| `zOffset` | `0.0` | Added to the garage Z |
| `bobUpAndDown`, `rotate` | `false` | Marker animation |
| `houseGarages` | `false` | Also mark property garages |

Set `noMarker = true` on a garage entry to skip its marker.

## Garage types

`Config.garageTypes` has `public`, `private`, `job`, `gang` and `impound`. Each has `label`, `blipLabel`, `blipSprite`, `blipColor` and `shows`.

| Field | Effect |
| --- | --- |
| `shows` | Metadata. In code, only `impound` behaviour matters: a garage whose `type` is `impound` lists impounded vehicles; every other type lists non-impounded ones. |
| `requireDuty` | Used for garages with a `job`: the player must be on duty (checked on client and server). Default `true` for `job`. It is also present on `gang` (`false`) but gang garages do not check duty. |
| `allowStore` | When `false` (impound), the client offers no Store action for vehicles that are out. |

A garage whose `type` is not in `Config.garageTypes` gets no zone, marker or blip on the client.

## Garages

`Config.garages` is a table keyed by garage id. Fields used by code:

| Field | Meaning |
| --- | --- |
| `type` | A key of `Config.garageTypes` |
| `label` | Display name |
| `coords` | `vector4` of the interaction point; used for the zone, blip and distance checks |
| `spawns` | List of `vector4` spawn points; the first one without a vehicle within `Config.spawn.clearance` is used |
| `job` | Job name; the player must have this job |
| `gang` | Gang name; the player must be in this gang |
| `size` | Optional `vector3` zone size |
| `noMarker` | Skip the ground marker |
| `bucket`, `categories` | Present in the shipped entries but not read by any code |

Shipped examples: `legionsquare`, `motel`, `sandyshores` (public), `missionrow` (police job), `ballas` (gang), `impoundlot` (impound).

## Houses

| Option | Default | Used by code |
| --- | --- | --- |
| `Config.houseGarages.blip` | `false` | Yes: whether garages with an id starting `house_` get a map blip. |
| `Config.houseGarages.query` | `SELECT * FROM houselocations ...` | No: the server runs its own hard-coded query. See [Compatibility](./compatibility.md). |
| `Config.houseGarages.bucket` | `0` | No |

## Impound

| Option | Default | Used by code |
| --- | --- | --- |
| `defaultFee` | `500` | Yes: fee when the vehicle has no stored `impound_fee`. |
| `maxFee` | `100000` | Yes: ceiling on the fee. |
| `account` | `'bank'` | No: the fee is always charged to `cash`. |
| `reason` | `'impound-fee'` | No: the literal `'impound-fee'` is passed instead. |

## Spawn

| Option | Default | Meaning |
| --- | --- | --- |
| `clearance` | `3.0` | Metres a spawn point must be free of vehicles |
| `warpIntoVehicle` | `false` | Put the player into the driver seat after take-out |
| `applyMods` | `true` | Re-apply stored mods on take-out (client side) |
| `timeout` | `10000` | Milliseconds the client has to see the spawned vehicle and confirm; the server discards the pending entity after this plus 5000 ms |

## Cosmetics and garage recording

| Option | Default | Meaning |
| --- | --- | --- |
| `TrustClientCosmetics` | `false` | `true` saves whatever look the client sends |
| `SaveUnstoredLook` | `false` | With protection on, record the client's look on the first park of a vehicle with no stored look |
| `RecordGarageId` | `true` | Write `garage_id` on `player_vehicles` when parking in a non-property, non-impound garage |
| `mods.cosmetic` | list of keys | Keys kept from the database when protection is on |
| `mods.entryCap` | `80` | Not read by code (the server instead rejects mods whose JSON exceeds 131072 bytes) |

See [Using garages](./how-to-use.md#cosmetic-protection).

## Other

| Option | Default | Used by code |
| --- | --- | --- |
| `Config.ui.accent` | `false` | Yes: a colour string overrides the app accent. |
| `Config.listing.max`, `Config.listing.healthScale` | `50`, `1000.0` | No: not read. The NUI list uses a fixed page size of 9 and no cap. |
