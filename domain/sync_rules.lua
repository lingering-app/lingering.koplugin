--[[--
Business rule voor voortgangssync: "verder wint, nooit blind wegschrijven".

decide(local_percent, fetched, allow_jump, read_since_open) → actie
- fetched = { ok = bool, record = nil | { percent = getal|tekst, progress = ... } }
- "fail": ophalen mislukt of onleesbaar → níets wegschrijven
- "push": geen stand op de server, of dit apparaat is verder → eigen stand wegschrijven
- "jump": server verder en springen mag → naar de serverstand
- "none": gelijk, of server verder maar springen mag niet (bijv. bij sluiten)
Gelezen op de server (vanaf FINISHED) en dit apparaat eronder: nooit springen (de positie bij
"gelezen" is vaak niet het einde). Heb je sinds het openen verder gelezen (read_since_open),
dan lees je het boek opnieuw: "push", de server accepteert dan weer een gewone stand.
Anders "none": even kijken in een gelezen boek haalt "gelezen" niet weg.
Pure Lua: geen KOReader.
]]
local SyncRules = {
    -- Verschil in percentage (0..1) waaronder twee standen als gelijk gelden.
    EPSILON = 0.0005,
    -- Vanaf hier geldt een stand op de server als gelezen.
    FINISHED = 0.995,
}

function SyncRules.decide(local_percent, fetched, allow_jump, read_since_open)
    if not (fetched and fetched.ok) then
        return "fail"
    end
    local record = fetched.record
    if record == nil or record.percent == nil then
        return "push"
    end
    local server = tonumber(record.percent)
    if not server then
        return "fail"
    end
    local here = tonumber(local_percent) or 0
    if server >= SyncRules.FINISHED and server > here + SyncRules.EPSILON then
        return read_since_open and "push" or "none"
    end
    if server > here + SyncRules.EPSILON then
        return allow_jump and "jump" or "none"
    elseif server < here - SyncRules.EPSILON then
        return "push"
    end
    return "none"
end

return SyncRules
