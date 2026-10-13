local lu = require("luaunit")
local ReadingStats = require("lingering.domain.reading_stats")

TestReadingStats = {}

-- Woensdag 14 oktober 2026, 15:00 lokale tijd.
local NOW = os.time{ year = 2026, month = 10, day = 14, hour = 15 }

function TestReadingStats:test_leeg()
    lu.assertEquals(ReadingStats.summary({}, NOW), { today = 0, week = 0, streak = 0, year = 0 })
end

function TestReadingStats:test_vandaag_week_jaar()
    local s = ReadingStats.summary({
        ["2026-10-14"] = 600,   -- vandaag
        ["2026-10-12"] = 300,   -- maandag: deze week
        ["2026-10-11"] = 900,   -- zondag: vorige week
        ["2026-01-02"] = 100,
        ["2025-12-31"] = 5000,  -- vorig jaar
    }, NOW)
    lu.assertEquals(s.today, 600)
    lu.assertEquals(s.week, 900)
    lu.assertEquals(s.year, 1900)
end

function TestReadingStats:test_reeks_tot_vandaag()
    local s = ReadingStats.summary({
        ["2026-10-14"] = 60, ["2026-10-13"] = 60, ["2026-10-12"] = 60, ["2026-10-10"] = 60,
    }, NOW)
    lu.assertEquals(s.streak, 3)
end

function TestReadingStats:test_reeks_vandaag_nog_niet_gelezen()
    local s = ReadingStats.summary({ ["2026-10-13"] = 60, ["2026-10-12"] = 60 }, NOW)
    lu.assertEquals(s.streak, 2)
end

function TestReadingStats:test_reeks_over_maandgrens()
    local now = os.time{ year = 2026, month = 3, day = 1, hour = 9 }
    local s = ReadingStats.summary({ ["2026-03-01"] = 1, ["2026-02-28"] = 1, ["2026-02-27"] = 1 }, now)
    lu.assertEquals(s.streak, 3)
end
