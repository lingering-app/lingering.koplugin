--[[--
Woordenboek (vanuit Instellingen): kies Nederlands of Engels. Staat het woordenboek nog niet
op het apparaat, dan eerst downloaden (wifi aan zonder te vragen; KOReader vraagt bevestiging
met de grootte). Het gekozen woordenboek staat aan, het andere uit; een vinkje toont de keuze,
een downloadicoon wat er nog niet op staat. Lijst in config.dictionaries.
]]
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("lingering.l10n.gettext")
local Screen = Device.screen

local Config = require("lingering.config")
local Dictionaries = require("lingering.koreader.dictionaries")
local Network = require("lingering.koreader.network")
local Widgets = require("lingering.ui.widgets")
local Style = require("lingering.ui.style")

local DictionaryScreen = InputContainer:extend{
    fm = nil,           -- FileManager-instantie (heeft fm.dictionary)
    nav = nil,
    covers_fullscreen = true,
    stop_events_propagation = true,
}
Widgets.guardPaint(DictionaryScreen, "woordenboek")
Widgets.guardEvents(DictionaryScreen, "woordenboek")
Widgets.followRotation(DictionaryScreen)

local function managedNames()
    local names = {}
    for _, dict in ipairs(Config.dictionaries) do table.insert(names, dict.name) end
    return names
end

-- Rechts: vinkje als gekozen, downloadicoon als het er nog niet op staat, anders niets.
function DictionaryScreen:rightIcon(dict)
    if Dictionaries.isEnabled(self.fm, dict.name) then
        return { icon_file = "check.svg" }
    elseif not Dictionaries.isInstalled(self.fm, dict.name) then
        return { icon_file = "download.svg" }
    end
end

function DictionaryScreen:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }

    local title_bar = Widgets.header{
        width = width,
        title = _("Woordenboek"),
        on_back = function() self:close() end,
        show_parent = self,
    }
    self.rows = {}
    local group = VerticalGroup:new{ align = "left", title_bar, Widgets.line(width) }
    for _, dict in ipairs(Config.dictionaries) do
        local row = Widgets.Row:new{
            width = width,
            text = dict.label,
            icon = { icon_file = "dictionary.svg" },
            right = self:rightIcon(dict),
            callback = function() self:choose(dict) end,
        }
        self.rows[dict.name] = row
        table.insert(group, row)
        table.insert(group, Widgets.line(width))
    end

    -- Navigatiebalk onderaan; Instellingen vet, een tik erop gaat terug naar Instellingen.
    local nav = Widgets.mainNav(width, self.nav, "settings", function() self:close() end)
    local used = nav:getSize().h
    for _, widget in ipairs(group) do used = used + widget:getSize().h end
    table.insert(group, VerticalSpan:new{ width = math.max(0, height - used) })
    table.insert(group, nav)

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Style.background,
        group,
    }
end

function DictionaryScreen:refresh()
    for _, dict in ipairs(Config.dictionaries) do
        local row = self.rows[dict.name]
        -- Direct zetten: update{ right = nil } zou het oude icoon laten staan.
        row.right = self:rightIcon(dict)
        row:update{}
    end
    UIManager:setDirty(self, "ui")
end

function DictionaryScreen:choose(dict)
    local managed = managedNames()
    if Dictionaries.isInstalled(self.fm, dict.name) then
        logger.info("Lingering: woordenboek gekozen:", dict.name)
        Dictionaries.choose(self.fm, dict.name, managed)
        self:refresh()
        return
    end
    local entry = Dictionaries.entry(dict.name)
    if not entry then
        logger.warn("Lingering: woordenboek niet in KOReaders lijst:", dict.name)
        UIManager:show(InfoMessage:new{ text = _("Dit woordenboek is niet beschikbaar."), timeout = 3 })
        return
    end
    local started = Network.turnOnWifiThen(function()
        Widgets.safeCall("woordenboek downloaden", function()
            logger.info("Lingering: woordenboek downloaden:", dict.name)
            Dictionaries.download(self.fm, entry, function()
                if Dictionaries.isInstalled(self.fm, dict.name) then
                    Dictionaries.choose(self.fm, dict.name, managed)
                end
                if not self.closed then self:refresh() end
            end)
        end)
    end)
    if not started then
        UIManager:show(InfoMessage:new{ text = _("Geen wifi-verbinding."), timeout = 3 })
    end
end

function DictionaryScreen:onClose()
    self:close()
    return true
end

function DictionaryScreen:show()
    UIManager:show(self, "full")
end

function DictionaryScreen:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "full")
end

return DictionaryScreen
