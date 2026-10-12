#!/bin/sh
# Rooktest: start KOReader (Flatpak) twee keer met tests/smoke.lua en controleer de log.
# Gebruik: tools/smoke.sh [boek.epub]   (standaard het eerste boek in ~/Lingering)
# Ander schermformaat: SMOKE_W=1072 SMOKE_H=1448 SMOKE_DPI=300 tools/smoke.sh (Kobo Clara)
dir="$(cd "$(dirname "$0")/.." && pwd)"
book="${1:-$(ls "$HOME"/Lingering/*.epub 2>/dev/null | head -1)}"
data="$HOME/.var/app/rocks.koreader.KOReader/config/koreader"
shots="$data/screenshots/lingering-smoke"
mkdir -p "$shots"
logs="$(mktemp -d)"
fail=0
run() {
    name=$1; seconds=$2; shift 2
    # Vast schermformaat (Kobo-achtig portrait), los van hoe groot het venster laatst was.
    timeout "$seconds" flatpak run --env=LINGERING_TEST="$name" --env=LINGERING_SHOTS="$shots" \
        --env=EMULATE_READER_W="${SMOKE_W:-758}" --env=EMULATE_READER_H="${SMOKE_H:-1024}" \
        ${SMOKE_DPI:+--env=EMULATE_READER_DPI="$SMOKE_DPI"} \
        rocks.koreader.KOReader "$@" > "$logs/$name.log" 2>&1
    echo "== $name"
    grep -h "Lingering: SMOKE" "$logs/$name.log"
    # Verwacht: de test met het foute wachtwoord, en waarschuwingen van crengine zelf.
    expected="CRE WARNING|inloggen mislukt bij OPDS (gebruikersnaam of wachtwoord onjuist|incorrect username or password)"
    if grep -E "WARN|ERROR|traceback|MISLUKT" "$logs/$name.log" | grep -qvE "$expected"; then
        grep -nE "WARN|ERROR|traceback|MISLUKT" "$logs/$name.log" | grep -vE "$expected"
        fail=1
    fi
}
run fm 40
if [ -n "$book" ]; then run reader 32 "$book"; else echo "== reader overgeslagen (geen boek)"; fi
echo "Schermafdrukken: $shots"
echo "Logs: $logs"
[ "$fail" = 0 ] && echo "SMOKE: alles OK" || echo "SMOKE: FOUTEN"
exit $fail
