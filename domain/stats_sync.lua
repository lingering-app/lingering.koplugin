--[[--
Regels voor het delen van leestijd per dag tussen apparaten (de stats-API naast kosync, zoals
crosspoint-sync: PUT /api/v1/stats/global met "daily", GET /api/v1/stats/summary).
Elk apparaat stuurt steeds het totaal per dag (niet wat erbij kwam); de server bewaart per
apparaat en dag het hoogste getal en telt bij ophalen de apparaten op. Opnieuw of dubbel
versturen kan dus geen kwaad.

StatsSync.pending(days, since) → { { date, seconds }, ... }, nieuwste eerst
    days: { ["2026-10-14"] = seconden } van dit apparaat; since: datum van de laatste geslaagde
    verzending (die dag zelf gaat opnieuw mee, want hij kan sindsdien gegroeid zijn) of nil (alles).
StatsSync.chunks(list, size) → lijst van lijsten van hooguit size (de server neemt er 20 per keer)
StatsSync.merge(local_days, server_days) → per dag het hoogste van de twee
StatsSync.parseSummary(body) → { ["2026-10-14"] = seconden } uit het antwoord van de server, of nil
    als het geen bruikbaar antwoord is; rijen met een ongeldige datum of seconden vallen weg.
StatsSync.shouldTry(now, state) → true als er weer geprobeerd mag worden
    state: { last_try, blocked_until } (seconden)
StatsSync.afterTry(now, status) → nieuwe state na een poging (status: HTTP-code of nil)
Pure Lua: geen KOReader.
]]
local StatsSync = {
    CHUNK = 20,
    INTERVAL = 600,       -- hooguit eens per tien minuten
    BLOCKED = 86400,      -- server zonder deze API (404): een dag niet meer proberen
}

function StatsSync.pending(days, since)
    local list = {}
    for date, seconds in pairs(days or {}) do
        if (since == nil or date >= since) and (tonumber(seconds) or 0) > 0 then
            table.insert(list, { date = date, seconds = math.floor(seconds) })
        end
    end
    table.sort(list, function(a, b) return a.date > b.date end)
    return list
end

function StatsSync.chunks(list, size)
    local result, current = {}, nil
    for i, item in ipairs(list) do
        if (i - 1) % size == 0 then
            current = {}
            table.insert(result, current)
        end
        table.insert(current, item)
    end
    return result
end

function StatsSync.merge(local_days, server_days)
    local merged = {}
    for date, seconds in pairs(server_days or {}) do merged[date] = seconds end
    for date, seconds in pairs(local_days or {}) do
        if seconds > (merged[date] or 0) then merged[date] = seconds end
    end
    return merged
end

function StatsSync.parseSummary(body)
    if type(body) ~= "table" or type(body.daily) ~= "table" then return nil end
    local days = {}
    for _, row in ipairs(body.daily) do
        local seconds = type(row) == "table" and tonumber(row.seconds)
        if seconds and seconds >= 0 and type(row.date) == "string"
                and row.date:match("^%d%d%d%d%-%d%d%-%d%d$") then
            days[row.date] = seconds
        end
    end
    return days
end

function StatsSync.shouldTry(now, state)
    state = state or {}
    if state.blocked_until and now < state.blocked_until then return false end
    return not state.last_try or now - state.last_try >= StatsSync.INTERVAL
end

function StatsSync.afterTry(now, status)
    return {
        last_try = now,
        blocked_until = status == 404 and now + StatsSync.BLOCKED or nil,
    }
end

return StatsSync
