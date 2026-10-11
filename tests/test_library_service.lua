local lu = require("luaunit")
local Fakes = require("fakes")
local Library = require("lingering.app.library_service")

local ROOT = "https://opds.lingering.app"

local function book(title)
    return { kind = "book", title = title, author = "A", filetype = "epub", href = "h/" .. title, thumbnail = "t/" .. title }
end

local function path(title)
    return "/boeken/Lingering/" .. title .. " - A.epub"
end

-- Catalogus in de cache: hoofdpagina met de plank, en de plank met boeken.
local function catalog(books)
    Library.store = nil
    Library:saveFeed(ROOT, { { kind = "folder", title = "Aan het lezen", url = "plank" } })
    Library:saveFeed("plank", books)
end

TestLibraryService = {}

function TestLibraryService:setUp()
    Fakes.reset()
    Library.store = nil
end

function TestLibraryService:test_plank_zonder_huidig_boek_en_mappen()
    catalog({ book("Een"), { kind = "folder", title = "Map", url = "m" }, book("Twee") })
    local books = Library:readingBooks(path("Een"))
    lu.assertEquals(#books, 1)
    lu.assertEquals(books[1].title, "Twee")
end

function TestLibraryService:test_geen_plank_geen_boeken()
    Library:saveFeed(ROOT, { { kind = "folder", title = "Gelezen", url = "g" } })
    lu.assertEquals(Library:readingBooks(nil), {})
end

function TestLibraryService:test_serverstand_alleen_voor_gedownload_en_nooit_geopend()
    catalog({ book("Nieuw"), book("Geopend"), book("NietGedownload") })
    Fakes.state.files[path("Nieuw")] = true
    Fakes.state.files[path("Geopend")] = true
    Fakes.state.local_percents[path("Geopend")] = 0.2
    Fakes.state.server_records["digest:" .. path("Nieuw")] = { percent = 0.4 }
    local changed
    Library:refreshServerProgress(Library:readingBooks(nil), function(c) changed = c end)
    lu.assertTrue(changed)
    lu.assertEquals(Fakes.calls.fetch_stored, 1)
    lu.assertEquals(Library:serverPercent(book("Nieuw")), 0.4)
    lu.assertNil(Library:serverPercent(book("Geopend")))
    lu.assertNil(Library:serverPercent(book("NietGedownload")))
end

function TestLibraryService:test_zelfde_stand_is_geen_wijziging()
    catalog({ book("Nieuw") })
    Fakes.state.files[path("Nieuw")] = true
    Fakes.state.server_records["digest:" .. path("Nieuw")] = { percent = 0.4 }
    Library:refreshServerProgress(Library:readingBooks(nil), function() end)
    local changed
    Library:refreshServerProgress(Library:readingBooks(nil), function(c) changed = c end)
    lu.assertFalse(changed)
end

function TestLibraryService:test_ophalen_mislukt_verandert_niets()
    catalog({ book("Nieuw") })
    Fakes.state.files[path("Nieuw")] = true
    Fakes.state.fetch_ok = false
    local changed
    Library:refreshServerProgress(Library:readingBooks(nil), function(c) changed = c end)
    lu.assertFalse(changed)
    lu.assertNil(Library:serverPercent(book("Nieuw")))
end

function TestLibraryService:test_niets_te_doen_meldt_meteen_klaar()
    local changed = "nog niet"
    Library:refreshServerProgress({}, function(c) changed = c end)
    lu.assertFalse(changed)
end
