# Gedeeld door tools/smoke.sh en tools/screenshots.sh (met ". tools/kohome.sh").
#
# getHomeDir [extra-instellingen]
#   Maakt een lege KOReader-map voor KO_HOME, met de plugin (link naar deze repo) en een paar
#   instellingen: geen handleiding bij de eerste start, thuismap in de testmap. Extra regels
#   voor settings.reader.lua (bijv. de taal) kunnen als argument mee. Geeft het pad terug.
#   In de cachemap van de Flatpak, want het gewone /tmp is binnen de Flatpak afgeschermd.
getHomeDir() {
    home="$HOME/.var/app/rocks.koreader.KOReader/cache/lingering-test-$$"
    rm -rf "$home"
    mkdir -p "$home/plugins" "$home/books/Lingering" "$home/settings"
    ln -s "$dir" "$home/plugins/lingering.koplugin"
    cat > "$home/settings.reader.lua" <<SETTINGS
return {
    ["quickstart_shown_version"] = 999999999999,
    ["home_dir"] = "$home/books",
    ["lastdir"] = "$home/books",
    $1
}
SETTINGS
    echo "$home"
}
