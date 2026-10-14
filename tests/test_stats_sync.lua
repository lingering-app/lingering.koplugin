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

local TODAY, YESTERDAY = "2026-10-14", "2026-10-13"

function TestStatsSync:test_lezen_na_sync_telt_op_bij_andere_apparaten()
    -- Bij de sync: Kobo 600 s, ander apparaat 1200 s → som 1800. Daarna 900 s verder op de Kobo.
    local days = StatsSync.combine({ [TODAY] = 1500 }, { [TODAY] = 1800 }, { [TODAY] = 600 })
    lu.assertEquals(days[TODAY], 1800 - 600 + 1500)
end

function TestStatsSync:test_direct_na_sync_de_som()
    local days = StatsSync.combine({ [TODAY] = 600 }, { [TODAY] = 1800 }, { [TODAY] = 600 })
    lu.assertEquals(days[TODAY], 1800)
end

function TestStatsSync:test_dag_alleen_lokaal()
    -- Vandaag na de laatste sync begonnen met lezen: de server weet er nog niets van.
    local days = StatsSync.combine({ [TODAY] = 300 }, { [YESTERDAY] = 1000 }, { [YESTERDAY] = 400 })
    lu.assertEquals(days[TODAY], 300)
    lu.assertEquals(days[YESTERDAY], 1000)
end

function TestStatsSync:test_dag_alleen_op_de_server()
    -- Alleen op een ander apparaat gelezen.
    local days = StatsSync.combine({}, { [YESTERDAY] = 700 }, {})
    lu.assertEquals(days[YESTERDAY], 700)
end

function TestStatsSync:test_eigen_statistieken_gewist_nooit_minder_dan_server()
    local days = StatsSync.combine({ [TODAY] = 0 }, { [TODAY] = 1800 }, { [TODAY] = 600 })
    lu.assertEquals(days[TODAY], 1800)
end

function TestStatsSync:test_nooit_minder_dan_eigen_tijd()
    -- Server kreeg de eigen tijd nooit (sync mislukt), oude momentopname groter dan de som.
    local days = StatsSync.combine({ [TODAY] = 2000 }, { [TODAY] = 500 }, { [TODAY] = 900 })
    lu.assertEquals(days[TODAY], 2000)
end

function TestStatsSync:test_zonder_eerdere_sync()
    local days = StatsSync.combine({ [TODAY] = 600 }, nil, nil)
    lu.assertEquals(days, { [TODAY] = 600 })
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

function TestStatsSync:test_antwoord_omzetten()
    local days = StatsSync.parseSummary({ daily = {
        { date = "2026-10-13", seconds = 1080, minutes = 18 },
        { date = "2026-10-14", seconds = 960.5 },
    } })
    lu.assertEquals(days, { ["2026-10-13"] = 1080, ["2026-10-14"] = 960.5 })
end

function TestStatsSync:test_antwoord_ongeldige_rijen_vallen_weg()
    local days = StatsSync.parseSummary({ daily = {
        { date = "14-10-2026", seconds = 60 },
        { date = "2026-10-14", seconds = "veel" },
        { date = "2026-10-12", seconds = -5 },
        "geen rij",
        { date = "2026-10-11", seconds = 30 },
    } })
    lu.assertEquals(days, { ["2026-10-11"] = 30 })
end

function TestStatsSync:test_antwoord_onbruikbaar()
    lu.assertNil(StatsSync.parseSummary(nil))
    lu.assertNil(StatsSync.parseSummary({}))
    lu.assertNil(StatsSync.parseSummary({ daily = "geen lijst" }))
    lu.assertEquals(StatsSync.parseSummary({ daily = {} }), {})
end

function TestStatsSync:test_zonder_momentopname_hoogste()
    -- Som van de server, maar onbekend welk deel van dit apparaat is: niet optellen.
    local days = StatsSync.combine({ [TODAY] = 900 }, { [TODAY] = 600 }, nil)
    lu.assertEquals(days[TODAY], 900)
end

function TestStatsSync:test_momentopname_zonder_die_dag_is_nul()
    -- Bij de sync had dit apparaat vandaag nog niet gelezen; nu 300 s.
    local days = StatsSync.combine({ [TODAY] = 300 }, { [TODAY] = 1200 }, { [YESTERDAY] = 100 })
    lu.assertEquals(days[TODAY], 1500)
end
