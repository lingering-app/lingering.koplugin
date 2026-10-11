#!/bin/sh
# Nieuwe versie uitbrengen: versie in _meta.lua zetten, controleren, committen, tag maken.
# Gebruik: tools/release.sh 0.2.0 [--push]
#   Zonder --push blijft alles lokaal; met --push gaan de commit en de tag naar origin,
#   waarna Kobo's via Instellingen → Update naar deze versie kunnen bijwerken.
set -e
dir="$(cd "$(dirname "$0")/.." && pwd)"
version="$1"
push="$2"

if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Gebruik: tools/release.sh <major.minor.patch> [--push]   (bijv. 0.2.0)"
    exit 1
fi
tag="v$version"
cd "$dir"
if [ -n "$(git status --porcelain)" ]; then
    echo "Er staan nog niet-gecommitte wijzigingen. Commit of stash die eerst."
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
    echo "Tag $tag bestaat al."
    exit 1
fi

echo "== Controles"
tools/check.sh | grep -v "^OK   /"
tools/test.sh | tail -1

echo "== Versie $version"
sed -i -E "s/^(    version = )\"[0-9]+\.[0-9]+\.[0-9]+\",/\1\"$version\",/" _meta.lua
grep -q "version = \"$version\"" _meta.lua || { echo "Versie niet gezet in _meta.lua"; exit 1; }
if [ -n "$(git status --porcelain _meta.lua)" ]; then
    git commit -q -m "Versie $version" _meta.lua
fi
git tag -a "$tag" -m "Versie $version"
echo "Tag $tag gemaakt op $(git rev-parse --short HEAD)."

if [ "$push" = "--push" ]; then
    git push origin HEAD
    git push origin "$tag"
    echo "== Gepusht. Kobo's kunnen nu bijwerken naar $tag."
else
    echo "Nog niet gepusht. Doe dat met: git push origin HEAD && git push origin $tag"
fi
