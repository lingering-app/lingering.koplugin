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
    local state = {}
    run{
        { name = "homescreen", wait = 2, fn = function()
            assert(plugin.home, "geen homescreen")
            shot("1-home")
        end },
        { name = "mappen op het homescreen", fn = function()
            assert(plugin.home.shelf_dimen and plugin.home.shelf_dimen.h > 0, "geen mapblokken getoond")
            shot("1b-home-collections")
        end },
        { name = "raster aan het lezen (3 boeken)", fn = function()
            -- Tijdelijk drie boeken (elk met een eigen omslag) in plaats van de echte lijst.
            local Books = require("lingering.koreader.books")
            local original = Books.readingBooks
            Books.readingBooks = function(fm, limit)
                local books = {}
                for i = 1, 3 do
                    local book = original(fm, limit)[1]
                    if book then
                        book.percent = i * 0.25
                        table.insert(books, book)
                    end
                end
                return books
            end
            local ok, err = pcall(function()
                state.grid_home = require("lingering.ui.homescreen"):new{
                    fm = plugin.ui, nav = plugin:nav(),
                }
            end)
            Books.readingBooks = original
            assert(ok, err)
            assert(#state.grid_home.books == 3, "geen drie boeken")
            UIManager:show(state.grid_home)
        end },
        { name = "raster aan het lezen getekend", fn = function()
            shot("1d-home-reading-grid")
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
            assert(lib.page_entries and #lib.page_entries > 0, "geen items in Mijn boeken")
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
            local sw, sh = Widgets.stackSize(cw, ch)
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
            lib:openEntry(lib.page_entries[1])
        end },
        { name = "eerste map getekend", wait = 2, fn = function()
            shot("3-folder")
            assert(lib.nav_bar, "geen navigatiebalk in Mijn boeken")
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
        { name = "inhoudsopgave", fn = function()
            assert(require("lingering.koreader.reader").showToc(ui), "inhoudsopgave niet geopend")
        end },
        { name = "inhoudsopgave getekend", fn = function()
            shot("6-toc")
            UIManager:close(UIManager:getTopmostVisibleWidget())
        end },
        -- Elke run schrijft 5 pagina's verder weg; is het testboek bijna uit, dan eerst naar
        -- 30% en die stand rechtstreeks naar de server (anders kan "verder bladeren" niet meer;
        -- niet naar pagina 1, want dan kan "terugbladeren" niet).
        { name = "testboek terugzetten (bijna uit)", fn = function()
            if (ui.kosync:getLastPercent() or 0) < 0.8 then return end
            local page = math.max(10, math.floor(ui.document:getPageCount() * 0.3))
            ui:handleEvent(require("ui/event"):new("GotoPage", page))
            local session = assert(require("lingering.koreader.kosync").session(ui.kosync), "geen sessie")
            session:store(session:snapshot(), function(ok)
                logger.info("Lingering: SMOKE testboek teruggezet:", ok)
            end)
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

return Smoke
