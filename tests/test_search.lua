local lu = require("luaunit")
local Search = require("lingering.domain.search")

local function book(title, author, href)
    return { kind = "book", title = title, author = author, href = href or ("h/" .. title) }
end

local ALL = {
    book("De Stille Haven", "Anna de Vries"),
    book("Het Lange Pad", "Bram Jansen"),
    book("Émile ou de l'éducation", "Jean-Jacques Rousseau"),
    { kind = "folder", title = "Haven", url = "f" },
}

TestSearch = {}

function TestSearch:test_op_titel_en_auteur()
    lu.assertEquals(#Search.books({ ALL }, "haven"), 1)
    lu.assertEquals(Search.books({ ALL }, "jansen")[1].title, "Het Lange Pad")
end

function TestSearch:test_alle_woorden_moeten_voorkomen()
    lu.assertEquals(#Search.books({ ALL }, "stille vries"), 1)
    lu.assertEquals(#Search.books({ ALL }, "stille jansen"), 0)
end

function TestSearch:test_hoofdletters_en_accenten_maken_niet_uit()
    lu.assertEquals(#Search.books({ ALL }, "EMILE"), 1)
    lu.assertEquals(#Search.books({ ALL }, "éducation"), 1)
    lu.assertEquals(#Search.books({ ALL }, "education"), 1)
end

function TestSearch:test_mappen_tellen_niet()
    for _, item in ipairs(Search.books({ ALL }, "haven")) do
        lu.assertEquals(item.kind, "book")
    end
end

function TestSearch:test_zelfde_boek_in_twee_mappen_een_keer()
    local reading = { book("De Stille Haven", "Anna de Vries") }
    lu.assertEquals(#Search.books({ ALL, reading }, "haven"), 1)
end

function TestSearch:test_lege_zoekterm_niets()
    lu.assertEquals(Search.books({ ALL }, "   "), {})
    lu.assertEquals(Search.books({ ALL }, nil), {})
end

function TestSearch:test_op_titel_gesorteerd()
    local found = Search.books({ ALL }, "e")
    lu.assertEquals(found[1].title, "De Stille Haven")
    lu.assertEquals(found[#found].title, "Het Lange Pad")
end

function TestSearch:test_getallen_in_natuurlijke_volgorde()
    local found = Search.books({ { book("Deel 10"), book("Deel 2"), book("Deel 125"), book("Deel 25") } }, "deel")
    local titles = {}
    for i, item in ipairs(found) do titles[i] = item.title end
    lu.assertEquals(titles, { "Deel 2", "Deel 10", "Deel 25", "Deel 125" })
end
