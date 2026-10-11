#!/bin/sh
# Unit tests (luaunit) met de LuaJIT uit de KOReader-Flatpak, zonder KOReader zelf.
# Gebruik: tools/test.sh [luaunit-opties, bijv. -v of -p patroon]
dir="$(cd "$(dirname "$0")/.." && pwd)"
flatpak run --command=/app/lib/koreader/luajit rocks.koreader.KOReader "$dir/tests/run.lua" "$dir" "$@"
