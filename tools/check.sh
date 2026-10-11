#!/bin/sh
# Syntaxcontrole van alle Lua-bestanden met de LuaJIT uit de KOReader-Flatpak.
# Gebruik: tools/check.sh
dir="$(cd "$(dirname "$0")/.." && pwd)"
files="$(find "$dir" -name '*.lua' -not -path '*/.git/*' | tr '\n' ' ')"
flatpak run --env=FILES="$files" --command=/app/lib/koreader/luajit rocks.koreader.KOReader -e '
local bad = 0
for p in os.getenv("FILES"):gmatch("%S+") do
    local f, e = loadfile(p)
    if f then print("OK   " .. p) else bad = bad + 1; print("FOUT " .. e) end
end
os.exit(bad == 0 and 0 or 1)'
