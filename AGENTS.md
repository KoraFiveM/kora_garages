# qbgarages agent guide

## Boundary

`qbgarages` owns **no vehicle data**. Ownership, condition and impound state live
in qbcore's `player_vehicles` table and are reached exclusively through
`Core.garage.*` (`exports.qbcore:getByPlate`, `getByOwner`, `spawnVehicle`,
`storeVehicle`, `impound`, `retrieveImpound`, `updateState`). Never write SQL
here, never add a `player_vehicles` query, and never keep a vehicle record as
this resource's own state. If a rule needs a new column or a new read shape
(a fleet listing, for instance), that is a **qbcore** change — stop and say so
rather than reaching around it.

`server/api.lua` is the sole authority. `client/` is presentation and intent:
`client/ui.lua` owns the NUI/focus bridge, `client/actions.lua` finds the entity
the player means and applies the mods the *server* handed back, and neither may
decide anything.

## Security

The browser may send a **garage id** and a **plate**, and nothing else. Both are
intent. Every action re-resolves the garage from `Config.garages`, the citizenid
and job/gang from qbcore, the position and routing bucket from the server-side
ped, and the vehicle row from the DB by plate — see `server/access.lua`, which is
the single funnel. Do not add a client-facing entry point that accepts a
coordinate, a condition value, a fee, a garage descriptor, a vehicle record, a
citizenid or a spawn point.

Reach every native through a `type(...) == 'function'` guard and make a missing
one **fail the check**, never skip it. That is what keeps the plain-Lua tests
possible and what makes a future native move degrade into "refused" instead of
"unchecked".

The client-supplied mods blob is the one unavoidable claim (mod state has no
server-side native). Keep it filtered to `Config.mods.cosmetic` in
`Garages.api.filterMods`. Do not add `modEngine`, `modBrakes`,
`modTransmission`, `modSuspension`, `modArmor` or `modTurbo` to that list, and do
not add `plate`, `model`, `engineHealth`, `bodyHealth` or `fuelLevel` — the
server owns all five, and a mods blob is not a back door for them.

## Impound ordering

Charge the fee through qbcore's money export **before** clearing the impound
flag, and refund it if the clear then fails. Reversing the order turns an
unaffordable retrieval into a free one. There is a test for this; keep it.

## Compat

`server/compat.lua` speaks the real `qb-garage:*` protocol and must stay a thin
shim over `Garages.api`/`Garages.access`. It is never a second, laxer entry
point: no legacy handler may skip the ownership, distance or bucket checks, and
a caller-supplied price, condition value or garage type is ignored rather than
believed. Upstream's raw `state == 0` write stays refused — it has no location or
ownership proof of its own, so honouring it would be a free un-impound.

## Blips

Every blip uses its garage location label and
`Config.garageTypes[type].blipLabel` as its named category. This groups matching
Garage, Job Garage, Gang Garage, and Impound locations beneath separate
pause-map legend headings without identical entries. See qblib's blip docs.

## Tests

Keep the smoke tests deterministic and free of a running FXServer. Add a test
whenever a refusal, a config rule or a public export changes — the refusals *are*
the feature here, so a new gate without a test for it is incomplete. After
changing `web/`, run `pnpm install && pnpm typecheck && pnpm build` in that
folder and commit the regenerated `web/build/` artifacts.
