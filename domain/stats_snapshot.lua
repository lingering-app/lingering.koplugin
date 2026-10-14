--[[--
Momentopname van de leesstatistieken van dit apparaat voor de stats-API, zoals crosspoint-sync
hem verwacht (src/models/stats.ts, parseGlobalStats; CrossInk "stats_v5"). Elk apparaat stuurt
zijn eigen totalen over alle tijd; de server telt de apparaten bij elkaar op.

StatsSnapshot.build{ starts, durations, pages, completed, now } →
    { v, sessions, seconds, pages, completed, tod, dow, anchor_day, history_b64, streak }
    starts/durations: per gelezen pagina het begin (unix) en de duur (s, al afgekapt), op
    volgorde van begin; pages: aantal verschillende gelezen pagina's; completed: aantal
    uitgelezen boeken.
- tod: seconden per dagdeel, [ochtend 6–12, middag 12–18, avond 18–24, nacht 0–6] (lokale tijd;
  de grenzen legt de API niet vast).
- dow: seconden per weekdag, maandag t/m zondag.
- sessions: een nieuwe sessie na SESSION_GAP seconden niet lezen (legt de API niet vast).
- anchor_day: dagen sinds 2000-01-01 van de nieuwste leesdag (0 = nog niets gelezen).
- history_b64: base64 van HISTORY_BYTES bytes; bit n (byte n >> 3, bit 1 << (n & 7)) = gelezen
  op anchor_day − n, over HISTORY_DAYS dagen.
- streak: langste reeks aaneengesloten leesdagen ooit (ook ouder dan 730 dagen).
StatsSnapshot.dayNumber(date) → dagen sinds 2000-01-01 voor "YYYY-MM-DD".
StatsSnapshot.base64(bytes) → base64 van een lijst bytes (0..255).
Pure Lua: geen KOReader.
]]
local StatsSnapshot = {
    VERSION = 5,
    SESSION_GAP = 1800,
    HISTORY_BYTES = 92,
    HISTORY_DAYS = 730,
}

local function noonOf(date)
    local y, m, d = date:match("^(%d+)-(%d+)-(%d+)$")
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

local EPOCH_NOON = os.time{ year = 2000, month = 1, day = 1, hour = 12 }

function StatsSnapshot.dayNumber(date)
    return math.floor((noonOf(date) - EPOCH_NOON) / 86400 + 0.5)
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function StatsSnapshot.base64(bytes)
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local function char(shift) local k = math.floor(n / 2 ^ shift) % 64 return ALPHABET:sub(k + 1, k + 1) end
        table.insert(out, char(18) .. char(12) .. (b and char(6) or "=") .. (c and char(0) or "="))
    end
    return table.concat(out)
end

-- Dagdeel van een lokaal uur: 1 ochtend, 2 middag, 3 avond, 4 nacht.
local function partOfDay(hour)
    if hour >= 6 and hour < 12 then return 1 end
    if hour >= 12 and hour < 18 then return 2 end
    if hour >= 18 then return 3 end
    return 4
end

function StatsSnapshot.build(data)
    local starts, durations = data.starts or {}, data.durations or {}
    local tod, dow = { 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0 }
    local seconds, sessions = 0, 0
    local days = {}
    local last_end
    for i, start in ipairs(starts) do
        local duration = math.max(0, math.floor(durations[i] or 0))
        seconds = seconds + duration
        local t = os.date("*t", start)
        tod[partOfDay(t.hour)] = tod[partOfDay(t.hour)] + duration
        local weekday = (t.wday + 5) % 7 + 1 -- os.date: 1 = zondag; hier 1 = maandag
        dow[weekday] = dow[weekday] + duration
        if not last_end or start - last_end > StatsSnapshot.SESSION_GAP then sessions = sessions + 1 end
        last_end = math.max(last_end or 0, start + duration)
        if duration > 0 then days[os.date("%Y-%m-%d", start)] = true end
    end

    -- Leesdagen als dagnummers: nieuwste (anker), bitmap en langste reeks.
    local numbers = {}
    for date in pairs(days) do table.insert(numbers, StatsSnapshot.dayNumber(date)) end
    table.sort(numbers)
    local anchor = numbers[#numbers] or 0
    local bytes = {}
    for i = 1, StatsSnapshot.HISTORY_BYTES do bytes[i] = 0 end
    local streak, run, previous = 0, 0, nil
    for _, n in ipairs(numbers) do
        run = (previous and n == previous + 1) and run + 1 or 1
        streak = math.max(streak, run)
        previous = n
        local bit = anchor - n
        if bit < StatsSnapshot.HISTORY_DAYS then
            local index = math.floor(bit / 8) + 1
            local mask = 2 ^ (bit % 8)
            if math.floor(bytes[index] / mask) % 2 == 0 then bytes[index] = bytes[index] + mask end
        end
    end

    return {
        v = StatsSnapshot.VERSION,
        sessions = sessions,
        seconds = seconds,
        pages = math.max(0, math.floor(data.pages or 0)),
        completed = math.max(0, math.floor(data.completed or 0)),
        tod = tod,
        dow = dow,
        anchor_day = anchor,
        history_b64 = StatsSnapshot.base64(bytes),
        streak = streak,
    }
end

return StatsSnapshot
