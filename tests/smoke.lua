--[[--
Rooktest in de emulator. Wordt alleen geladen als LINGERING_TEST gezet is (zie main.lua);
tools/smoke.sh start KOReader in een eigen testmap (KO_HOME) tegen tools/mock_server.py.
LINGERING_TEST=setup   inloggen op de testserver (echte AccountService), daarna afsluiten
LINGERING_TEST=reader  actiebalk → draaien → inhoudsopgave → sync-knop → springen → wegschrijven →
                       boek sluiten
LINGERING_TEST=fm      homescreen (sync-knop) → Mijn boeken → eerste map → Instellingen → Taal →
                       Woordenboek → Account → inloggen (goed/fout) → downloaden → update
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

-- Testaccount van tools/mock_server.py.
local TEST_USER, TEST_PASSWORD = "test", "test"

function Smoke.setup(plugin)
    run{
        { name = "inloggen op de testserver", wait = 2, fn = function()
            local AccountService = require("lingering.app.account_service")
            assert(AccountService.verify(TEST_USER, TEST_PASSWORD), "testserver weigert het testaccount")
            assert(AccountService.save(TEST_USER, TEST_PASSWORD, plugin.ui), "account opslaan mislukt")
        end },
        { name = "afsluiten", fn = function()
            UIManager:quit()
        end },
    }
end

function Smoke.filemanager(plugin)
    local lib
    local state = {}
    -- Homescreen met tijdelijk n boeken (elk met een eigen omslag) in plaats van de echte lijst.
    local function homeWithBooks(n)
        local Books = require("lingering.koreader.books")
        local original = Books.readingBooks
        Books.readingBooks = function(fm, limit)
            local books = {}
            for i = 1, n do
                local book = original(fm, limit)[1]
                if book then
                    book.percent = i * 0.25
                    table.insert(books, book)
                end
            end
            return books
        end
        local ok, home = pcall(function()
            return require("lingering.ui.homescreen"):new{
                fm = plugin.ui, nav = plugin:nav(),
                library = plugin.home.library, collections = plugin.home.collections,
            }
        end)
        Books.readingBooks = original
        assert(ok, home)
        return home
    end
    run{
        { name = "homescreen", wait = 2, fn = function()
            assert(plugin.home, "geen homescreen")
            -- Synchroniseren alleen met de knop: het homescreen haalt zelf niets op.
            assert(plugin.home.sync_item and not plugin.home.sync_item.busy, "homescreen synchroniseert uit zichzelf")
            plugin.home.sync_item:startTask()
        end },
        { name = "sync-kader homescreen", wait = 1, fn = function()
            assert(plugin.home.sync_status and plugin.home.sync_status:isOpen(), "geen kader met voortgang")
            shot("1-home-sync-progress")
        end },
        { name = "homescreen gesynchroniseerd", wait = 6, fn = function()
            assert(not plugin.home.sync_item.busy, "sync-knop homescreen nog bezig")
            assert(not plugin.home.sync_status:isOpen(), "kader niet gesloten na de sync")
            -- Leestijd van alle apparaten: een ander apparaat las vandaag 30 min op de testserver.
            local server = require("lingering.app.session"):read("lingering_stats_server")
            local today = os.date("%Y-%m-%d")
            assert(server and (server[today] or 0) >= 1800, "leestijd niet gesynchroniseerd")
            assert(plugin.home.reading and plugin.home.reading.today >= 1800, "rij telt de server niet mee")
            shot("1-home")
        end },
        { name = "mappen op het homescreen", fn = function()
            assert(plugin.home.shelf_dimen and plugin.home.shelf_dimen.h > 0, "geen mapblokken getoond")
            shot("1b-home-collections")
        end },
        { name = "halve kaarten (2 boeken)", fn = function()
            state.grid_home = homeWithBooks(2)
            assert(#state.grid_home.books == 2, "geen twee boeken")
            UIManager:show(state.grid_home)
        end },
        { name = "halve kaarten getekend", fn = function()
            shot("1c-home-two-books")
            state.grid_home:close()
        end },
        { name = "raster aan het lezen (3 boeken)", fn = function()
            state.grid_home = homeWithBooks(3)
            assert(#state.grid_home.books == 3, "geen drie boeken")
            UIManager:show(state.grid_home)
        end },
        { name = "raster aan het lezen getekend", fn = function()
            shot("1d-home-reading-grid")
            -- Menu van de "…"-knop (alleen tonen: "Gelezen" zou het boek echt op uit zetten).
            local Geom = require("ui/geometry")
            local Screen_ = require("device").screen
            state.grid_home:showBookMenu(state.grid_home.books[1],
                Geom:new{ x = Screen_:scaleBySize(140), y = Screen_:scaleBySize(330), w = 36, h = 36 })
            state.menu = UIManager:getTopmostVisibleWidget()
            assert(state.menu and state.menu.content, "geen menu")
        end },
        { name = "boekmenu getekend", fn = function()
            shot("1g-book-menu")
            state.menu:dismiss()
            state.grid_home:close()
        end },
        { name = "batterij-kader", fn = function()
            local bar = plugin.home.status_bar
            local button = bar.right[bar.slot + 1]
            assert(button and button.onTapBattery, "geen batterijknop")
            button:onTapBattery()
            state.popover = UIManager:getTopmostVisibleWidget()
            assert(state.popover and state.popover.lines, "geen kader")
        end },
        { name = "batterij-kader getekend", fn = function()
            shot("1e-battery-popover")
            state.popover:onTapClose()
            assert(UIManager:getTopmostVisibleWidget() == plugin.home, "kader niet gesloten")
        end },
        { name = "helderheid-kader", fn = function()
            -- Alleen tonen: de emulator heeft geen voorlicht om in te stellen.
            local bar = plugin.home.status_bar
            bar:showBrightness(bar.light_item)
            state.brightness = UIManager:getTopmostVisibleWidget()
            assert(state.brightness and state.brightness.content, "geen helderheid-kader")
        end },
        { name = "helderheid-kader getekend", fn = function()
            shot("1f-brightness-popover")
            state.brightness:dismiss()
        end },
        { name = "draaien binnen portrait", fn = function()
            local Event = require("ui/event")
            UIManager:sendEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPSIDE_DOWN))
            assert(Screen:getRotationMode() == Screen.DEVICE_ROTATED_UPSIDE_DOWN, "niet gedraaid")
            shot("1a-home-upside-down")
            UIManager:sendEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
            assert(Screen:getRotationMode() == Screen.DEVICE_ROTATED_UPSIDE_DOWN, "naar landscape gedraaid")
            UIManager:sendEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
            assert(Screen:getRotationMode() == Screen.DEVICE_ROTATED_UPRIGHT, "niet teruggedraaid")
        end },
        { name = "blok openen", fn = function()
            local Library = require("lingering.app.library_service")
            local title = require("lingering.config").collections[1]
            local url = assert(Library:collectionUrl(title), "map niet gevonden: " .. tostring(title))
            plugin.home.on_open_collection(url, title)
        end },
        { name = "map geopend vanaf homescreen", fn = function()
            local top = UIManager:getTopmostVisibleWidget()
            assert(top and top.stack and top.stack[1] and top.stack[1].url ==
                require("lingering.app.library_service"):collectionUrl(require("lingering.config").collections[1]),
                "Mijn boeken niet in de map geopend")
            shot("1c-collection-opened")
            top:close()
        end },
        { name = "mijn boeken", fn = function()
            plugin:nav().library()
            lib = plugin.screens[1]
            assert(lib and lib.stack, "Mijn boeken niet geopend")
        end },
        { name = "mijn boeken getekend", wait = 2, fn = function()
            assert(lib.entries and #lib.entries > 0, "geen items in Mijn boeken")
            -- Synchroniseren alleen met de knop: het scherm haalt zelf niets op.
            assert(not lib.sync_item.busy, "Mijn boeken synchroniseert uit zichzelf")
            lib.sync_item:startTask()
            assert(lib.sync_item.busy, "sync-knop start niet")
        end },
        { name = "sync-kader", wait = 1, fn = function()
            assert(lib.sync_status and lib.sync_status:isOpen(), "geen kader met voortgang")
            shot("2c-library-sync-progress")
        end },
        { name = "mijn boeken gesynchroniseerd", wait = 6, fn = function()
            assert(not lib.sync_item.busy, "sync-knop nog bezig")
            local Library = require("lingering.app.library_service")
            for _, entry in ipairs(lib.entries) do
                if entry.kind == "folder" then
                    assert(Library:cached(entry.url), "map niet opgehaald: " .. tostring(entry.title))
                end
            end
            assert(not lib.sync_status:isOpen(), "kader niet gesloten na de sync")
            -- Leestijd van alle apparaten: een ander apparaat las vandaag 30 min op de testserver.
            local server = require("lingering.app.session"):read("lingering_stats_server")
            local today = os.date("%Y-%m-%d")
            assert(server and (server[today] or 0) >= 1800, "leestijd niet gesynchroniseerd")
            shot("2-library")
        end },
        { name = "stapel omslagen", fn = function()
            -- Herbruikbare stapel met drie omslagen, in een testvenster.
            local Widgets = require("lingering.ui.widgets")
            local Library = require("lingering.app.library_service")
            local book = Smoke.firstBook(Library)
            assert(book and Library:hasCover(book.thumbnail), "geen omslag in de cache")
            local Screen_ = require("device").screen
            local cw, ch = Screen_:scaleBySize(120), Screen_:scaleBySize(180)
            local sw, sh = math.floor(cw * 2.4), ch
            local covers = {}
            for _ = 1, 3 do table.insert(covers, Widgets.loadCover(Library, book.thumbnail, cw, ch)) end
            local stack = assert(Widgets.coverStack(covers, sw, sh), "geen stapel")
            local FrameContainer = require("ui/widget/container/framecontainer")
            state.stack_window = FrameContainer:new{
                padding = Screen_:scaleBySize(20), bordersize = 0,
                background = require("ffi/blitbuffer").COLOR_WHITE, stack,
            }
            UIManager:show(state.stack_window)
        end },
        { name = "stapel getekend", fn = function()
            shot("2b-stack")
            UIManager:close(state.stack_window)
        end },
        { name = "eerste map", fn = function()
            -- "Al mijn boeken": 300 boeken op de testserver, in pagina's.
            local started = os.clock()
            lib:openEntry(lib.entries[1])
            state.open_ms = math.floor((os.clock() - started) * 1000)
        end },
        { name = "eerste map getekend", wait = 2, fn = function()
            shot("3-folder")
            assert(lib.nav_bar, "geen navigatiebalk in Mijn boeken")
            assert(#lib.entries == 300, "niet alle 300 boeken opgehaald: " .. #lib.entries)
            assert(lib.page_count and lib.page_count > 1, "geen pagina's")
            logger.info("Lingering: SMOKE map met", #lib.entries, "boeken,", lib.page_count, "pagina's, openen", state.open_ms, "ms")
            local started = os.clock()
            lib:onSwipe(nil, { direction = "west" })
            state.turn_ms = math.floor((os.clock() - started) * 1000)
            assert(lib:current().page == 2, "niet naar pagina 2")
        end },
        { name = "pagina 2 getekend", wait = 1, fn = function()
            shot("3b-folder-page-2")
            logger.info("Lingering: SMOKE pagina omslaan", state.turn_ms, "ms")
            lib:onSwipe(nil, { direction = "east" })
            assert(lib:current().page == 1, "niet terug naar pagina 1")
        end },
        { name = "navigatie: Mijn boeken opnieuw → begin", fn = function()
            lib:goToRoot()
            assert(#lib.stack == 1, "niet terug naar het begin")
        end },
        { name = "navigatie: naar instellingen", fn = function()
            plugin:nav().settings()
            assert(lib.closed, "Mijn boeken niet gesloten bij wissel")
            state.settings = plugin.screens[1]
            assert(state.settings and UIManager:getTopmostVisibleWidget() == state.settings, "Instellingen niet bovenaan")
        end },
        { name = "instellingen getekend", wait = 1, fn = function()
            shot("4-settings")
        end },
        { name = "taal", fn = function()
            -- Alleen tonen: echt wisselen zou de taal van de emulator blijvend veranderen.
            state.settings.on_language()
            state.lang = UIManager:getTopmostVisibleWidget()
            assert(state.lang and state.lang.rows and #state.lang.rows == 2, "taalscherm niet geopend")
        end },
        { name = "taal getekend", fn = function()
            shot("4f-language")
            state.lang:close()
        end },
        { name = "woordenboek", fn = function()
            state.settings.on_dictionary()
            state.dict = UIManager:getTopmostVisibleWidget()
            assert(state.dict and state.dict.rows, "woordenboekscherm niet geopend")
        end },
        { name = "woordenboek getekend", fn = function()
            shot("4d-dictionary")
            -- Nederlands kiezen; staat het er nog niet op, dan vraagt KOReader bevestiging.
            -- Het woordenboek komt van de testserver (klein), niet uit KOReaders lijst.
            local Dictionaries = require("lingering.koreader.dictionaries")
            local real_entry = Dictionaries.entry
            Dictionaries.entry = function(name)
                local server = os.getenv("LINGERING_OPDS_URL"):gsub("/opds$", "")
                return { name = name, lang_in = "nld", lang_out = "nld", url = server .. "/dict/test-nl.zip" }
            end
            state.dict.items[1].choose(state.dict)
            Dictionaries.entry = real_entry
        end },
        { name = "woordenboek: bevestigen", wait = 4, fn = function()
            local top = UIManager:getTopmostVisibleWidget()
            if top and top.ok_callback then
                logger.info("Lingering: SMOKE woordenboek, download bevestigd")
                top.ok_callback()
                UIManager:close(top)
            end
        end },
        { name = "woordenboek gekozen", wait = 5, fn = function()
            local Dictionaries = require("lingering.koreader.dictionaries")
            local name = require("lingering.config").dictionaries[1].name
            assert(Dictionaries.isInstalled(plugin.ui, name), "woordenboek niet geïnstalleerd")
            assert(Dictionaries.isEnabled(plugin.ui, name), "woordenboek niet gekozen")
            -- Meldingen van KOReader ("Dictionary downloaded") sluiten.
            for _ = 1, 5 do
                local top = UIManager:getTopmostVisibleWidget()
                if top == state.dict then break end
                UIManager:close(top)
            end
            shot("4e-dictionary-chosen")
            state.dict:close()
        end },
        { name = "over lingering", fn = function()
            state.settings.on_about()
        end },
        { name = "over lingering getekend", fn = function()
            shot("4c-about")
        end },
        { name = "navigatie: vanuit over naar mijn boeken", fn = function()
            plugin:nav().library()
            assert(state.settings.closed, "Instellingen niet gesloten")
            assert(#plugin.screens == 1 and plugin.screens[1].stack, "Mijn boeken niet geopend")
            assert(UIManager:getTopmostVisibleWidget() == plugin.screens[1], "Over Lingering niet gesloten")
        end },
        { name = "navigatie: home", fn = function()
            local library = plugin.screens[1]
            plugin:nav().home()
            assert(library.closed and #plugin.screens == 0, "Mijn boeken niet gesloten")
            assert(UIManager:getTopmostVisibleWidget() == plugin.home, "homescreen niet bovenaan")
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
        { name = "update zoeken", fn = function()
            require("lingering.app.update_service").check(function(result)
                state.update = result
            end)
        end },
        { name = "update gezocht", wait = 3, fn = function()
            assert(state.update and state.update.status ~= "error", "update zoeken mislukt")
            logger.info("Lingering: SMOKE update:", state.update.status, "geïnstalleerd", tostring(state.update.installed), "nieuwste", tostring(state.update.latest))
        end },
        { name = "update installeren in tijdelijke kopie", fn = function()
            -- Alleen in deze test: een kopie van de plugin bijwerken naar de nieuwste tag.
            local tag = state.update and state.update.latest
            if not tag then
                logger.info("Lingering: SMOKE nog geen tag in de repo, installeren overgeslagen")
                return
            end
            local UpdateService = require("lingering.app.update_service")
            local plugin = require("lingering.plugin")
            local real_dir = plugin.dir
            local tmp = os.tmpname()
            os.remove(tmp)
            os.execute("cp -rL '" .. real_dir .. "' '" .. tmp .. "'")
            state.update_tmp = tmp
            plugin.dir = tmp
            UpdateService._install(tag, function(ok, reason)
                plugin.dir = real_dir
                state.update_ok, state.update_reason = ok, reason
            end)
        end },
        { name = "update geïnstalleerd", wait = 3, fn = function()
            local lfs = require("libs/libkoreader-lfs")
            local tmp = state.update_tmp
            if not tmp then return end
            local ok = state.update_ok
            local has_main = lfs.attributes(tmp .. "/main.lua", "mode") == "file"
            local has_backup = lfs.attributes(tmp .. ".bak/main.lua", "mode") == "file"
            local no_tests = lfs.attributes(tmp .. "/tests", "mode") == nil
            local no_zip = lfs.attributes(tmp .. ".update.zip", "mode") == nil
            -- Opruimen zoals bij de volgende start, daarna controleren dat het weg is.
            local plugin = require("lingering.plugin")
            local real_dir = plugin.dir
            plugin.dir = tmp
            require("lingering.app.update_service").cleanup()
            plugin.dir = real_dir
            local backup_gone = lfs.attributes(tmp .. ".bak", "mode") == nil
            require("ffi/util").purgeDir(tmp)
            assert(ok, "installeren mislukt: " .. tostring(state.update_reason))
            assert(has_main and has_backup and no_tests and no_zip, "onverwachte mappen na installeren")
            assert(backup_gone, "reservekopie niet opgeruimd")
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
            -- Batterij-kader in het boek: boven de actiebalk, vrij van de lijn eronder.
            local bar = UIManager:getTopmostVisibleWidget().status_bar
            assert(bar, "geen statusbalk in de actiebalk")
            bar.right[bar.slot + 1]:onTapBattery()
            state.popover = UIManager:getTopmostVisibleWidget()
            assert(state.popover and state.popover.lines, "geen batterij-kader boven de actiebalk")
        end },
        { name = "batterij-kader in het boek getekend", fn = function()
            shot("5b-actionbar-battery")
            state.popover:onTapClose()
            UIManager:close(UIManager:getTopmostVisibleWidget())
        end },
        -- Draai (g-sensor) met de actiebalk open: de balk gaat dicht, het boek draait mee.
        { name = "draaien met actiebalk open", wait = 2, fn = function()
            show_action_bar()
            state.bar = UIManager:getTopmostVisibleWidget()
            state.rotation = require("device").screen:getRotationMode()
            UIManager:sendEvent(require("ui/event"):new("SetRotationMode", (state.rotation + 2) % 4))
        end },
        { name = "boek gedraaid, actiebalk dicht", wait = 2, fn = function()
            local Screen_ = require("device").screen
            assert(UIManager:getTopmostVisibleWidget() ~= state.bar, "actiebalk nog open")
            assert(Screen_:getRotationMode() == (state.rotation + 2) % 4, "boek niet gedraaid")
            UIManager:sendEvent(require("ui/event"):new("SetRotationMode", state.rotation))
        end },
        { name = "inhoudsopgave", fn = function()
            assert(require("lingering.koreader.reader").showToc(ui), "inhoudsopgave niet geopend")
        end },
        { name = "inhoudsopgave getekend", fn = function()
            shot("6-toc")
            UIManager:close(UIManager:getTopmostVisibleWidget())
        end },
        -- Het testboek begint op pagina 1: eerst vooruit, zodat terugbladeren kan.
        { name = "vooruit bladeren", fn = function()
            turn(10, 1)
            assert(ui.kosync:getLastPercent() > 0, "niet vooruit gebladerd")
        end },
        { name = "sync-knop", wait = 3, fn = function()
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

--[[--
Schermafdrukken voor de website (tools/screenshots.sh), tegen de echte catalogus en het
account dat het script in de testmap zet. Drie fases:
- shots-prep:   catalogus en mappen ophalen, de boeken uit "Aan het lezen" downloaden
- shots-reader: boek openen (kosync haalt de echte stand op); met LINGERING_SHOT_MAIN=1 ook
                de bladzijde en de bovenbalk vastleggen
- shots-fm:     homescreen, boekmenu, Mijn boeken, "Al mijn boeken"
]]
local MAX_SHOT_BOOKS = 3

function Smoke.shotsPrep(plugin)
    local Library = require("lingering.app.library_service")
    local Config = require("lingering.config")
    -- Achter elkaar: hoofdcatalogus, dan elke map, dan downloaden en afsluiten.
    local function finish()
        local ok, books = pcall(Library.collectionBooks, Library, "Aan het lezen")
        local n = 0
        for _, book in ipairs(ok and books or {}) do
            if n >= MAX_SHOT_BOOKS then break end
            if not Library:isDownloaded(book) then Library:download(book) end
            n = n + 1
            logger.info("Lingering: SHOTS gedownload:", book.title)
        end
        UIManager:scheduleIn(1, function() UIManager:quit() end)
    end
    local function syncFolders(titles, i)
        local title = titles[i]
        if not title then return finish() end
        local url = Library:collectionUrl(title)
        if not url then return syncFolders(titles, i + 1) end
        Library:sync(url, function() syncFolders(titles, i + 1) end)
    end
    UIManager:scheduleIn(2, function()
        Library:sync(Library:rootUrl(), function(ok)
            logger.info("Lingering: SHOTS catalogus:", ok and "ok" or "mislukt")
            local titles = { "Aan het lezen", Config.finished_collection }
            for _, title in ipairs(Config.collections) do table.insert(titles, title) end
            syncFolders(titles, 1)
        end)
    end)
end

function Smoke.shotsReader(ui, show_action_bar)
    local Navigation = require("lingering.koreader.navigation")
    local ReaderControl = require("lingering.koreader.reader")
    local Event = require("ui/event")
    -- Alles boven het boek sluiten (bijv. KOReaders paneel onderin na een losse tik).
    local function onlyBook()
        for _ = 1, 5 do
            local top = UIManager:getTopmostVisibleWidget()
            if top == nil or top == ui then break end
            UIManager:close(top)
        end
    end
    local steps = {}
    if os.getenv("LINGERING_SHOT_MAIN") == "1" then
        local start_page
        table.insert(steps, { name = "bladeren", wait = 8, fn = function()
            onlyBook()
            -- Een paar pagina's verder, zodat er tekst staat in plaats van de omslag.
            start_page = ui:getCurrentPage()
            for _ = 1, 6 do ReaderControl.turnPage(ui, 1) end
        end })
        table.insert(steps, { name = "bladzijde", wait = 2, fn = function()
            onlyBook()
            shot("lezen-bladzijde")
        end })
        table.insert(steps, { name = "bovenbalk", fn = function() show_action_bar() end })
        table.insert(steps, { name = "bovenbalk vastgelegd", fn = function()
            shot("lezen-bovenbalk")
            onlyBook()
            -- Terug naar de beginpagina: dan schrijft het sluiten niets naar het account.
            ui:handleEvent(Event:new("GotoPage", start_page))
        end })
    else
        table.insert(steps, { name = "stand opgehaald", wait = 8, fn = function() end })
    end
    table.insert(steps, { name = "boek sluiten", fn = function() Navigation.closeBook(ui) end })
    table.insert(steps, { name = "afsluiten", wait = 3, fn = function() UIManager:quit() end })
    run(steps)
end

function Smoke.shotsHome(plugin)
    local state = {}
    run{
        { name = "homescreen synchroniseren", wait = 2, fn = function() plugin.home.sync_item:startTask() end },
        { name = "homescreen", wait = 15, fn = function() shot("home") end },
        { name = "boekmenu", fn = function()
            -- ⋮ van het eerste boek in de rij (zelfde maten als HomeScreen:readingTiles).
            local Geom = require("ui/geometry")
            local Grid = require("lingering.ui.grid")
            local Style = require("lingering.ui.style")
            local col_w = Grid.columnWidth(Screen:getWidth(), 4)
            local y = Screen:scaleBySize(Style.top_bar.height) + Grid.MARGIN + math.floor(col_w * 3 / 2)
            local home = plugin.home
            if home and home.books and #home.books > 1 then
                home:showBookMenu(home.books[1], Geom:new{
                    x = Grid.MARGIN + col_w - Screen:scaleBySize(24), y = y, w = Screen:scaleBySize(24), h = Screen:scaleBySize(40),
                })
                state.menu = UIManager:getTopmostVisibleWidget()
            end
        end },
        { name = "boekmenu vastgelegd", fn = function()
            if state.menu and state.menu.dismiss then
                shot("home-boekmenu")
                state.menu:dismiss()
            end
        end },
        { name = "mijn boeken", fn = function()
            plugin:nav().library()
            plugin.screens[1].sync_item:startTask()
        end },
        { name = "mijn boeken vastgelegd", wait = 10, fn = function()
            shot("mijn-boeken")
            local lib = plugin.screens[1]
            for _, entry in ipairs(lib.entries or {}) do
                if entry.kind == "folder" and entry.title == "Al mijn boeken" then
                    lib:openEntry(entry)
                    -- Omslagen komen alleen met de sync-knop.
                    lib.sync_item:startTask()
                    break
                end
            end
        end },
        { name = "al mijn boeken vastgelegd", wait = 10, fn = function() shot("al-mijn-boeken") end },
        { name = "afsluiten", fn = function() UIManager:quit() end },
    }
end

return Smoke
