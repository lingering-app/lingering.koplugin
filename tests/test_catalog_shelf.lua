local lu = require("luaunit")
local Catalog = require("lingering.domain.catalog")

TestCatalogShelf = {}

function TestCatalogShelf:test_plank_op_naam()
    local items = {
        { kind = "folder", title = "Al mijn boeken", url = "a" },
        { kind = "folder", title = " aan HET lezen ", url = "b" },
        { kind = "book", title = "Aan het lezen", href = "x" },
    }
    lu.assertEquals(Catalog.findFolder(items, "Aan het lezen").url, "b")
    lu.assertNil(Catalog.findFolder(items, "Gelezen"))
    lu.assertNil(Catalog.findFolder(nil, "Aan het lezen"))
    lu.assertNil(Catalog.findFolder(items, ""))
end
