--[[--
Taal van KOReader, voor de vertalingen van Lingering (l10n/).
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

--[[--
De taal waarin KOReader draait: GetText.current_lang (frontend/gettext.lua), zoals reader.lua
hem bij het starten zet uit G_reader_settings "language" (bijv. "nl_NL", "en"). Zonder
ingestelde taal is dat "C" (Engels).
]]
function M.language()
    local ok, lang = try("language", function()
        return require("gettext").current_lang
    end)
    return ok and lang or "C"
end

--- De ingestelde taal (G_reader_settings "language"), of nil als er niets is ingesteld.
function M.setting()
    local ok, lang = try("languageSetting", function()
        return G_reader_settings:readSetting("language")
    end)
    return ok and lang or nil
end

--[[--
Taal van KOReader wijzigen, zoals KOReaders taalmenu (ui/language.lua, Language:changeLanguage):
bewaart G_reader_settings "language" en vraagt om KOReader te herstarten. Na de herstart
volgen KOReader en Lingering (l10n/) die taal.
]]
function M.change(lang)
    return try("changeLanguage", function()
        require("ui/language"):changeLanguage(lang)
    end)
end

return M
