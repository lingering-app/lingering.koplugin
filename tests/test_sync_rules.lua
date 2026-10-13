local lu = require("luaunit")
local SyncRules = require("lingering.domain.sync_rules")

local function decide(here, fetched, jump)
    return SyncRules.decide(here, fetched, jump)
end

TestSyncRules = {}

function TestSyncRules:test_ophalen_mislukt_schrijft_nooit_weg()
    lu.assertEquals(decide(0.5, { ok = false }, true), "fail")
    lu.assertEquals(decide(0.5, nil, true), "fail")
end

function TestSyncRules:test_geen_stand_op_server_schrijft_weg()
    lu.assertEquals(decide(0.5, { ok = true, record = nil }, true), "push")
    lu.assertEquals(decide(0.5, { ok = true, record = { percent = nil } }, true), "push")
end

function TestSyncRules:test_server_verder_springt()
    lu.assertEquals(decide(0.118, { ok = true, record = { percent = 0.1527 } }, true), "jump")
end

function TestSyncRules:test_server_verder_zonder_springen_doet_niets()
    lu.assertEquals(decide(0.118, { ok = true, record = { percent = 0.1527 } }, false), "none")
end

function TestSyncRules:test_apparaat_verder_schrijft_weg()
    lu.assertEquals(decide(0.1527, { ok = true, record = { percent = 0.118 } }, true), "push")
end

function TestSyncRules:test_gelijk_binnen_marge_doet_niets()
    lu.assertEquals(decide(0.5, { ok = true, record = { percent = 0.5004 } }, true), "none")
    lu.assertEquals(decide(0.5, { ok = true, record = { percent = 0.4996 } }, true), "none")
end

function TestSyncRules:test_percentage_als_tekst()
    lu.assertEquals(decide("0.4", { ok = true, record = { percent = "0.6" } }, true), "jump")
end

function TestSyncRules:test_onleesbaar_percentage_is_mislukt()
    lu.assertEquals(decide(0.5, { ok = true, record = { percent = "abc" } }, true), "fail")
end

function TestSyncRules:test_gelezen_op_server_springt_niet()
    local fetched = { ok = true, record = { percent = 1 } }
    lu.assertEquals(SyncRules.decide(0.73, fetched, true), "none")
    lu.assertEquals(SyncRules.decide(0.73, fetched, false), "none")
    lu.assertTrue(SyncRules.isFinished(0.996))
    lu.assertFalse(SyncRules.isFinished(0.9))
    lu.assertFalse(SyncRules.isFinished(nil))
end

function TestSyncRules:test_gelezen_op_server_en_opnieuw_gelezen_schrijft_weg()
    local fetched = { ok = true, record = { percent = 1 } }
    lu.assertEquals(SyncRules.decide(0.75, fetched, true, true), "push")
    lu.assertEquals(SyncRules.decide(0.75, fetched, false, true), "push")
end

function TestSyncRules:test_ook_gelezen_als_beide_uit_zijn()
    lu.assertEquals(SyncRules.decide(1, { ok = true, record = { percent = 1 } }, true, true), "none")
end
