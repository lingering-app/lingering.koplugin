local lu = require("luaunit")
local StatsSync = require("lingering.domain.stats_sync")

TestStatsSync = {}

function TestStatsSync:test_pending_alles_nieuwste_eerst()
    local list = StatsSync.pending({ ["2026-10-12"] = 60, ["2026-10-14"] = 90.6, ["2026-10-13"] = 0 }, nil)
    lu.assertEquals(list, { { date = "2026-10-14", seconds = 90 }, { date = "2026-10-12", seconds = 60 } })
end

function TestStatsSync:test_pending_vanaf_laatste_verzending_inclusief()
    local list = StatsSync.pending({ ["2026-10-12"] = 60, ["2026-10-13"] = 70, ["2026-10-14"] = 80 }, "2026-10-13")
    lu.assertEquals(list, { { date = "2026-10-14", seconds = 80 }, { date = "2026-10-13", seconds = 70 } })
end

function TestStatsSync:test_chunks()
    local list = {}
    for i = 1, 45 do list[i] = i end
    local chunks = StatsSync.chunks(list, 20)
    lu.assertEquals(#chunks, 3)
    lu.assertEquals(#chunks[1], 20)
    lu.assertEquals(#chunks[3], 5)
    lu.assertEquals(StatsSync.chunks({}, 20), {})
end

function TestStatsSync:test_merge_hoogste_per_dag()
    local merged = StatsSync.merge(
        { ["2026-10-14"] = 900, ["2026-10-13"] = 100 },
        { ["2026-10-14"] = 600, ["2026-10-13"] = 1500, ["2026-10-01"] = 40 })
    lu.assertEquals(merged, { ["2026-10-14"] = 900, ["2026-10-13"] = 1500, ["2026-10-01"] = 40 })
end

function TestStatsSync:test_niet_vaker_dan_interval()
    lu.assertTrue(StatsSync.shouldTry(1000, nil))
    local state = StatsSync.afterTry(1000, 200)
    lu.assertFalse(StatsSync.shouldTry(1000 + StatsSync.INTERVAL - 1, state))
    lu.assertTrue(StatsSync.shouldTry(1000 + StatsSync.INTERVAL, state))
end

function TestStatsSync:test_server_zonder_api_een_dag_niet()
    local state = StatsSync.afterTry(1000, 404)
    lu.assertFalse(StatsSync.shouldTry(1000 + StatsSync.INTERVAL, state))
    lu.assertTrue(StatsSync.shouldTry(1000 + StatsSync.BLOCKED, state))
end

function TestStatsSync:test_onbereikbaar_gewoon_na_interval()
    local state = StatsSync.afterTry(1000, nil)
    lu.assertTrue(StatsSync.shouldTry(1000 + StatsSync.INTERVAL, state))
end
