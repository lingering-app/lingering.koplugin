local lu = require("luaunit")
local StatsSnapshot = require("lingering.domain.stats_snapshot")

-- Lokale tijd: woensdag 14 oktober 2026.
local function at(day, hour, min)
    return os.time{ year = 2026, month = 10, day = day, hour = hour, min = min or 0 }
end

TestStatsSnapshot = {}

function TestStatsSnapshot:test_leeg()
    local s = StatsSnapshot.build{}
    lu.assertEquals(s.v, 5)
    lu.assertEquals(s.sessions, 0)
    lu.assertEquals(s.seconds, 0)
    lu.assertEquals(s.tod, { 0, 0, 0, 0 })
    lu.assertEquals(s.dow, { 0, 0, 0, 0, 0, 0, 0 })
    lu.assertEquals(s.anchor_day, 0)
    lu.assertEquals(s.streak, 0)
    -- 92 nul-bytes: 124 tekens base64 (30 × "AAAA" + "AAA=" voor 2 bytes).
    lu.assertEquals(#s.history_b64, 124)
    lu.assertEquals(s.history_b64:sub(-4), "AAA=")
end

function TestStatsSnapshot:test_base64()
    lu.assertEquals(StatsSnapshot.base64({ 77, 97, 110 }), "TWFu")
    lu.assertEquals(StatsSnapshot.base64({ 77, 97 }), "TWE=")
    lu.assertEquals(StatsSnapshot.base64({ 77 }), "TQ==")
    lu.assertEquals(StatsSnapshot.base64({ 255, 0, 1 }), "/wAB")
end

function TestStatsSnapshot:test_dagnummer()
    lu.assertEquals(StatsSnapshot.dayNumber("2000-01-01"), 0)
    lu.assertEquals(StatsSnapshot.dayNumber("2000-01-02"), 1)
    lu.assertEquals(StatsSnapshot.dayNumber("2001-01-01"), 366) -- 2000 is een schrikkeljaar
end

function TestStatsSnapshot:test_dagdelen_en_weekdagen()
    local s = StatsSnapshot.build{
        starts = { at(14, 7), at(14, 13), at(14, 20), at(15, 2) },
        durations = { 60, 120, 180, 240 },
    }
    lu.assertEquals(s.tod, { 60, 120, 180, 240 })
    -- 14 okt 2026 is een woensdag (index 3), 15 okt donderdag (4).
    lu.assertEquals(s.dow, { 0, 0, 360, 240, 0, 0, 0 })
    lu.assertEquals(s.seconds, 600)
end

function TestStatsSnapshot:test_sessies_na_een_half_uur_pauze()
    local s = StatsSnapshot.build{
        starts = { at(14, 9, 0), at(14, 9, 1), at(14, 9, 40), at(14, 9, 41) },
        durations = { 60, 60, 60, 60 },
    }
    lu.assertEquals(s.sessions, 2)
end

function TestStatsSnapshot:test_anker_bitmap_en_reeks()
    local s = StatsSnapshot.build{
        starts = { at(10, 9), at(12, 9), at(13, 9), at(14, 9) },
        durations = { 60, 60, 60, 60 },
    }
    lu.assertEquals(s.anchor_day, StatsSnapshot.dayNumber("2026-10-14"))
    lu.assertEquals(s.streak, 3) -- 12, 13, 14
    -- bit 0 (14), 1 (13), 2 (12) en 4 (10): 0b00010111 = 23 → eerste byte.
    lu.assertEquals(s.history_b64:sub(1, 4), StatsSnapshot.base64({ 23, 0, 0 }))
end

function TestStatsSnapshot:test_pagina_zonder_tijd_telt_niet_als_leesdag()
    local s = StatsSnapshot.build{ starts = { at(14, 9) }, durations = { 0 } }
    lu.assertEquals(s.anchor_day, 0)
    lu.assertEquals(s.streak, 0)
end

function TestStatsSnapshot:test_paginas_en_uitgelezen_doorgegeven()
    local s = StatsSnapshot.build{ pages = 42, completed = 3 }
    lu.assertEquals(s.pages, 42)
    lu.assertEquals(s.completed, 3)
end
