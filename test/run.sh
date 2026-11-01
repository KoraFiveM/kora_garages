#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir/.."
"${LUA:-lua}" test/legacy-housing.lua
"${LUA:-lua}" test/property.lua
"${LUA:-lua}" test/compat.lua
