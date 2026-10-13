-- De pluginloader leest dit bestand vóór main.lua, dus zonder onze eigen modules (l10n/):
-- de taal hier rechtstreeks uit GetText.current_lang, zoals koreader/locale.lua.
local ok, lang = pcall(function() return require("gettext").current_lang end)
local dutch = ok and type(lang) == "string" and lang:match("^nl") ~= nil
return {
    fullname = "Lingering UI",
    -- Versie van deze plugin; tools/release.sh zet hem en maakt de tag v<versie>.
    version = "0.0.9",
    description = dutch
        and "Een versimpelde schil over KOReader: homescreen, mijn boeken en leesscherm."
        or "A simplified shell over KOReader: home screen, my books and reading screen.",
}
