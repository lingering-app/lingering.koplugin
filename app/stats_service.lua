--[[--
Leestijd per dag delen tussen apparaten (stats-API naast kosync, zie domain/stats_sync.lua).
StatsService.days(fm) → { ["2026-10-14"] = seconden } voor het homescreen: per dag het hoogste
    van dit apparaat (statistics-plugin) en de laatst opgehaalde som van de server; nil als er
    niets is.
StatsService.refresh(fm, done) → versturen wat nog niet (zeker) op de server staat en de som
    ophalen; done(changed) met changed = true als de som van de server anders is.
    Hooguit eens per tien minuten, alleen met verbinding; een server zonder deze API (404) een
    dag niet. Mislukt er iets, dan blijft alles zoals het was (geen melding): de volgende keer
    gaan dezelfde totalen gewoon opnieuw.
Nog nergens aangeroepen: wanneer er gesynct wordt, is nog niet gekozen.
Bewaard in lingering.lua: lingering_stats_server (som per dag), lingering_stats_pushed (datum
van de laatste geslaagde verzending), lingering_stats_state (pogingen).
]]
local logger = require("logger")

local Books = require("lingering.koreader.books")
local Kosync = require("lingering.koreader.kosync")
local Network = require("lingering.koreader.network")
local Session = require("lingering.app.session")
local StatsSync = require("lingering.domain.stats_sync")

local StatsService = {}

function StatsService.days(fm)
    local merged = StatsSync.merge(Books.readingDays(fm), Session:read("lingering_stats_server"))
    return next(merged) and merged or nil
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

function StatsService.refresh(fm, done)
    local now = os.time()
    if not Network.isOnline() or not StatsSync.shouldTry(now, Session:read("lingering_stats_state")) then
        return done(false)
    end
    local today = os.date("%Y-%m-%d", now)
    local pending = StatsSync.pending(Books.readingDays(fm), Session:read("lingering_stats_pushed"))
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
    if changed then Session:save("lingering_stats_server", days) end
    done(changed)
end

--- Na inloggen met een (ander) account: niets van het vorige account bewaren.
function StatsService.reset()
    Session:save("lingering_stats_server", nil)
    Session:save("lingering_stats_pushed", nil)
    Session:save("lingering_stats_state", nil)
end

return StatsService
