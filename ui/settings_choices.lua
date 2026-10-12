--[[--
Keuzelijsten uit Instellingen, op ui/choicescreen.lua:
- language(nav): Nederlands of English. Wijzigt de taal van KOReader (en daarmee van
  Lingering); KOReader vraagt om te herstarten.
- dictionary(fm, nav): Nederlands of English uit config.dictionaries. Staat het er nog niet
  op, dan wifi aan en KOReaders eigen download (met bevestiging), daarna kiezen. Kiezen zet
  het gekozen woordenboek aan en het andere uit; vinkje = gekozen, downloadicoon = staat er
  nog niet op.
]]
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("lingering.l10n.gettext")

local Config = require("lingering.config")
local Dictionaries = require("lingering.koreader.dictionaries")
local Locale = require("lingering.koreader.locale")
local Network = require("lingering.koreader.network")
local ChoiceScreen = require("lingering.ui.choicescreen")

local SettingsChoices = {}

-- Talen in hun eigen naam (niet vertaald), met de code van KOReaders taalmenu.
local LANGUAGES = {
    { label = "Nederlands", code = "nl_NL" },
    { label = "English", code = "en" },
}

local CHECK = { icon_file = "check.svg" }

function SettingsChoices.language(nav)
    -- Huidige taal: Nederlands als KOReader op nl draait, anders Engels.
    local function current()
        return (Locale.setting() or Locale.language() or ""):match("^nl") and "nl_NL" or "en"
    end
    local items = {}
    for _, lang in ipairs(LANGUAGES) do
        table.insert(items, {
            label = lang.label,
            icon = { icon_file = "language.svg" },
            right = function() return current() == lang.code and CHECK or nil end,
            choose = function(screen)
                if current() == lang.code then return end
                logger.info("Lingering: taal gewijzigd naar", lang.code)
                Locale.change(lang.code)
                screen:refresh()
            end,
        })
    end
    return ChoiceScreen:new{ title = _("Taal"), items = items, nav = nav }
end

function SettingsChoices.dictionary(fm, nav)
    local managed = {}
    for _, dict in ipairs(Config.dictionaries) do table.insert(managed, dict.name) end

    local function choose(screen, dict)
        if Dictionaries.isInstalled(fm, dict.name) then
            logger.info("Lingering: woordenboek gekozen:", dict.name)
            Dictionaries.choose(fm, dict.name, managed)
            screen:refresh()
            return
        end
        local entry = Dictionaries.entry(dict.name)
        if not entry then
            logger.warn("Lingering: woordenboek niet in KOReaders lijst:", dict.name)
            UIManager:show(InfoMessage:new{ text = _("Dit woordenboek is niet beschikbaar."), timeout = 3 })
            return
        end
        local started = Network.turnOnWifiThen(function()
            logger.info("Lingering: woordenboek downloaden:", dict.name)
            Dictionaries.download(fm, entry, function()
                if Dictionaries.isInstalled(fm, dict.name) then
                    Dictionaries.choose(fm, dict.name, managed)
                end
                screen:refresh()
            end)
        end)
        if not started then
            UIManager:show(InfoMessage:new{ text = _("Geen wifi-verbinding."), timeout = 3 })
        end
    end

    local items = {}
    for _, dict in ipairs(Config.dictionaries) do
        table.insert(items, {
            label = dict.label,
            icon = { icon_file = "dictionary.svg" },
            -- Vinkje als gekozen, downloadicoon als het er nog niet op staat, anders niets.
            right = function()
                if Dictionaries.isEnabled(fm, dict.name) then
                    return CHECK
                elseif not Dictionaries.isInstalled(fm, dict.name) then
                    return { icon_file = "download.svg" }
                end
            end,
            choose = function(screen) choose(screen, dict) end,
        })
    end
    return ChoiceScreen:new{ title = _("Woordenboek"), items = items, nav = nav }
end

return SettingsChoices
