--[[--
Leesstatistieken voor het homescreen uit leestijd per dag:
summary(days, now) → { today, week, streak, year }
    days: { ["2026-10-13"] = seconden, ... } (lokale datum)
    now: os.time() van nu
    today/week/year: seconden; week begint op maandag. streak: dagen op rij gelezen, tot en
    met vandaag (of tot en met gisteren als je vandaag nog niet gelezen hebt).
Pure Lua: geen KOReader.
]]
local ReadingStats = {}

-- Lokale datum ("2026-10-13") van offset dagen vóór now; via 12 uur 's middags, zodat
-- zomertijd geen dag overslaat.
local function dayKey(now, offset)
    local t = os.date("*t", now)
    return os.date("%Y-%m-%d", os.time{ year = t.year, month = t.month, day = t.day - offset, hour = 12 })
end

function ReadingStats.summary(days, now)
    days = days or {}
    local today = days[dayKey(now, 0)] or 0

    -- os.date wday: 1 = zondag; dagen sinds maandag.
    local since_monday = (os.date("*t", now).wday + 5) % 7
    local week = 0
    for i = 0, since_monday do week = week + (days[dayKey(now, i)] or 0) end

    local year_prefix = os.date("%Y-", now)
    local year = 0
    for key, secs in pairs(days) do
        if key:sub(1, #year_prefix) == year_prefix then year = year + secs end
    end

    local streak, i = 0, today > 0 and 0 or 1
    while (days[dayKey(now, i)] or 0) > 0 do
        streak = streak + 1
        i = i + 1
    end

    return { today = today, week = week, streak = streak, year = year }
end

return ReadingStats
