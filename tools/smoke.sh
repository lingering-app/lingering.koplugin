#!/bin/sh
# Rooktest: KOReader (Flatpak) met tests/smoke.lua tegen een lokale testserver
# (tools/mock_server.py), in een eigen, lege KOReader-map (KO_HOME). Jouw eigen KOReader en
# de echte Lingering-server worden niet aangeraakt.
# Fases: setup (inloggen op de testserver) → reader (testboek) → fm (homescreen, Mijn boeken,
# instellingen). Daarna worden de testserver en de testmap opgeruimd.
# Gebruik: tools/smoke.sh
# Ander schermformaat: SMOKE_W=1072 SMOKE_H=1448 SMOKE_DPI=300 tools/smoke.sh (Kobo Clara)
# Andere poort: SMOKE_PORT=8765 (standaard)
dir="$(cd "$(dirname "$0")/.." && pwd)"
port="${SMOKE_PORT:-8765}"
base="http://127.0.0.1:$port"
app="$HOME/.var/app/rocks.koreader.KOReader"
shots="$app/config/koreader/screenshots/lingering-smoke"
mkdir -p "$shots"
logs="$(mktemp -d)"
fail=0

# Lege KOReader-map voor de test, met de plugin (link naar deze map) en een paar instellingen:
# geen handleiding bij de eerste start, thuismap in de testmap. In de cachemap van de Flatpak,
# want het gewone /tmp is binnen de Flatpak afgeschermd.
getHomeDir() {
    home="$app/cache/lingering-smoke-$$"
    rm -rf "$home"
    mkdir -p "$home/plugins" "$home/books/Lingering"
    ln -s "$dir" "$home/plugins/lingering.koplugin"
    cat > "$home/settings.reader.lua" <<EOF
return {
    ["quickstart_shown_version"] = 999999999999,
    ["home_dir"] = "$home/books",
    ["lastdir"] = "$home/books",
}
EOF
    echo "$home"
}

home="$(getHomeDir)"
python3 -I "$dir/tools/mock_server.py" --port "$port" > "$logs/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$home"' EXIT INT TERM
for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -s -o /dev/null "$base/opds" && break
    sleep 0.5
done

run() {
    name=$1; seconds=$2; shift 2
    # Vast schermformaat (Kobo-achtig portrait), los van hoe groot het venster laatst was.
    timeout "$seconds" flatpak run --env=KO_HOME="$home" \
        --env=LINGERING_OPDS_URL="$base/opds" --env=LINGERING_SYNC_URL="$base/kosync" \
        --env=LINGERING_TEST="$name" --env=LINGERING_SHOTS="$shots" \
        --env=EMULATE_READER_W="${SMOKE_W:-758}" --env=EMULATE_READER_H="${SMOKE_H:-1024}" \
        ${SMOKE_DPI:+--env=EMULATE_READER_DPI="$SMOKE_DPI"} \
        rocks.koreader.KOReader "$@" > "$logs/$name.log" 2>&1
    echo "== $name"
    grep -h "Lingering: SMOKE" "$logs/$name.log"
    # Verwacht: de test met het foute wachtwoord, en waarschuwingen van crengine zelf.
    expected="CRE WARNING|inloggen mislukt bij OPDS"
    if grep -E "WARN|ERROR|traceback|MISLUKT" "$logs/$name.log" | grep -qvE "$expected"; then
        grep -nE "WARN|ERROR|traceback|MISLUKT" "$logs/$name.log" | grep -vE "$expected"
        fail=1
    fi
}

run setup 30
# Testboek in de thuismap, zoals Lingering het zou downloaden.
book="$home/books/Lingering/De Stille Haven - Anna de Vries.epub"
curl -s -u test:test -o "$book" "$base/opds/book/1.epub"
run reader 40 "$book"
run fm 90
echo "Schermafdrukken: $shots"
echo "Logs: $logs"
[ "$fail" = 0 ] && echo "SMOKE: alles OK" || echo "SMOKE: FOUTEN"
exit $fail
