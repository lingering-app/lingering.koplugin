--[[--
Business rules voor de catalogus (Mijn boeken):
- normalize(item, filetype_of): item van de OPDS-parser → map of boek, of nil;
- pickAcquisition(acquisitions, filetype_of): beste download-link, EPUB eerst;
- fileName(book): "<titel> - <auteur>.<ext>" (nog niet veilig gemaakt voor het bestandssysteem);
- findFolder(items, title): map met deze naam (hoofdletters en spaties maken niet uit), of nil.
filetype_of(acquisition) → "epub" | "pdf" | … | nil wordt door de aanroeper meegegeven.
Pure Lua: geen KOReader.
]]
local Catalog = {}

function Catalog.pickAcquisition(acquisitions, filetype_of)
    local fallback, fallback_type
    for _, acquisition in ipairs(acquisitions or {}) do
        if acquisition.href and acquisition.type ~= "borrow" then
            local filetype = filetype_of(acquisition)
            if filetype == "epub" then
                return acquisition, filetype
            elseif filetype and not fallback then
                fallback, fallback_type = acquisition, filetype
            end
        end
    end
    return fallback, fallback_type
end

function Catalog.normalize(item, filetype_of)
    if item.acquisitions and #item.acquisitions > 0 then
        local acquisition, filetype = Catalog.pickAcquisition(item.acquisitions, filetype_of)
        if not acquisition then return nil end
        return {
            kind = "book",
            title = item.title or "?",
            author = item.author,
            thumbnail = item.thumbnail or item.image,
            href = acquisition.href,
            filetype = filetype,
        }
    elseif item.url then
        return {
            kind = "folder",
            title = item.title or item.text or "?",
            url = item.url,
        }
    end
end

function Catalog.fileName(book)
    return book.title .. (book.author and (" - " .. book.author) or "") .. "." .. (book.filetype or "epub")
end

local function simplify(text)
    return (tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

function Catalog.findFolder(items, title)
    local wanted = simplify(title)
    if wanted == "" then return nil end
    for _, entry in ipairs(items or {}) do
        if entry.kind == "folder" and simplify(entry.title) == wanted then
            return entry
        end
    end
end

return Catalog
