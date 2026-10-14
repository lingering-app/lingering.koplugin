local lu = require("luaunit")
local Fakes = require("fakes")
local Session = require("lingering.app.session")
local StatsService = require("lingering.app.stats_service")
local StatsSync = require("lingering.domain.stats_sync")

local TODAY = os.date("%Y-%m-%d")

local function refresh()
    local result = "nog niet"
    StatsService.refresh(nil, function(changed) result = changed end)
    return result
end

TestStatsService = {}

function TestStatsService:setUp()
    Fakes.reset()
    Session.store = nil -- nieuwe nep-opslag van Fakes.reset
end

function TestStatsService:test_verstuurt_en_haalt_som_op()
    Fakes.state.local_days = { [TODAY] = 900, ["2026-01-01"] = 60 }
    Fakes.state.server_days = { [TODAY] = 1500 }
    lu.assertTrue(refresh())
    lu.assertEquals(#Fakes.calls.pushes, 1)
    lu.assertEquals(Fakes.calls.pushes[1][1], { date = TODAY, seconds = 900 })
    lu.assertEquals(Session:read("lingering_stats_server"), { [TODAY] = 1500 })
    lu.assertEquals(Session:read("lingering_stats_pushed"), TODAY)
end

function TestStatsService:test_tonen_hoogste_van_server_en_lokaal()
    Session:save("lingering_stats_server", { [TODAY] = 600, ["2026-10-01"] = 300 })
    Fakes.state.local_days = { [TODAY] = 900 }
    lu.assertEquals(StatsService.days(nil), { [TODAY] = 900, ["2026-10-01"] = 300 })
end

function TestStatsService:test_niets_te_tonen()
    lu.assertNil(StatsService.days(nil))
end

function TestStatsService:test_offline_niets()
    Fakes.state.online = false
    lu.assertFalse(refresh())
    lu.assertNil(Fakes.calls.pushes)
    lu.assertNil(Fakes.calls.fetches)
end

function TestStatsService:test_niet_vaker_dan_eens_per_tien_minuten()
    Fakes.state.local_days = { [TODAY] = 60 }
    refresh()
    lu.assertFalse(refresh())
    lu.assertEquals(#Fakes.calls.pushes, 1)
end

function TestStatsService:test_lange_achterstand_in_porties()
    Fakes.state.local_days = {}
    for day = 1, 45 do
        Fakes.state.local_days[os.date("%Y-%m-%d", os.time{ year = 2026, month = 1, day = day, hour = 12 })] = 60
    end
    refresh()
    lu.assertEquals(#Fakes.calls.pushes, 3)
    lu.assertEquals(#Fakes.calls.pushes[1], StatsSync.CHUNK)
end

function TestStatsService:test_daarna_alleen_vanaf_laatste_verzending()
    Session:save("lingering_stats_pushed", TODAY)
    Fakes.state.local_days = { [TODAY] = 300, ["2026-01-01"] = 60 }
    refresh()
    lu.assertEquals(Fakes.calls.pushes[1], { { date = TODAY, seconds = 300 } })
end

function TestStatsService:test_versturen_mislukt_houdt_alles()
    Session:save("lingering_stats_server", { [TODAY] = 600 })
    Fakes.state.local_days = { [TODAY] = 900 }
    Fakes.state.push_code = nil -- server niet bereikbaar
    lu.assertFalse(refresh())
    lu.assertNil(Fakes.calls.fetches)
    lu.assertNil(Session:read("lingering_stats_pushed"))
    lu.assertEquals(Session:read("lingering_stats_server"), { [TODAY] = 600 })
end

function TestStatsService:test_server_zonder_api_een_dag_niet()
    Fakes.state.local_days = { [TODAY] = 60 }
    Fakes.state.push_code = 404
    refresh()
    local state = Session:read("lingering_stats_state")
    lu.assertFalse(StatsSync.shouldTry(os.time() + StatsSync.INTERVAL, state))
end

function TestStatsService:test_ophalen_mislukt_houdt_oude_som()
    Session:save("lingering_stats_server", { [TODAY] = 600 })
    Fakes.state.fetch_code = 500
    lu.assertFalse(refresh())
    lu.assertEquals(Session:read("lingering_stats_server"), { [TODAY] = 600 })
end

function TestStatsService:test_zelfde_som_is_geen_wijziging()
    Session:save("lingering_stats_server", { [TODAY] = 600 })
    Fakes.state.server_days = { [TODAY] = 600 }
    lu.assertFalse(refresh())
end

function TestStatsService:test_reset_na_ander_account()
    Session:save("lingering_stats_server", { [TODAY] = 600 })
    Session:save("lingering_stats_pushed", TODAY)
    StatsService.reset()
    lu.assertNil(Session:read("lingering_stats_server"))
    lu.assertNil(Session:read("lingering_stats_pushed"))
end

function TestStatsService:test_onbruikbaar_antwoord_houdt_oude_som()
    Session:save("lingering_stats_server", { [TODAY] = 600 })
    Fakes.state.summary_body = { iets = "anders" }
    lu.assertFalse(refresh())
    lu.assertEquals(Session:read("lingering_stats_server"), { [TODAY] = 600 })
end
