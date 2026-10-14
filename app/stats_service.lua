--[[--
Leestijd per dag delen tussen apparaten (stats-API naast kosync, zie domain/stats_sync.lua).
StatsService.days(fm) → { ["2026-10-14"] = seconden } voor het homescreen: per dag de laatst
    opgehaalde som van de server, aangevuld met wat dit apparaat sindsdien las
    (StatsSync.combine); nil als er niets is.
StatsService.refresh(fm, done, opts) → versturen wat nog niet (zeker) op de server staat en de som
    ophalen; done(changed) met changed = true als de som van de server anders is.
    Alleen met verbinding. Automatisch (opts.manual niet gezet): hooguit eens per tien minuten,
    en een server zonder deze API (404) een dag niet; met opts.manual (sync-knop) altijd. Mislukt er iets, dan blijft alles zoals het was (geen melding): de volgende keer
    gaan dezelfde totalen gewoon opnieuw.
Aangeroepen door de sync-knop van Mijn boeken (ui/libraryscreen.lua), met opts.manual.
Bewaard in lingering.lua: lingering_stats_server (som per dag), lingering_stats_local_at_sync
(eigen leestijd per dag bij die sync), lingering_stats_pushed (datum van de laatste geslaagde
verzending), lingering_stats_state (pogingen).
]]
local logger = require("logger")

local Books = require("lingering.koreader.books")
local Kosync = require("lingering.koreader.kosync")
local Network = require("lingering.koreader.network")
local Session = require("lingering.app.session")
local StatsSync = require("lingering.domain.stats_sync")

local StatsService = {}

function StatsService.days(fm)
    local days = StatsSync.combine(Books.readingDays(fm), Session:read("lingering_stats_server"),
        Session:read("lingering_stats_local_at_sync"))
    return next(days) and days or nil
end

local function sameDays(a, b)
    for date, seconds in pairs(a or {}) do
        if (b or {})[date] ~= seconds then return false end
    end
    for date in pairs(b or {}) do
        if (a or {})[date] == nil then return false end
    end
    return true
end

local function ok(code) return code and code >= 200 and code < 300 end

function StatsService.refresh(fm, done, opts)
    local now = os.time()
    local manual = opts and opts.manual
    if not Network.isOnline()
            or (not manual and not StatsSync.shouldTry(now, Session:read("lingering_stats_state"))) then
        return done(false)
    end
    local today = os.date("%Y-%m-%d", now)
    -- Eén momentopname: wat nu verstuurd wordt, is het eigen deel in de som die daarna komt.
    local local_days = Books.readingDays(fm) or {}
    local pending = StatsSync.pending(local_days, Session:read("lingering_stats_pushed"))
    for _, chunk in ipairs(StatsSync.chunks(pending, StatsSync.CHUNK)) do
        local code = Kosync.pushStats(chunk)
        if not ok(code) then
            logger.info("Lingering: leestijd versturen mislukt, status", tostring(code))
            Session:save("lingering_stats_state", StatsSync.afterTry(now, code))
            return done(false)
        end
    end
    Session:save("lingering_stats_pushed", today)

    local code, body = Kosync.fetchStats()
    local days = code == 200 and StatsSync.parseSummary(body) or nil
    Session:save("lingering_stats_state", StatsSync.afterTry(now, code))
    if code ~= 200 or not days then
        logger.info("Lingering: leestijd ophalen mislukt, status", tostring(code))
        return done(false)
    end
    local changed = not sameDays(days, Session:read("lingering_stats_server"))
        or not sameDays(local_days, Session:read("lingering_stats_local_at_sync"))
    if changed then
        Session:save("lingering_stats_server", days)
        Session:save("lingering_stats_local_at_sync", local_days)
    end
    done(changed)
end

--- Na inloggen met een (ander) account: niets van het vorige account bewaren.
function StatsService.reset()
    Session:save("lingering_stats_server", nil)
    Session:save("lingering_stats_local_at_sync", nil)
    Session:save("lingering_stats_pushed", nil)
    Session:save("lingering_stats_state", nil)
end

return StatsService
