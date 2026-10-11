--[[--
Business rule voor voortgangssync: "verder wint, nooit blind wegschrijven".

decide(local_percent, fetched, allow_jump) → actie
- fetched = { ok = bool, record = nil | { percent = getal|tekst, progress = ... } }
- "fail": ophalen mislukt of onleesbaar → níets wegschrijven
- "push": geen stand op de server, of dit apparaat is verder → eigen stand wegschrijven
- "jump": server verder en springen mag → naar de serverstand
- "none": gelijk, of server verder maar springen mag niet (bijv. bij sluiten)
Pure Lua: geen KOReader.
]]
local SyncRules = {
    -- Verschil in percentage (0..1) waaronder twee standen als gelijk gelden.
    EPSILON = 0.0005,
}

function SyncRules.decide(local_percent, fetched, allow_jump)
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
    if server > here + SyncRules.EPSILON then
        return allow_jump and "jump" or "none"
    elseif server < here - SyncRules.EPSILON then
        return "push"
    end
    return "none"
end

return SyncRules
