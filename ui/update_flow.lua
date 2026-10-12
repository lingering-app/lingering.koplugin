--[[--
Bijwerken naar de nieuwste versie (vanuit "Over Lingering"): wifi aan, zoeken, vragen,
bijwerken, KOReader herstarten. Afloop in app/update_service.lua.
]]
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("lingering.l10n.gettext")
local T = require("ffi/util").template

local UpdateService = require("lingering.app.update_service")
local Widgets = require("lingering.ui.widgets")

local UpdateFlow = {}

local function install(tag)
    local busy = InfoMessage:new{ text = _("Bijwerken…") }
    UIManager:show(busy)
    UIManager:forceRePaint()
    UpdateService.install(tag, function(ok, reason) Widgets.safeCall("bijwerken", function()
        UIManager:close(busy)
        if ok then
            UpdateService.askForRestart(_("Lingering is bijgewerkt. KOReader moet herstarten."))
        elseif reason == "ontwikkelversie" then
            UIManager:show(InfoMessage:new{ text = _("Dit is een ontwikkelversie; bijwerken overgeslagen.") })
        else
            UIManager:show(InfoMessage:new{ text = _("Bijwerken mislukt. De huidige versie blijft staan.") })
        end
    end) end)
end

function UpdateFlow.run()
    logger.info("Lingering: update zoeken")
    local busy = InfoMessage:new{ text = _("Zoeken naar een nieuwe versie…") }
    UIManager:show(busy)
    UIManager:forceRePaint()
    UpdateService.check(function(result) Widgets.safeCall("update", function()
        UIManager:close(busy)
        if result.status == "error" then
            UIManager:show(InfoMessage:new{ text = _("Zoeken naar een nieuwe versie is mislukt."), timeout = 3 })
        elseif result.status == "current" then
            UIManager:show(InfoMessage:new{
                text = T(_("Je hebt de nieuwste versie (v%1)."), result.installed or "?"),
                timeout = 3,
            })
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("Bijwerken naar %1?"), result.latest),
                ok_text = _("Bijwerken"),
                ok_callback = function() install(result.latest) end,
            })
        end
    end) end)
end

return UpdateFlow
