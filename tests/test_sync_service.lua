local lu = require("luaunit")
local Fakes = require("fakes")
local SyncService = require("lingering.app.sync_service")

local handle = {}

local function reconcile(jump)
    local result = "nog niet"
    SyncService.reconcile(handle, { jump = jump }, function(ok) result = ok end)
    return result
end

TestSyncService = {}

function TestSyncService:setUp() Fakes.reset() end

function TestSyncService:test_niet_ingelogd()
    Fakes.state.logged_in = false
    lu.assertFalse(reconcile(true))
    lu.assertNil(Fakes.calls.fetch)
end

function TestSyncService:test_ophalen_mislukt_schrijft_niets_weg()
    Fakes.state.fetch_ok = false
    lu.assertFalse(reconcile(true))
    lu.assertNil(Fakes.calls.store)
    lu.assertNil(Fakes.calls.jump)
end

function TestSyncService:test_server_verder_springt_zonder_wegschrijven()
    Fakes.state.local_percent = 0.1
    Fakes.state.record = { percent = 0.3, progress = "server-pos" }
    lu.assertTrue(reconcile(true))
    lu.assertEquals(Fakes.calls.jump, "server-pos")
    lu.assertNil(Fakes.calls.store)
end

function TestSyncService:test_server_verder_bij_sluiten_niets()
    Fakes.state.local_percent = 0.1
    Fakes.state.record = { percent = 0.3, progress = "server-pos" }
    lu.assertTrue(reconcile(false))
    lu.assertNil(Fakes.calls.jump)
    lu.assertNil(Fakes.calls.store)
end

function TestSyncService:test_apparaat_verder_schrijft_weg()
    Fakes.state.local_percent = 0.6
    Fakes.state.record = { percent = 0.3 }
    lu.assertTrue(reconcile(true))
    lu.assertEquals(Fakes.calls.store.progress, "local-pos")
end

function TestSyncService:test_wegschrijven_mislukt()
    Fakes.state.record = nil
    Fakes.state.store_ok = false
    lu.assertFalse(reconcile(true))
end

function TestSyncService:test_automatisch_ophalen_offline_slaat_over()
    Fakes.state.online = false
    SyncService.policy.pull(handle)
    lu.assertNil(Fakes.calls.fetch)
end

function TestSyncService:test_automatisch_ophalen_niet_twee_keer_kort_na_elkaar()
    SyncService.policy.pull(handle)
    SyncService.policy.pull(handle)
    lu.assertEquals(Fakes.calls.fetch, 1)
end

function TestSyncService:test_ophalen_mislukt_probeert_nog_een_keer()
    Fakes.state.fetch_ok = false
    SyncService.policy.pull(handle)
    lu.assertEquals(Fakes.calls.fetch, 1)
    Fakes.runScheduled()
    lu.assertEquals(Fakes.calls.fetch, 2)
end

function TestSyncService:test_slaapstand_zonder_wifi_zet_geen_wifi_aan()
    Fakes.state.online, Fakes.state.wifi_on = false, false
    SyncService.policy.push(handle, true)
    lu.assertNil(Fakes.calls.turn_on_wifi)
    lu.assertNil(Fakes.calls.fetch)
end

function TestSyncService:test_slaapstand_met_wifi_vergelijkt_en_zet_wifi_uit()
    Fakes.state.record = { percent = 0.5 }
    SyncService.policy.push(handle, true)
    lu.assertEquals(Fakes.calls.fetch, 1)
    lu.assertEquals(Fakes.calls.disable_wifi, 1)
end

function TestSyncService:test_sluiten_offline_doet_niets()
    Fakes.state.online = false
    SyncService.policy.close(handle)
    lu.assertNil(Fakes.calls.fetch)
end

function TestSyncService:test_syncknop_wifi_uit_gaat_aan_en_weer_uit()
    Fakes.state.online, Fakes.state.wifi_on = false, false
    Fakes.state.record = { percent = 0.5 }
    local result
    SyncService.syncNow({ kosync = handle }, function(ok) result = ok end)
    lu.assertTrue(result)
    lu.assertEquals(Fakes.calls.turn_on_wifi, 1)
    -- Eerst klaar melden (icoon stopt), wifi pas daarna uit.
    lu.assertNil(Fakes.calls.disable_wifi)
    Fakes.runScheduled()
    lu.assertEquals(Fakes.calls.disable_wifi, 1)
end

function TestSyncService:test_syncknop_wifi_aan_blijft_aan()
    Fakes.state.record = { percent = 0.5 }
    SyncService.syncNow({ kosync = handle }, function() end)
    Fakes.runScheduled()
    lu.assertNil(Fakes.calls.disable_wifi)
end

function TestSyncService:test_syncknop_zonder_verbinding()
    Fakes.state.online, Fakes.state.wifi_on, Fakes.state.wifi_fails = false, false, true
    local result
    SyncService.syncNow({ kosync = handle }, function(ok) result = ok end)
    lu.assertFalse(result)
    Fakes.runScheduled()
    lu.assertEquals(Fakes.calls.disable_wifi, 1)
end
