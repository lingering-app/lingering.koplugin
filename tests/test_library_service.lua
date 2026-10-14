local lu = require("luaunit")
local Fakes = require("fakes")
local Library = require("lingering.app.library_service")

local ROOT = "https://opds.lingering.app"

local function book(title)
    return { kind = "book", title = title, author = "A", filetype = "epub", href = "h/" .. title, thumbnail = "t/" .. title }
end

local function catalog()
    Library:saveFeed(ROOT, {
        { kind = "folder", title = "Aan het lezen", url = "lezen" },
        { kind = "folder", title = "Al mijn boeken", url = "alles" },
    })
    Library:saveFeed("lezen", { book("Een"), { kind = "folder", title = "Sub", url = "s" } })
    Library:saveFeed("alles", { book("Een"), book("Twee") })
end

TestLibraryService = {}

function TestLibraryService:setUp()
    Fakes.reset()
    Library.store = nil
    self.synced = {}
    Library.sync = function(_, url, done)
        table.insert(self.synced, url)
        done(true)
    end
    Library.fetchCover = function() return false end
end

function TestLibraryService:test_map_op_naam()
    catalog()
    lu.assertEquals(Library:collectionUrl("al MIJN boeken"), "alles")
    lu.assertNil(Library:collectionUrl("Gelezen"))
end

function TestLibraryService:test_boeken_uit_map_zonder_submappen()
    catalog()
    local books = Library:collectionBooks("Aan het lezen")
    lu.assertEquals(#books, 1)
    lu.assertEquals(books[1].title, "Een")
    lu.assertEquals(Library:collectionBooks("Bestaat niet"), {})
end

function TestLibraryService:test_sync_knop_haalt_hoofdpagina_en_mappen_altijd_op()
    catalog() -- verse cache: toch opnieuw ophalen (alleen de knop roept dit aan)
    local changed
    Library:refreshCollections({ "Aan het lezen", "Al mijn boeken" }, function(c) changed = c end)
    for _ = 1, 5 do Fakes.runScheduled() end
    lu.assertEquals(self.synced, { ROOT, "lezen", "alles" })
    lu.assertTrue(changed)
end

function TestLibraryService:test_onbekende_map_wordt_overgeslagen()
    catalog()
    Library:refreshCollections({ "Bestaat niet", "Al mijn boeken" }, function() end)
    for _ = 1, 5 do Fakes.runScheduled() end
    lu.assertEquals(self.synced, { ROOT, "alles" })
end

function TestLibraryService:test_gelezen_op_website_wordt_hier_gelezen()
    Library:saveFeed(ROOT, { { kind = "folder", title = "Gelezen", url = "gelezen" } })
    Library:saveFeed("gelezen", { book("Een"), book("Twee") })
    local een, twee = Library:bookPath(book("Een")), Library:bookPath(book("Twee"))
    Fakes.state.files = { [een] = true, [twee] = true }
    Fakes.state.statuses = { [een] = "reading", [twee] = "complete" }
    local changed
    Library:syncFinished(function(c) changed = c end)
    lu.assertTrue(changed)
    lu.assertEquals(Fakes.calls.finished, een)
    lu.assertEquals(self.synced, { "gelezen" })
end

function TestLibraryService:test_gelezen_ophalen_mislukt_gebruikt_cache()
    Library:saveFeed(ROOT, { { kind = "folder", title = "Gelezen", url = "gelezen" } })
    Library:saveFeed("gelezen", { book("Een") })
    local een = Library:bookPath(book("Een"))
    Fakes.state.files = { [een] = true }
    Fakes.state.statuses = { [een] = "reading" }
    Library.sync = function(_, _, done) done(false) end
    local changed
    Library:syncFinished(function(c) changed = c end)
    lu.assertTrue(changed)
end

function TestLibraryService:test_gelezen_niet_gedownload_doet_niets()
    Library:saveFeed(ROOT, { { kind = "folder", title = "Gelezen", url = "gelezen" } })
    Library:saveFeed("gelezen", { book("Een") })
    Fakes.state.files = {}
    local changed
    Library:syncFinished(function(c) changed = c end)
    lu.assertFalse(changed)
    lu.assertNil(Fakes.calls.finished)
end

function TestLibraryService:test_geen_map_gelezen_doet_niets()
    catalog()
    local changed
    Library:syncFinished(function(c) changed = c end)
    lu.assertFalse(changed)
end

function TestLibraryService:test_omslagen_in_de_achtergrond()
    Library.credentials = function() return "u", "p" end
    local bestaand = Library:coverPath("t/oud")
    Fakes.state.files = { [bestaand] = true }
    local fetched, jobs
    Library:fetchCoversAsync({ "t/oud", "t/nieuw", "t/nieuw" }, function(n, j) fetched, jobs = n, j end)
    -- Alleen de ontbrekende, en dubbele maar één keer.
    lu.assertEquals(#Fakes.calls.background, 1)
    lu.assertEquals(Fakes.calls.background[1].url, "t/nieuw")
    lu.assertEquals(fetched, 1)
    lu.assertEquals(#jobs, 1)
end
