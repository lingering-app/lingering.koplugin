--[[--
Leestijd uit statistieken, zoals ReaderStatistics het berekent:
- gelezen = gecapte leestijd (som per pagina van min(duur, max_sec));
- resterend = resterende pagina's × gemiddelde tijd per pagina.
estimate{ read_pages, read_time, pages } en percent (0..1) → { read_secs, left_secs } of nil.
Pure Lua: geen KOReader.
]]
local ReadingTime = {}

function ReadingTime.estimate(raw, percent)
    if not raw then return nil end
    local read_pages, read_time = tonumber(raw.read_pages) or 0, tonumber(raw.read_time) or 0
    if read_pages == 0 or read_time == 0 then return nil end
    local pages = tonumber(raw.pages) or 0
    local avg_time = read_time / read_pages
    local pages_left = math.max(0, pages - math.floor((percent or 0) * pages + 0.5))
    return {
        read_secs = read_time,
        left_secs = pages_left * avg_time,
    }
end

--- Uren en minuten: geeft hours, minutes (afgerond op hele minuten).
function ReadingTime.split(secs)
    local minutes = math.floor((secs or 0) / 60 + 0.5)
    return math.floor(minutes / 60), minutes % 60
end

return ReadingTime
