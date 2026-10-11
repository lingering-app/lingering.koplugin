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
