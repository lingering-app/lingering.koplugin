--[[--
Boekgegevens: boeken die je aan het lezen bent, omslag, leesstatistieken, thuismap.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

-- Bestaande boeken uit ReadHistory.hist (frontend/readhistory.lua), recentste eerst. De
-- quickstart-handleiding telt niet (zoals in ReaderUI:getLastDirFile); herkend aan
-- <datadir>/help/quickstart-*.html, omdat QuickStart.quickstart_filename pas na
-- QuickStart:getQuickStart() bestaat.
local function historyFiles()
    local lfs = require("libs/libkoreader-lfs")
    local ReadHistory = require("readhistory")
    local DataStorage = require("datastorage")
    local help_dir = DataStorage:getDataDir() .. "/help/"
    local function isQuickStart(path)
        return path:sub(1, #help_dir) == help_dir and path:match("/quickstart%-[^/]*%.html$") ~= nil
    end
    local files = {}
    for _, entry in ipairs(ReadHistory.hist or {}) do
        if entry.file and not isQuickStart(entry.file)
                and lfs.attributes(entry.file, "mode") == "file" then
            table.insert(files, entry.file)
        end
    end
    return files
end

-- Gegevens van één boek: FileManagerBookInfo:getDocProps en de doc-settings
-- (BookList.getDocSettings: percent_finished, summary.status zoals BookList.getBookStatus).
local function bookInfo(fm, file)
    local BookList = require("ui/widget/booklist")
    local props = fm.bookinfo:getDocProps(file, nil, true) or {}
    local doc_settings = BookList.getDocSettings(file)
    local summary = doc_settings:readSetting("summary") or {}
    return {
        file = file,
        title = props.display_title or props.title or file:match("([^/]+)$"),
        authors = props.authors,
        percent = doc_settings:readSetting("percent_finished"),
        status = summary.status or "reading",
        md5 = doc_settings:readSetting("partial_md5_checksum"),
    }
end

-- Sleutels waaraan hetzelfde boek in een ander bestand te herkennen is: dezelfde inhoud
-- (partial_md5_checksum, ook de sleutel van kosync) of dezelfde titel en auteur (andere uitgave).
local function bookKeys(info)
    local keys = {}
    if info.md5 then table.insert(keys, "md5:" .. info.md5) end
    local title = (info.title or ""):lower():gsub("%s+", " ")
    if title ~= "" then
        table.insert(keys, "titel:" .. title .. "|" .. (info.authors or ""):lower():gsub("%s+", " "))
    end
    return keys
end

-- Omslag apart (FileManagerBookInfo:getCoverImage): faalt alleen die, dan zonder omslag.
local function withCover(fm, book)
    local cover_ok, cover = try("getCoverImage", fm.bookinfo.getCoverImage, fm.bookinfo, nil, book.file)
    book.cover = cover_ok and cover or nil
    return book
end

--[[--
Boeken voor het homescreen: wat je aan het lezen bent (status "reading" in KOReader,
dus niet "abandoned"/on hold of "complete"), recentste eerst, hooguit limit; hetzelfde
boek in meer bestanden één keer. Is er niets
aan het lezen, dan alleen het laatst geopende boek. Lege lijst als er geen boek is.
Elk boek: { file, title, authors, percent, status, cover }; cover is een BlitBuffer of nil.
]]
function M.readingBooks(fm, limit)
    local ok, books = try("readingBooks", function()
        local files = historyFiles()
        local books = {}
        -- Hetzelfde boek in meer bestanden (bijv. eerder ergens anders gedownload) telt één
        -- keer: de recentst gelezen versie, want de geschiedenis staat op volgorde.
        local seen = {}
        for _, file in ipairs(files) do
            local info = bookInfo(fm, file)
            local keys = bookKeys(info)
            local duplicate = false
            for _, key in ipairs(keys) do
                if seen[key] then duplicate = true end
                seen[key] = true
            end
            if info.status == "reading" and not duplicate then
                table.insert(books, info)
                if #books >= limit then break end
            end
        end
        if #books == 0 and files[1] then
            books[1] = bookInfo(fm, files[1])
        end
        return books
    end)
    if not ok or not books then return {} end
    for _, book in ipairs(books) do withCover(fm, book) end
    return books
end

--[[--
Boek op "uit" (complete) zetten, zoals de statusknoppen van KOReader
(filemanagerutil.genStatusButtonsRow: summary.status + saveSummary + BookList-cache).
]]
function M.markFinished(file)
    return try("markFinished", function()
        local BookList = require("ui/widget/booklist")
        local filemanagerutil = require("apps/filemanager/filemanagerutil")
        local doc_settings = BookList.getDocSettings(file)
        local summary = doc_settings:readSetting("summary") or {}
        summary.status = "complete"
        filemanagerutil.saveSummary(doc_settings, summary)
        BookList.setBookInfoCacheProperty(file, "status", "complete")
    end)
end

--[[--
KOReader-status van een bestand: "new" (nooit geopend), "reading", "abandoned" of "complete";
zoals BookList.getBookStatus, maar uit de doc-settings zelf (de cache kan oud zijn).
]]
function M.status(file)
    local ok, status = try("bookStatus", function()
        local BookList = require("ui/widget/booklist")
        if not BookList.hasBookBeenOpened(file) then return "new" end
        local summary = BookList.getDocSettings(file):readSetting("summary") or {}
        return summary.status or "reading"
    end)
    return ok and status or "new"
end

--[[--
Wat kosync nodig heeft om de stand van een (niet geopend) boek weg te schrijven:
{ digest = partial_md5_checksum, progress = last_xpointer (epub) of last_page (pdf) }, of nil.
Zoals KOSync:getDocumentDigest (binary) en KOSync:getLastProgress.
]]
function M.syncPosition(file)
    local ok, position = try("syncPosition", function()
        local doc_settings = require("ui/widget/booklist").getDocSettings(file)
        local digest = doc_settings:readSetting("partial_md5_checksum")
        local progress = doc_settings:readSetting("last_xpointer") or doc_settings:readSetting("last_page")
        if not (digest and progress) then return nil end
        return { digest = digest, progress = progress }
    end)
    return ok and position or nil
end

--[[--
Leesstatistieken van een boek uit de database van de statistics-plugin, alleen als die
plugin geladen is én aan staat (fm.statistics.settings.is_enabled). Anders nil.

Rekent zoals ReaderStatistics (plugins/statistics.koplugin/main.lua):
- gelezen = som per pagina van min(duur, max_sec)   (getPageTimeTotalStats, "Time spent reading")
- resterend = resterende pagina's × gemiddelde tijd per pagina   (getCurrentStat)
Het boek is niet open, dus de huidige pagina = percent_finished × book.pages.
Het boek wordt gevonden op md5 = partial_md5_checksum (zoals getIdBookDB).
]]
function M.stats(fm, file)
    local ok, stats = try("bookStats", function()
        local statistics = fm and fm.statistics
        if not (statistics and statistics.settings and statistics.settings.is_enabled) then
            return nil
        end
        local BookList = require("ui/widget/booklist")
        local DataStorage = require("datastorage")
        local SQ3 = require("lua-ljsqlite3/init")
        local lfs = require("libs/libkoreader-lfs")

        local md5 = BookList.getDocSettings(file):readSetting("partial_md5_checksum")
        local db = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        if not md5 or lfs.attributes(db, "mode") ~= "file" then return nil end

        local conn = SQ3.open(db)
        local stmt = conn:prepare("SELECT id, pages FROM book WHERE md5 = ? ORDER BY last_open DESC LIMIT 1;")
        local row = stmt:reset():bind(md5):step()
        stmt:close()
        if not row then
            conn:close()
            return nil
        end
        local id_book, pages = tonumber(row[1]), tonumber(row[2]) or 0
        local max_sec = tonumber(statistics.settings.max_sec) or 120
        local read_pages, read_time = conn:rowexec(string.format([[
            SELECT count(*), sum(durations)
            FROM (
                SELECT min(sum(duration), %d) AS durations
                FROM page_stat
                WHERE id_book = %d
                GROUP BY page
            );
        ]], max_sec, id_book))
        conn:close()

        -- Ruwe getallen; de berekening (gelezen/resterend) staat in domain/reading_time.lua.
        return {
            read_pages = tonumber(read_pages) or 0,
            read_time = tonumber(read_time) or 0,
            pages = pages,
        }
    end)
    return ok and stats or nil
end

--- Thuismap van KOReader (filemanagerutil.getHomeFolder).
function M.homeFolder()
    local ok, dir = try("getHomeFolder", function()
        return require("apps/filemanager/filemanagerutil").getHomeFolder()
    end)
    return ok and dir or "."
end



return M
