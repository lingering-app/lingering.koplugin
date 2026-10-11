--[[--
Rooktest in de emulator. Wordt alleen geladen als LINGERING_TEST gezet is (zie main.lua).
LINGERING_TEST=fm      homescreen → Mijn boeken → eerste map → Instellingen
LINGERING_TEST=reader  actiebalk → inhoudsopgave → sync-knop → boek sluiten
LINGERING_SHOTS=<map>  schermafdrukken
Elke scène logt "Lingering: SMOKE <naam> OK"; fouten verschijnen als WARN/ERROR in de log.
]]
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = require("device").screen

local shots = os.getenv("LINGERING_SHOTS")
local function shot(name)
    if shots then Screen:shot(shots .. "/" .. name .. ".png") end
end

local function run(steps)
    local t = 0
    for _, step in ipairs(steps) do
        t = t + (step.wait or 1)
        UIManager:scheduleIn(t, function()
            local ok, err = pcall(step.fn)
            if ok then
                logger.info("Lingering: SMOKE", step.name, "OK")
            else
                logger.warn("Lingering: SMOKE", step.name, "MISLUKT", err)
            end
        end)
    end
end

local Smoke = {}

function Smoke.filemanager(plugin)
    local lib
    run{
        { name = "homescreen", wait = 2, fn = function()
            assert(plugin.home, "geen homescreen")
            shot("1-home")
        end },
        { name = "mijn boeken", fn = function()
            local LibraryScreen = require("lingering.ui.libraryscreen")
            lib = LibraryScreen:new{ library = require("lingering.app.library"), on_open_book = function() end }
            lib:show()
        end },
        { name = "mijn boeken getekend", wait = 2, fn = function()
            assert(lib.page_entries and #lib.page_entries > 0, "geen items in Mijn boeken")
            shot("2-library")
        end },
        { name = "eerste map", fn = function()
            lib:openEntry(lib.page_entries[1])
        end },
        { name = "eerste map getekend", wait = 2, fn = function()
            shot("3-folder")
            lib:close()
        end },
        { name = "instellingen", fn = function()
            plugin:showSettings()
        end },
        { name = "instellingen getekend", wait = 1, fn = function()
            shot("4-settings")
        end },
    }
end

function Smoke.reader(ui, show_action_bar)
    local Kosync = require("lingering.koreader.kosync")
    local Navigation = require("lingering.koreader.navigation")
    run{
        { name = "actiebalk", wait = 3, fn = function()
            show_action_bar()
        end },
        { name = "actiebalk getekend", fn = function()
            shot("5-actionbar")
            UIManager:close(UIManager:getTopmostVisibleWidget())
        end },
        { name = "inhoudsopgave", fn = function()
            assert(require("lingering.koreader.reader").showToc(ui), "inhoudsopgave niet geopend")
        end },
        { name = "inhoudsopgave getekend", fn = function()
            shot("6-toc")
            UIManager:close(UIManager:getTopmostVisibleWidget())
        end },
        { name = "sync-knop", fn = function()
            Kosync.syncNow(ui, function(ok)
                logger.info("Lingering: SMOKE sync-knop resultaat", ok)
            end)
        end },
        { name = "boek sluiten", wait = 3, fn = function()
            assert(Navigation.closeBook(ui), "boek niet gesloten")
        end },
    }
end

return Smoke
