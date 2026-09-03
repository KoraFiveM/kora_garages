#!/usr/bin/env bash
# Runs every qbgarages smoke test with plain Lua (no busted, no FXServer, no DB).
# Exits non-zero on any failure.
#
# Each file loads only what it exercises, in the SERVER realm -- that is where
# every rule worth testing lives, because the client is presentation only. The
# world in test/mocks.lua is fully driven: a test moves the player, changes their
# routing bucket and edits the vehicle table itself, so each refusal is reached
# deliberately rather than by luck.
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lua_bin="${LUA:-lua}"
status=0
headers=0

for file in "$dir"/smoke/*.lua; do
    echo "== $(basename "$file" .lua) =="
    headers=$((headers + 1))
    if ! ( cd "$dir/.." && "$lua_bin" "$file" ); then status=1; fi
    echo
done

# A test file that dies mid-load still prints its header, so "0 failed" alone
# does not mean everything ran -- compare the header count against the summary
# count. Deliberately NOT prefixed with "== ", which would make this line look
# like a suite header and inflate the very count it exists to report.
echo "-- ran $headers suite(s) --"
exit "$status"
