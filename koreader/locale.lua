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

return M
