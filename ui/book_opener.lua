--[[--
Een boek uit de catalogus openen: staat het op het apparaat, dan meteen; anders eerst
downloaden (wifi aan zonder te vragen, melding "Downloaden…") en dan openen.
open(library, entry, on_path): on_path(pad) volgt als het bestand klaarstaat; de aanroeper
sluit zijn scherm en opent het boek.
]]
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("lingering.l10n.gettext")
local T = require("ffi/util").template

local Network = require("lingering.koreader.network")
local Widgets = require("lingering.ui.widgets")

local BookOpener = {}

function BookOpener.open(library, entry, on_path)
    if library:isDownloaded(entry) then
        Widgets.safeCall("boek openen", on_path, (library:bookPath(entry)))
        return
    end
    local started = Network.turnOnWifiThen(function() Widgets.safeCall("downloaden", function()
        local busy = InfoMessage:new{ text = T(_("Downloaden…\n%1"), entry.title) }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local ok, path = library:download(entry)
        UIManager:close(busy)
        -- Bij een fout toont OPDSBrowser:downloadFile zelf een melding.
        if ok then
            Widgets.safeCall("boek openen", on_path, path)
        end
    end) end)
    if not started then
        UIManager:show(InfoMessage:new{ text = _("Geen wifi-verbinding."), timeout = 3 })
    end
end

return BookOpener
