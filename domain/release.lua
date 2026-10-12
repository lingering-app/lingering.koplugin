--[[--
Regels voor zelf-update. Pure Lua: geen KOReader.

parse("v1.2.3") → { 1, 2, 3 } of nil (ook zonder "v"; alleen getallen)
compare(a, b)   → -1, 0, 1 (versie-tekst of tag)
latest(tags)    → de hoogste geldige tag uit een lijst namen, of nil
isNewer(tag, installed) → true als tag hoger is dan de geïnstalleerde versie
includes(pad)   → hoort dit pad (relatief in de zip, zonder bovenste map) bij de plugin?
                  Alle mappen behalve tests/, tools/ en docs/; geen verborgen bestanden;
                  bovenaan alleen _meta.lua, main.lua, config.lua en LICENSE.
]]
local Release = {}

function Release.parse(text)
    if type(text) ~= "string" then return nil end
    local major, minor, patch = text:match("^v?(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

function Release.compare(a, b)
    local va, vb = Release.parse(a), Release.parse(b)
    if not va or not vb then
        error("ongeldige versie: " .. tostring(va and b or a))
    end
    for i = 1, 3 do
        if va[i] ~= vb[i] then return va[i] < vb[i] and -1 or 1 end
    end
    return 0
end

function Release.latest(tags)
    local best
    for _, tag in ipairs(tags or {}) do
        if Release.parse(tag) and (not best or Release.compare(tag, best) > 0) then
            best = tag
        end
    end
    return best
end

function Release.isNewer(tag, installed)
    if not Release.parse(tag) then return false end
    if not Release.parse(installed) then return true end
    return Release.compare(tag, installed) > 0
end

local TOP_FILES = { ["_meta.lua"] = true, ["main.lua"] = true, ["config.lua"] = true, ["LICENSE"] = true }
-- Mappen die niet bij de plugin horen. Bewust een lijst van wat er NIET in gaat: een update
-- wordt geïnstalleerd door de oude versie, en een lijst van toegestane mappen zou nieuwe
-- mappen (zoals l10n/ in 0.0.8) weglaten.
local EXCLUDED_DIRS = { ["tests"] = true, ["tools"] = true, ["docs"] = true }

function Release.includes(path)
    if type(path) ~= "string" or path == "" then return false end
    if path:find("%.%.") or path:sub(1, 1) == "/" then return false end
    for part in path:gmatch("[^/]+") do
        if part:sub(1, 1) == "." then return false end
    end
    local top = path:match("^([^/]+)/")
    if not top then return TOP_FILES[path] == true end
    return not EXCLUDED_DIRS[top]
end

return Release
