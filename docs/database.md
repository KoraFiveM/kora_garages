---
title: Database
sidebar_position: 8
---

# Database

## kora_garages_property_garages

Created by this resource (`server/schema.lua`) through `Kora.sql.ensureTables`.

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | `varchar(50)`, primary key | Property garage id |
| `provider` | `varchar(64)` | Resource that registered the garage |
| `definition` | `longtext` | JSON of the normalised garage definition |

## player_vehicles (owned by kora_core)

This resource reads and updates these columns by plate: `state` (`garaged`, `out`, `impounded`), `garage_id`, `mods`, `engine_health`, `body_health`, `fuel`. It reads `impound_fee`, `citizenid`, `model`, `id` and `deleted_at`. On start, all rows with state `out` are set to `garaged`.

## houselocations (optional legacy)

If a table named `houselocations` exists, the server reads rows with a non-null `garage` column and creates `house_<name>` garages. See [Compatibility](./compatibility.md).
