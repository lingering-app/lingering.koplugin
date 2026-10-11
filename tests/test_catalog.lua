local lu = require("luaunit")
local Catalog = require("lingering.domain.catalog")

local function filetype_of(acquisition)
    return ({ ["application/epub+zip"] = "epub", ["application/pdf"] = "pdf" })[acquisition.type]
end

TestCatalog = {}

function TestCatalog:test_epub_heeft_voorkeur()
    local acq, ft = Catalog.pickAcquisition({
        { href = "a.pdf", type = "application/pdf" },
        { href = "a.epub", type = "application/epub+zip" },
    }, filetype_of)
    lu.assertEquals(acq.href, "a.epub")
    lu.assertEquals(ft, "epub")
end

function TestCatalog:test_terugval_op_ander_bruikbaar_type()
    local acq, ft = Catalog.pickAcquisition({
        { type = "borrow" },
        { href = "x.zip", type = "application/zip" },
        { href = "a.pdf", type = "application/pdf" },
    }, filetype_of)
    lu.assertEquals(acq.href, "a.pdf")
    lu.assertEquals(ft, "pdf")
end

function TestCatalog:test_niets_bruikbaars()
    lu.assertNil(Catalog.pickAcquisition({ { type = "borrow" }, { type = "application/epub+zip" } }, filetype_of))
end

function TestCatalog:test_normalize_boek_en_map()
    local book = Catalog.normalize({
        title = "Nu", author = "Tolle", thumbnail = "t.jpg",
        acquisitions = { { href = "nu.epub", type = "application/epub+zip" } },
    }, filetype_of)
    lu.assertEquals(book, { kind = "book", title = "Nu", author = "Tolle", thumbnail = "t.jpg", href = "nu.epub", filetype = "epub" })

    local folder = Catalog.normalize({ text = "Gelezen", url = "https://x/gelezen" }, filetype_of)
    lu.assertEquals(folder, { kind = "folder", title = "Gelezen", url = "https://x/gelezen" })

    lu.assertNil(Catalog.normalize({ title = "leeg" }, filetype_of))
end

function TestCatalog:test_bestandsnaam()
    lu.assertEquals(Catalog.fileName({ title = "Nu", author = "Tolle", filetype = "epub" }), "Nu - Tolle.epub")
    lu.assertEquals(Catalog.fileName({ title = "Nu" }), "Nu.epub")
end
