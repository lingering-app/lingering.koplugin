#!/bin/sh
# Zet de plugin op een aangesloten Kobo, zonder ontwikkelbestanden.
# Gebruik: tools/deploy.sh [koppelpunt-van-de-kobo]
#   Zonder argument zoekt het script een Kobo onder /run/media/$USER (map met .kobo).
# Eerst controles en unit tests; faalt er iets, dan wordt er niets gekopieerd.
set -e
dir="$(cd "$(dirname "$0")/.." && pwd)"

mount="$1"
if [ -z "$mount" ]; then
    for candidate in /run/media/"$USER"/* /media/"$USER"/*; do
        [ -d "$candidate/.kobo" ] && mount="$candidate" && break
    done
fi
if [ -z "$mount" ] || [ ! -d "$mount/.kobo" ]; then
    echo "Geen Kobo gevonden. Sluit hem aan via USB (en kies 'Verbinden'), of geef het koppelpunt op."
    exit 1
fi
target="$mount/.adds/koreader/plugins/lingering.koplugin"

echo "== Controles"
"$dir/tools/check.sh" | grep -v "^OK   /"
"$dir/tools/test.sh" | tail -1

echo "== Kopiëren naar $target"
mkdir -p "$target"
rsync -rt --delete --modify-window=2 \
    --exclude='.git/' --exclude='.gitignore' \
    --exclude='tests/' --exclude='tools/' --exclude='docs/' \
    --exclude='*.old' --exclude='*.part' \
    "$dir/" "$target/"
sync
echo "== Klaar. Werp de Kobo netjes uit en start KOReader."
