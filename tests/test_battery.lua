local lu = require("luaunit")
local Battery = require("lingering.domain.battery")

TestBattery = {}

function TestBattery:test_leeg_en_vol()
    lu.assertEquals(Battery.icon(0), "battery_0_bar.svg")
    lu.assertEquals(Battery.icon(95), "battery_full.svg")
    lu.assertEquals(Battery.icon(100), "battery_full.svg")
end

function TestBattery:test_streepjes_lopen_op()
    lu.assertEquals(Battery.icon(10), "battery_0_bar.svg")
    lu.assertEquals(Battery.icon(50), "battery_3_bar.svg")
    lu.assertEquals(Battery.icon(94), "battery_6_bar.svg")
    local last = -1
    for p = 0, 94 do
        local bars = tonumber(Battery.icon(p):match("battery_(%d)_bar"))
        lu.assertTrue(bars >= last)
        last = bars
    end
end

function TestBattery:test_laden_en_onzin()
    lu.assertEquals(Battery.icon(40, true), "battery_charging_full.svg")
    lu.assertEquals(Battery.icon(nil), "battery_0_bar.svg")
    lu.assertEquals(Battery.icon(150), "battery_full.svg")
end
