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

function TestLibraryService:test_verse_cache_wordt_niet_opnieuw_opgehaald()
    catalog()
    local changed
    Library:refreshCollections({ "Aan het lezen", "Al mijn boeken" }, function(c) changed = c end)
    Fakes.runScheduled()
    Fakes.runScheduled()
    Fakes.runScheduled()
    lu.assertEquals(self.synced, {})
    lu.assertFalse(changed)
end

function TestLibraryService:test_verouderde_mappen_worden_ververst()
    catalog()
    -- Cache tien minuten en een seconde oud maken.
    local all = Library.store:readSetting("feeds")
    for _, feeds in pairs(all) do
        for _, feed in pairs(feeds) do feed.fetched = os.time() - 601 end
    end
    local changed
    Library:refreshCollections({ "Aan het lezen", "Al mijn boeken" }, function(c) changed = c end)
    for _ = 1, 5 do Fakes.runScheduled() end
    lu.assertEquals(self.synced, { ROOT, "lezen", "alles" })
    lu.assertTrue(changed)
end
