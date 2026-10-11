--[[--
Lingering UI: een versimpelde schil over KOReader.
Laadt de onderdelen, kiest per context (bestandsbeheerder of lezer) wat er gebeurt.
]]
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

-- Onze modules heten "lingering.<map>.<naam>" en worden uit de eigen pluginmap geladen.
-- Unieke namen zijn nodig: de require-cache is gedeeld met KOReader en andere plugins, en
-- namen als "reader" of "settings" zouden bij KOReader's eigen bestanden uitkomen.
--   domain/    business rules, pure Lua (geen KOReader)
--   app/       use cases en eigen instellingen
--   koreader/  anti-corruption layer: het enige dat KOReader-internals kent
--   ui/        schermen (KOReader-widgets)
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
package.loaded["lingering.plugin"] = { dir = plugin_dir }
if not package.loaded["lingering.loader"] then
    package.loaded["lingering.loader"] = true
    table.insert(package.loaders, 2, function(name)
        local relative = name:match("^lingering%.(.+)$")
        if not relative then return nil end
        local path = plugin_dir .. "/" .. relative:gsub("%.", "/") .. ".lua"
        local chunk, err = loadfile(path)
        if not chunk then
            return "\n\tLingering: " .. tostring(err)
        end
        return chunk
    end)
end

-- Rooktest in de emulator (tests/smoke.lua), alleen met LINGERING_TEST; op de Kobo niets.
local Smoke = os.getenv("LINGERING_TEST") and dofile(plugin_dir .. "/tests/smoke.lua") or nil

local Settings = require("lingering.app.session")

local Lingering = WidgetContainer:extend{
    name = "lingering",
}

function Lingering:init()
    self.in_reader = self.ui and self.ui.document ~= nil
    logger.info("Lingering: plugin geladen in", self.in_reader and "ReaderUI" or "FileManager",
        Settings:isActive() and "(actief)" or "(uitgeschakeld voor deze sessie)")
    if Settings:isActive() then
        require("lingering.koreader.global_settings").enforce()
    end
    if not self.in_reader then
        -- Deze versie start: restanten van een vorige update (zip, .new, .bak) opruimen.
        require("lingering.app.update_service").cleanup()
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
    -- Hier en niet in init: plugins worden op volgorde van pad geladen en onze map
    -- (<datadir>/plugins) komt vóór plugins/kosync.koplugin, dus ui.kosync bestaat in
    -- init nog niet, en onze onReaderReady draait vóór die van kosync (die registerEvents
    -- aanroept en zijn eerste ophaalpoging op de volgende tik plant).
    require("lingering.koreader.kosync").installRules(self.ui, require("lingering.app.sync_service").policy)
    require("lingering.koreader.kosync").ensureBinary(self.ui)
    require("lingering.ui.reader").install(self.ui)
end

--- Toont het homescreen. Faalt dat, dan blijft de gewone bestandsbeheerder zichtbaar.
function Lingering:showHomeScreen()
    if self.home or not Settings:isActive() then return end
    if not Settings:read("lingering_setup_done") then
        self:showSetup(true)
        return
    end
    local ok, err = pcall(function()
        local HomeScreen = require("lingering.ui.homescreen")
        local home = HomeScreen:new{
            fm = self.ui,
            library = require("lingering.app.library_service"),
            on_open_book = function(path) require("lingering.koreader.navigation").openBook(path) end,
            on_local_books = function() self:showLibrary() end,
            on_settings = function() self:showSettings() end,
            on_emergency = function() self:openEmergencyMenu() end,
            on_closed = function() self.home = nil end,
        }
        self.home = home
        home:show()
    end)
    if ok and Smoke and os.getenv("LINGERING_TEST") == "fm" then
        Smoke.filemanager(self)
    end
    if ok then
        logger.info("Lingering: homescreen getoond")
    else
        self.home = nil
        logger.warn("Lingering: homescreen kon niet laden, bestandsbeheerder blijft zichtbaar:", err)
    end
end

--- Mijn boeken: de OPDS-catalogus, gecachet; tik op een boek opent of downloadt het.
function Lingering:showLibrary()
    local LibraryScreen = require("lingering.ui.libraryscreen")
    LibraryScreen:new{
        library = require("lingering.app.library_service"),
        on_open_book = function(path)
            require("lingering.koreader.navigation").openBook(path)
        end,
    }:show()
    logger.info("Lingering: mijn boeken getoond")
end

--- Inlogscherm. Eerste keer: in plaats van het homescreen; anders vanuit Instellingen.
function Lingering:showSetup(first_run)
    local ok, err = pcall(function()
        require("lingering.ui.setup").show{
            first_run = first_run,
            fm = self.ui,
            on_done = first_run and function() self:showHomeScreen() end or nil,
            on_emergency = function() self:openEmergencyMenu() end,
        }
    end)
    if ok then
        logger.info("Lingering: inlogscherm getoond")
    else
        logger.warn("Lingering: inlogscherm kon niet laden, bestandsbeheerder blijft zichtbaar:", err)
    end
end

function Lingering:showSettings()
    local SettingsScreen = require("lingering.ui.settingsscreen")
    SettingsScreen:new{
        on_account = function() self:showSetup(false) end,
        on_emergency = function() self:openEmergencyMenu() end,
    }:show()
end

--- Noodluik: homescreen dicht, gewone bestandsbeheerder met het volledige menu.
function Lingering:openEmergencyMenu()
    logger.info("Lingering: noodluik, volledig KOReader-menu")
    if self.home then
        self.home:close()
    end
    require("lingering.koreader.navigation").showFullMenu(self.ui)
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
