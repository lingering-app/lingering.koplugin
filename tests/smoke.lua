--[[--
Rooktest in de emulator. Wordt alleen geladen als LINGERING_TEST gezet is (zie main.lua).
LINGERING_TEST=fm      homescreen → Mijn boeken → eerste map → Instellingen → Account →
                       inloggen (goed/fout) → downloaden (tijdelijk) → omslag zonder cache
LINGERING_TEST=reader  actiebalk → inhoudsopgave → sync-knop → springen → wegschrijven →
                       boek sluiten (let op: schrijft echte voortgang naar het testaccount)
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
            lib = LibraryScreen:new{ library = require("lingering.app.library_service"), on_open_book = function() end }
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
        { name = "inlogscherm (account)", fn = function()
            plugin:showSetup(false)
        end },
        { name = "inlogscherm getekend", wait = 1, fn = function()
            shot("4b-account")
            -- Invoervenster en achtergrond sluiten.
            UIManager:close(UIManager:getTopmostVisibleWidget())
            UIManager:close(UIManager:getTopmostVisibleWidget())
        end },
        { name = "inloggen: juiste gegevens", fn = function()
            local Opds = require("lingering.koreader.opds")
            local AccountService = require("lingering.app.account_service")
            local user, pass = Opds.credentials(require("lingering.config").opds_url)
            assert(user and pass, "geen opgeslagen account om mee te testen")
            assert(AccountService.verify(user, pass), "inloggen met opgeslagen gegevens mislukt")
            assert(AccountService.save(user, pass, plugin.ui), "opslaan mislukt")
        end },
        { name = "inloggen: fout wachtwoord", fn = function()
            local Opds = require("lingering.koreader.opds")
            local AccountService = require("lingering.app.account_service")
            local user = Opds.credentials(require("lingering.config").opds_url)
            local ok, stage = AccountService.verify(user, "dit-is-fout-" .. os.time())
            assert(not ok, "fout wachtwoord werd geaccepteerd")
            logger.info("Lingering: SMOKE fout wachtwoord geweigerd bij", stage)
        end },
        { name = "downloaden naar tijdelijke map", fn = function()
            local Library = require("lingering.app.library_service")
            local lfs = require("libs/libkoreader-lfs")
            local book = Smoke.firstBook(Library)
            assert(book, "geen boek in de catalogus gevonden")
            local tmp = os.tmpname()
            os.remove(tmp)
            -- Alleen in deze test: download naar een tijdelijk pad in plaats van ~/Lingering.
            local real_path = Library.bookPath
            Library.bookPath = function() return tmp, tmp:match("^(.*)/") end
            local ok, path = Library:download(book)
            Library.bookPath = real_path
            local size = path and lfs.attributes(path, "size") or 0
            if path then os.remove(path) end
            assert(ok and size > 0, "download mislukt of leeg")
            logger.info("Lingering: SMOKE download", size, "bytes")
        end },
        { name = "omslag zonder cache", fn = function()
            local Library = require("lingering.app.library_service")
            local book = Smoke.firstBook(Library)
            assert(book and book.thumbnail, "geen boek met omslag gevonden")
            local tmp = os.tmpname()
            local real_cover = Library.coverPath
            Library.coverPath = function() return tmp end
            local ok = Library:fetchCover(book.thumbnail)
            Library.coverPath = real_cover
            local bb = ok and require("ui/renderimage"):renderImageFile(tmp, false)
            os.remove(tmp)
            assert(ok and bb, "omslag niet opgehaald of onleesbaar")
            logger.info("Lingering: SMOKE omslag", bb:getWidth(), "x", bb:getHeight())
            bb:free()
        end },
    }
end

-- Eerste boek in de catalogus (uit de cache): hoofdpagina → eerste map → eerste boek.
function Smoke.firstBook(Library)
    local root = Library:cached(Library:rootUrl())
    for _, entry in ipairs(root and root.items or {}) do
        if entry.kind == "book" then return entry end
        if entry.kind == "folder" then
            local folder = Library:cached(entry.url)
            for _, inner in ipairs(folder and folder.items or {}) do
                if inner.kind == "book" then return inner end
            end
        end
    end
end

function Smoke.reader(ui, show_action_bar)
    local SyncService = require("lingering.app.sync_service")
    local ReaderControl = require("lingering.koreader.reader")
    local state = {}
    local function turn(n, d) for _ = 1, n do ReaderControl.turnPage(ui, d) end end
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
            SyncService.syncNow(ui, function(ok)
                logger.info("Lingering: SMOKE sync-knop resultaat", ok)
            end)
        end },
        -- Springen: terugbladeren, synchroniseren → weer op de serverstand.
        { name = "terugbladeren", wait = 2, fn = function()
            state.server = ui.kosync:getLastPercent()
            turn(5, -1)
            assert(ui.kosync:getLastPercent() < state.server, "niet teruggebladerd")
            SyncService.syncNow(ui, function(ok) state.jump_ok = ok end)
        end },
        { name = "springen naar serverstand", wait = 3, fn = function()
            assert(state.jump_ok, "sync na terugbladeren mislukt")
            local now = ui.kosync:getLastPercent()
            assert(math.abs(now - state.server) < 0.001, "niet gesprongen: " .. now .. " i.p.v. " .. state.server)
        end },
        -- Wegschrijven: verder bladeren dan de server, synchroniseren → server krijgt deze stand.
        { name = "verder bladeren", fn = function()
            turn(5, 1)
            state.ahead = ui.kosync:getLastPercent()
            assert(state.ahead > state.server, "niet verder gebladerd")
            SyncService.syncNow(ui, function(ok) state.push_ok = ok end)
        end },
        { name = "server heeft nieuwe stand", wait = 3, fn = function()
            assert(state.push_ok, "wegschrijven mislukt")
            -- Controle: terug en opnieuw synchroniseren moet naar de weggeschreven stand springen.
            turn(5, -1)
            SyncService.syncNow(ui, function(ok) state.check_ok = ok end)
        end },
        { name = "weggeschreven stand teruggehaald", wait = 3, fn = function()
            assert(state.check_ok, "controle-sync mislukt")
            local now = ui.kosync:getLastPercent()
            assert(math.abs(now - state.ahead) < 0.001, "server had de nieuwe stand niet: " .. now)
        end },
        { name = "boek sluiten", wait = 3, fn = function()
            assert(Navigation.closeBook(ui), "boek niet gesloten")
        end },
    }
end

return Smoke
