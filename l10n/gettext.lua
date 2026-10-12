--[[--
Vertaalfunctie van Lingering: _("Nederlandse tekst") geeft de tekst in de taal van KOReader.
De bronteksten zijn Nederlands; voor elke andere taal dan Nederlands komt de Engelse vertaling
uit l10n/en.lua (ontbreekt die, dan de Nederlandse tekst). KOReaders eigen gettext kent onze
teksten niet, daarom een eigen tabel. tools/check_l10n.lua controleert dat elke _("…") een
Engelse vertaling heeft.
]]
local Locale = require("lingering.koreader.locale")

local lang = Locale.language() or "C"
local strings = lang:match("^nl") and {} or require("lingering.l10n.en")

return function(text)
    return strings[text] or text
end
