--[[--
Lingering UI: een versimpelde schil over KOReader.
Laadt de onderdelen, kiest per context (bestandsbeheerder of lezer) wat er gebeurt.
]]
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

-- Onze modules krijgen unieke namen in de gedeelde require-cache. Namen als "reader" of
-- "settings" zouden anders bij KOReader's eigen reader.lua of bij een andere plugin uitkomen.
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
for _, module in ipairs({ "actionbar", "compat", "config", "homescreen", "reader",
                          "settings", "settingsscreen", "widgets" }) do
    package.preload["lingering_" .. module] = function()
        return dofile(plugin_dir .. "/" .. module .. ".lua")
    end
end

local Settings = require("lingering_settings")

local Lingering = WidgetContainer:extend{
    name = "lingering",
}

function Lingering:init()
    self.in_reader = self.ui and self.ui.document ~= nil
    logger.info("Lingering: plugin geladen in", self.in_reader and "ReaderUI" or "FileManager",
        Settings:isActive() and "(actief)" or "(uitgeschakeld voor deze sessie)")
    if Settings:isActive() then
        require("lingering_compat").enforceGlobalSettings()
    end
    if not self.in_reader then
        if self.ui.menu then
            self.ui.menu:registerToMainMenu(self)
        end
        if Settings:isActive() then
            -- Na de opbouw van de bestandsbeheerder, zodat het homescreen erbovenop komt.
            UIManager:nextTick(function() self:showHomeScreen() end)
        end
    end
end

function Lingering:onReaderReady()
    if not Settings:isActive() then return end
    require("lingering_reader").install(self.ui)
end

local function notYet()
    UIManager:show(InfoMessage:new{
        text = _("Dit onderdeel komt in een volgende versie."),
        timeout = 3,
    })
end

--- Toont het homescreen. Faalt dat, dan blijft de gewone bestandsbeheerder zichtbaar.
function Lingering:showHomeScreen()
    if self.home or not Settings:isActive() then return end
    local ok, err = pcall(function()
        local HomeScreen = require("lingering_homescreen")
        local home = HomeScreen:new{
            fm = self.ui,
            on_library = notYet,
            on_local_books = notYet,
            on_settings = function() self:showSettings() end,
            on_emergency = function() self:openEmergencyMenu() end,
            on_closed = function() self.home = nil end,
        }
        self.home = home
        home:show()
    end)
    if ok then
        logger.info("Lingering: homescreen getoond")
    else
        self.home = nil
        logger.warn("Lingering: homescreen kon niet laden, bestandsbeheerder blijft zichtbaar:", err)
    end
end

function Lingering:showSettings()
    local SettingsScreen = require("lingering_settingsscreen")
    SettingsScreen:new{
        on_sync = notYet,
        on_login = notYet,
        on_emergency = function() self:openEmergencyMenu() end,
    }:show()
end

--- Noodluik: homescreen dicht, gewone bestandsbeheerder met het volledige menu.
function Lingering:openEmergencyMenu()
    logger.info("Lingering: noodluik, volledig KOReader-menu")
    if self.home then
        self.home:close()
    end
    require("lingering_compat").showFileManagerMenu(self.ui)
end

function Lingering:addToMainMenu(menu_items)
    menu_items.lingering_disable = {
        text = _("Lingering UI uitschakelen"),
        sorting_hint = "main",
        help_text = _("Zet de versimpelde schil uit tot de volgende herstart, of tot je dit weer uitvinkt."),
        checked_func = function()
            return not Settings:isActive()
        end,
        callback = function(touchmenu_instance)
            Settings.session.disabled = not Settings.session.disabled
            logger.info("Lingering: schil", Settings.session.disabled and "uitgeschakeld" or "weer ingeschakeld")
            if Settings:isActive() and not self.in_reader then
                -- Weer aan: menu dicht en homescreen terug.
                pcall(function() touchmenu_instance:closeMenu() end)
                self:showHomeScreen()
            end
        end,
    }
end

return Lingering
