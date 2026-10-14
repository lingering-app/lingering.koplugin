--[[--
Zoeken in de opgeslagen catalogus (Mijn boeken), zonder server:
Search.books(feeds, query) → boeken waarvan titel of auteur alle woorden van query bevat,
    op titel gesorteerd (getallen als getal: "Deel 2" vóór "Deel 10"); elk boek één keer (zelfde download-link, of zelfde titel en auteur).
    feeds: lijst van lijsten met items (kind = "book" | "folder"), bijv. alle opgeslagen mappen.
Hoofdletters en accenten maken niet uit ("emile" vindt "Émile").
Search.normalize(text) → kleine letters zonder accenten (voor vergelijken).
Pure Lua: geen KOReader.
]]
local Search = {}

-- Veelvoorkomende letters met accent (UTF-8) → zonder.
local FOLD = {
    ["à"] = "a", ["á"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["å"] = "a",
    ["è"] = "e", ["é"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["ì"] = "i", ["í"] = "i", ["î"] = "i", ["ï"] = "i",
    ["ò"] = "o", ["ó"] = "o", ["ô"] = "o", ["ö"] = "o", ["õ"] = "o", ["ø"] = "o",
    ["ù"] = "u", ["ú"] = "u", ["û"] = "u", ["ü"] = "u",
    ["ý"] = "y", ["ÿ"] = "y", ["ç"] = "c", ["ñ"] = "n",
    ["À"] = "a", ["Á"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Ã"] = "a", ["Å"] = "a",
    ["È"] = "e", ["É"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["Ì"] = "i", ["Í"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["Ò"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Ö"] = "o", ["Õ"] = "o", ["Ø"] = "o",
    ["Ù"] = "u", ["Ú"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["Ý"] = "y", ["Ç"] = "c", ["Ñ"] = "n",
}

function Search.normalize(text)
    text = tostring(text or "")
    text = text:gsub("[\xC3][\x80-\xBF]", function(char) return FOLD[char] end)
    return text:lower()
end

-- Sorteersleutel: genormaliseerd, getallen met voorloopnullen (natuurlijke volgorde).
local function sortKey(title)
    return (Search.normalize(title):gsub("%d+", function(digits)
        return string.rep("0", math.max(0, 12 - #digits)) .. digits
    end))
end

local function words(query)
    local list = {}
    for word in Search.normalize(query):gmatch("%S+") do table.insert(list, word) end
    return list
end

function Search.books(feeds, query)
    local wanted = words(query)
    if #wanted == 0 then return {} end
    local found, seen = {}, {}
    for _, items in ipairs(feeds or {}) do
        for _, item in ipairs(items or {}) do
            if item.kind == "book" then
                local key = item.href or ((item.title or "") .. "\0" .. (item.author or ""))
                if not seen[key] then
                    local haystack = Search.normalize((item.title or "") .. " " .. (item.author or ""))
                    local match = true
                    for _, word in ipairs(wanted) do
                        if not haystack:find(word, 1, true) then
                            match = false
                            break
                        end
                    end
                    if match then
                        seen[key] = true
                        table.insert(found, item)
                    end
                end
            end
        end
    end
    local keys = {}
    for _, item in ipairs(found) do keys[item] = sortKey(item.title) end
    table.sort(found, function(a, b) return keys[a] < keys[b] end)
    return found
end

return Search
