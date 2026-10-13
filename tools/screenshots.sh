#!/bin/sh
# Schermafdrukken van Lingering voor de website, tegen de echte catalogus en het account uit
# je eigen KOReader (kosync.lua, opds.lua en lingering.lua worden naar een tijdelijke map
# gekopieerd; je eigen KOReader verandert niet). Nederlands, Kobo Clara-resolutie.
# Gebruik: tools/screenshots.sh [uitvoermap]   (standaard: screenshots-site/ in deze repo)
# Ander account: LINGERING_ACCOUNT_FROM=<KOReader-map met settings/>
# Ander formaat: SHOTS_W=1072 SHOTS_H=1448 SHOTS_DPI=300 (standaard: Kobo Clara)
dir="$(cd "$(dirname "$0")/.." && pwd)"
app="$HOME/.var/app/rocks.koreader.KOReader"
src="${LINGERING_ACCOUNT_FROM:-$app/config/koreader}"
out="${1:-$dir/screenshots-site}"
shots="$app/config/koreader/screenshots/lingering-site"
logs="$(mktemp -d)"

. "$dir/tools/kohome.sh"
home="$(getHomeDir '["language"] = "nl_NL",')"
trap 'rm -rf "$home"' EXIT INT TERM
for f in kosync.lua opds.lua lingering.lua; do
    cp "$src/settings/$f" "$home/settings/$f" || { echo "Geen $src/settings/$f"; exit 1; }
done
rm -rf "$shots"; mkdir -p "$shots" "$out"

run() {
    name=$1; seconds=$2; shift 2
    timeout "$seconds" flatpak run --env=KO_HOME="$home" \
        --env=LINGERING_TEST="$name" --env=LINGERING_SHOTS="$shots" \
        --env=EMULATE_READER_W="${SHOTS_W:-1072}" --env=EMULATE_READER_H="${SHOTS_H:-1448}" \
        --env=EMULATE_READER_DPI="${SHOTS_DPI:-300}" \
        "$@" > "$logs/$name.log" 2>&1
    echo "== $name"
    grep -hE "Lingering: (SMOKE|SHOTS)" "$logs/$name.log"
}

run shots-prep 180 rocks.koreader.KOReader
first=1
for book in "$home"/books/Lingering/*.epub; do
    [ -f "$book" ] || continue
    run shots-reader 60 --env=LINGERING_SHOT_MAIN="$first" rocks.koreader.KOReader "$book"
    first=0
done
run shots-fm 120 rocks.koreader.KOReader
cp "$shots"/*.png "$out"/ 2>/dev/null
echo "Schermafdrukken: $out"
ls "$out"
echo "Logs: $logs"
