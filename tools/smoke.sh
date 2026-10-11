#!/bin/sh
# Rooktest: start KOReader (Flatpak) twee keer met tests/smoke.lua en controleer de log.
# Gebruik: tools/smoke.sh [boek.epub]   (standaard het eerste boek in ~/Lingering)
dir="$(cd "$(dirname "$0")/.." && pwd)"
book="${1:-$(ls "$HOME"/Lingering/*.epub 2>/dev/null | head -1)}"
data="$HOME/.var/app/rocks.koreader.KOReader/config/koreader"
shots="$data/screenshots/lingering-smoke"
mkdir -p "$shots"
logs="$(mktemp -d)"
fail=0
run() {
    name=$1; seconds=$2; shift 2
    timeout "$seconds" flatpak run --env=LINGERING_TEST="$name" --env=LINGERING_SHOTS="$shots" \
        rocks.koreader.KOReader "$@" > "$logs/$name.log" 2>&1
    echo "== $name"
    grep -h "Lingering: SMOKE" "$logs/$name.log"
    if grep -qE "WARN|ERROR|traceback|MISLUKT" "$logs/$name.log"; then
        grep -nE "WARN|ERROR|traceback|MISLUKT" "$logs/$name.log" | grep -v "CRE WARNING"
        grep -E "WARN|ERROR|traceback|MISLUKT" "$logs/$name.log" | grep -qv "CRE WARNING" && fail=1
    fi
}
run fm 14
if [ -n "$book" ]; then run reader 16 "$book"; else echo "== reader overgeslagen (geen boek)"; fi
echo "Schermafdrukken: $shots"
echo "Logs: $logs"
[ "$fail" = 0 ] && echo "SMOKE: alles OK" || echo "SMOKE: FOUTEN"
exit $fail
