local lu = require("luaunit")
local Layout = require("lingering.domain.layout")

TestLayout = {}

function TestLayout:test_derden_tussen_de_stroken()
    local z = Layout.readerZones(
        { x = 0, y = 0, w = 1, h = 1/8 },
        { x = 1/4, y = 0, w = 2/4, h = 1/5 },
        { x = 0, y = 7/8, w = 1, h = 1/8 })
    lu.assertAlmostEquals(z.backward.y, 1/8, 1e-9)
    lu.assertAlmostEquals(z.backward.h, 6/8, 1e-9)
    lu.assertAlmostEquals(z.close.x, 1/3, 1e-9)
    lu.assertAlmostEquals(z.forward.x + z.forward.w, 1, 1e-9)
    lu.assertEquals(z.top, { x = 0, y = 0, w = 1, h = 1/8 })
end

function TestLayout:test_rasterrijen_beginnen_op_nul_en_sluiten_aan()
    -- De crash bij schuiven: ScrollableContainer zoekt de rij op y = 0.
    local rows = Layout.gridRows(9, 4, 300, 10)
    lu.assertEquals(#rows, 3)
    lu.assertEquals(rows[1].top, 0)
    lu.assertEquals(rows[1].bottom, 309)
    for i = 2, #rows do
        lu.assertEquals(rows[i].top, rows[i - 1].bottom + 1)
    end
end

function TestLayout:test_een_boek_is_een_rij()
    local rows = Layout.gridRows(1, 4, 300, 10)
    lu.assertEquals(#rows, 1)
    lu.assertEquals(rows[1].top, 0)
end

function TestLayout:test_rijen_van_verschillende_hoogte()
    local rows = Layout.stackRows({ 400, 300, 300 }, 20)
    lu.assertEquals(rows[1], { top = 0, bottom = 419 })
    lu.assertEquals(rows[2], { top = 420, bottom = 719 })
    lu.assertEquals(rows[3], { top = 720, bottom = 1019 })
end

function TestLayout:test_paginas_vullen_tot_het_past()
    -- 10 + 300 + 20 + 300 + 20 + 300 = 950 past in 1000; een vierde rij niet.
    local pages = Layout.pages({ 300, 300, 300, 300, 300, 300, 300 }, 1000, 10, 20)
    lu.assertEquals(pages, { { first = 1, last = 3 }, { first = 4, last = 6 }, { first = 7, last = 7 } })
end

function TestLayout:test_paginas_precies_passend()
    lu.assertEquals(Layout.pages({ 490, 490 }, 1000, 0, 20), { { first = 1, last = 2 } })
    lu.assertEquals(Layout.pages({ 490, 491 }, 1000, 0, 20), { { first = 1, last = 1 }, { first = 2, last = 2 } })
end

function TestLayout:test_paginas_rijen_van_verschillende_hoogte()
    -- mappen (400) en boeken (300): 10 + 400 + 20 + 300 = 730; + 20 + 300 = 1050 te veel.
    local pages = Layout.pages({ 400, 300, 300 }, 1000, 10, 20)
    lu.assertEquals(pages, { { first = 1, last = 2 }, { first = 3, last = 3 } })
end

function TestLayout:test_te_hoge_rij_eigen_pagina()
    lu.assertEquals(Layout.pages({ 1200, 300 }, 1000, 10, 20), { { first = 1, last = 1 }, { first = 2, last = 2 } })
end

function TestLayout:test_paginas_zonder_rijen()
    lu.assertEquals(Layout.pages({}, 1000, 10, 20), { { first = 1, last = 0 } })
end

function TestLayout:test_rijen_passend_zonder_krimpen()
    -- 10 + 3 × 300 + 2 × 20 = 950 ≤ 1000; er blijft te weinig over voor een vierde rij.
    lu.assertEquals({ Layout.fitRows(1000, 300, 20, 10) }, { 3, 300 })
end

function TestLayout:test_bijna_een_rij_extra_dan_krimpen()
    -- 2 rijen van 300 passen in 800 (10 + 620), er blijft 190 over (≥ 0,4 × 320): 3 rijen.
    local rows, h = Layout.fitRows(800, 300, 20, 10)
    lu.assertEquals(rows, 3)
    lu.assertTrue(10 + 3 * h + 2 * 20 <= 800)
    lu.assertTrue(h < 300)
end

function TestLayout:test_altijd_minstens_een_rij()
    lu.assertEquals({ Layout.fitRows(200, 300, 20, 10) }, { 1, 300 })
end
