---
title: Testing
sidebar_position: 10
---

# Testing

Offline Lua tests are in `test/` and run with `bash test/run.sh` (set `LUA` to choose the interpreter). It runs `legacy-housing.lua`, `property.lua`, `compat.lua`, `client.lua` and `markers.lua` using native and SQL fixtures. They expect sibling checkouts of `kora_core` and `kora_lib`. They do not start FXServer.

`tests/checklist-vehicles.feature` holds manual QA scenarios for `kora_qa`, registered by `qa_feature` in `fxmanifest.lua`.
