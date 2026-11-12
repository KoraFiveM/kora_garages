---
title: "Commands"
sidebar_position: 4
---


# Commands

Kora Garages adds one server command. (`Config.debug`'s own comment says it also "enables /garagedebug", but no such command exists anywhere in the current source — unclear/stale, treat it as not implemented.)

## Built-in commands

### `garage:storeAll [minutes]`

Forces every vehicle this resource currently has spawned (across all garages) back into storage, optionally after a countdown announced to all players.

| Field | Details |
| --- | --- |
| Context | Server console or admin · server command |
| Arguments | minutes? — delay before vehicles are removed; defaults to `1`. `0` or negative removes them immediately. |
| Access | Checked with `IsPlayerAceAllowed(source, 'command')`; the server console always passes this check. |

**Example**

```text
garage:storeAll
garage:storeAll 0
```

**Result**

Broadcasts an ADMIN notification (immediately, or once per minute during the countdown), then deletes every tracked entity that is not currently occupied and sets its `player_vehicles.state` back to `garaged`. Occupied vehicles are not deleted but their DB state is still reset.

## Notes from the code

- The command is registered with `restricted = false`, so access is decided only by the `IsPlayerAceAllowed(source, 'command')` check; a caller who fails it gets no response.
- Only vehicles taken out through this resource since it started are tracked and affected.
- Each tracked plate is set to `garaged` in `player_vehicles` after the delay, whether or not its entity was occupied.
