--[[--
Voortgangssync: de afloop en het beleid. Beslissing in domain/sync_rules.lua, KOReader-
aanroepen in koreader/kosync.lua en koreader/network.lua.

- reconcile(kosync, opts, done): momentopname → ophalen → besluiten → springen/wegschrijven.
- syncNow(ui, done): sync-knop; wifi aan zonder te vragen, daarna weer uit als hij uit stond.
- markFinished(file, done): boek op uit en, met verbinding, 100% naar de server.
- policy: wanneer kosync automatisch synchroniseert (zie koreader/kosync.lua installRules):
  alleen met verbinding, nooit wifi aanzetten; bij openen één nieuwe poging na 3 s.
]]
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Books = require("lingering.koreader.books")
local Kosync = require("lingering.koreader.kosync")
local Network = require("lingering.koreader.network")
local SyncRules = require("lingering.domain.sync_rules")

-- Recent al gesynchroniseerd (sync-knop, openen)? Dan niet nog eens automatisch.
local DEBOUNCE_SECONDS = 15
local RETRY_SECONDS = 3

local SyncService = {}

function SyncService.reconcile(kosync, opts, done)
    local finished = false
    local function finish(ok)
        if finished then return end
        finished = true
        if done then done(ok) end
    end
    local session = Kosync.session(kosync)
    if not session then
        logger.warn("Lingering: voortgang niet gesynchroniseerd, kosync niet ingelogd")
        finish(false)
        return
    end
    Kosync.markActivity(kosync)
    local ok, err = pcall(function()
        -- Momentopname nu: bij sluiten is het document weg als het antwoord binnenkomt.
        local snap = session:snapshot()
        session:fetch(snap, function(fetched_ok, record)
            local action = SyncRules.decide(snap.percent, { ok = fetched_ok, record = record }, opts.jump)
            logger.info("Lingering: voortgang", action, "(server", tostring(record and record.percent), "hier", snap.percent .. ")")
            if action == "jump" then
                local jumped = pcall(session.jump, session, record.progress)
                finish(jumped)
            elseif action == "push" then
                local started = pcall(session.store, session, snap, function(stored)
                    logger.info("Lingering: voortgang weggeschreven:", stored and "ok" or "mislukt")
                    finish(stored)
                end)
                if not started then finish(false) end
            else
                finish(action ~= "fail")
            end
        end)
    end)
    if not ok then
        logger.warn("Lingering: voortgang synchroniseren mislukt:", err)
        finish(false)
    end
end

function SyncService.syncNow(ui, done)
    local kosync = ui.kosync
    if not Kosync.session(kosync) then
        logger.warn("Lingering: synchroniseren niet mogelijk, kosync niet ingelogd of niet geladen")
        done(false)
        return
    end
    local wifi_was_off = not Network.isWifiOn()
    local reported = false
    local function finish(ok)
        if reported then return end
        reported = true
        -- Eerst melden (het icoon stopt), daarna pas wifi uit: dat blokkeert op een Kobo even.
        done(ok)
        if wifi_was_off then
            UIManager:scheduleIn(0.5, function()
                logger.info("Lingering: wifi weer uit na synchroniseren")
                Network.disableWifi()
            end)
        end
    end
    -- Ook vóór de verbinding er is: kosync's pull bij NetworkConnected mag niet tegelijk.
    Kosync.markActivity(kosync)
    local started = Network.turnOnWifiThen(function()
        SyncService.reconcile(kosync, { jump = true }, finish)
    end)
    if not started then finish(false) end
end

--[[--
Boek als gelezen markeren (menu "…" op het homescreen): in KOReader op "uit" (verdwijnt uit
"aan het lezen") en, met verbinding, 100% naar de syncserver. 100% is nooit achteruit, dus
dit past bij "verder wint". Zonder verbinding alleen lokaal; nooit wifi aanzetten.
done() volgt als het klaar is.
]]
function SyncService.markFinished(file, done)
    Books.markFinished(file)
    local position = Books.syncPosition(file)
    if position and Network.isOnline() then
        Kosync.storeFinished(position, function(ok)
            logger.info("Lingering: gelezen naar de server:", ok and "ok" or "mislukt")
            if done then done() end
        end)
    else
        logger.info("Lingering: gelezen, alleen lokaal (geen verbinding of geen stand)")
        if done then done() end
    end
end

SyncService.policy = {}

-- Openen, ontwaken, nieuwe verbinding: alleen met verbinding; springen mag.
function SyncService.policy.pull(kosync)
    if not Network.isOnline() then
        logger.info("Lingering: geen verbinding, voortgang ophalen overgeslagen")
        return
    end
    if Kosync.secondsSinceActivity(kosync) < DEBOUNCE_SECONDS then return end
    SyncService.reconcile(kosync, { jump = true }, function(ok)
        if ok then return end
        -- Eén nieuwe poging (bijv. net na het openen, netwerk nog niet klaar).
        UIManager:scheduleIn(RETRY_SECONDS, function()
            if Network.isOnline() then SyncService.reconcile(kosync, { jump = true }) end
        end)
    end)
end

-- Slaapstand en tussentijds: alleen met verbinding, nooit wifi aanzetten; niet springen.
function SyncService.policy.push(kosync, on_suspend)
    if not Network.isOnline() then
        logger.info("Lingering: geen verbinding, voortgang wegschrijven overgeslagen")
        return
    end
    SyncService.reconcile(kosync, { jump = false }, function()
        if on_suspend then Network.disableWifi() end
    end)
end

-- Sluiten: alleen met verbinding (geen blinde wachtrij); niet springen.
function SyncService.policy.close(kosync)
    if Network.isOnline() then
        SyncService.reconcile(kosync, { jump = false })
    else
        logger.info("Lingering: offline gesloten, voortgang volgt bij de volgende sync")
    end
end

return SyncService
