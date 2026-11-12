---
title: Commands
sidebar_position: 5
---

# Commands

## garage:storeAll

`garage:storeAll [minutes]` (typed by a player or from the console).

- Requires `IsPlayerAceAllowed(source, 'command')`; whether the console passes this is not verified here. Registered with `restricted = false`, so access is decided only by that check.
- Default delay is 1 minute (`tonumber(args[1]) or 1`). With `0` or less it acts immediately.
- It announces to all players, waits (minute by minute notices), then deletes every vehicle this resource spawned and tracked (that is not occupied) and sets each tracked plate to `garaged` in `player_vehicles`.
- Only vehicles taken out through this resource since it started are tracked.

`Config.debug` is described in the code comments as enabling `/garagedebug`, but no such command is registered.
