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
os.exit(bad == 0 and 0 or 1)' || exit 1

# Bestaat elke aangeroepen Compat.x / Widgets.x ook echt? (een verdwenen functie wordt
# anders pas op het apparaat stil afgevangen)
missing=0
for module in Compat Widgets; do
    file=compat.lua; [ "$module" = Widgets ] && file=widgets.lua
    defined="$(grep -ohE "^function $module[.:][A-Za-z_]+|^$module\.[A-Za-z_]+ *=" "$dir/$file" | sed -E "s/^function $module[.:]//; s/^$module\.//; s/ *=.*//" | sort -u)"
    used="$(grep -ohE "\b$module[.:][A-Za-z_]+\(" "$dir"/*.lua | sed -E "s/^$module[.:]//; s/\($//" | sort -u)"
    for name in $used; do
        if ! printf '%s\n' "$defined" | grep -qx "$name"; then
            echo "FOUT $module.$name wordt aangeroepen maar bestaat niet"
            missing=1
        fi
    done
done
[ "$missing" = 0 ] && echo "OK   alle Compat- en Widgets-functies bestaan"
exit $missing
