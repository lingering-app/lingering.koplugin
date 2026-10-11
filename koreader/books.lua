--[[--
Boekgegevens: huidig boek, omslag, leesstatistieken, thuismap.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

--[[--
Het boek dat het laatst gelezen is, voor het homescreen. nil als er geen is.
Gebruikt ReadHistory.hist (frontend/readhistory.lua), BookList.getDocSettings
(frontend/ui/widget/booklist.lua) en FileManagerBookInfo:getDocProps/getCoverImage.
Geeft { file, title, authors, percent, cover } terug; cover is een BlitBuffer of nil.
]]
function M.currentBook(fm)
    local ok, book = try("currentBook", function()
        local lfs = require("libs/libkoreader-lfs")
        local ReadHistory = require("readhistory")
        local BookList = require("ui/widget/booklist")
        local DataStorage = require("datastorage")
        -- Recentste bestaande boek. De quickstart-handleiding telt niet (zoals in
        -- ReaderUI:getLastDirFile); herkend aan <datadir>/help/quickstart-*.html, omdat
        -- QuickStart.quickstart_filename pas na QuickStart:getQuickStart() bestaat.
        local help_dir = DataStorage:getDataDir() .. "/help/"
        local function isQuickStart(path)
            return path:sub(1, #help_dir) == help_dir and path:match("/quickstart%-[^/]*%.html$") ~= nil
        end
        local file
        for _, entry in ipairs(ReadHistory.hist or {}) do
            if entry.file and not isQuickStart(entry.file)
                    and lfs.attributes(entry.file, "mode") == "file" then
                file = entry.file
                break
            end
        end
        if not file then
            return nil
        end
        local props = fm.bookinfo:getDocProps(file, nil, true) or {}
        local percent = BookList.getDocSettings(file):readSetting("percent_finished")
        return {
            file = file,
            title = props.display_title or props.title or file:match("([^/]+)$"),
            authors = props.authors,
            percent = percent,
        }
    end)
    if not ok or not book then return nil end
    -- De omslag apart: faalt alleen die, dan toont het homescreen het boek zonder omslag.
    local cover_ok, cover = try("getCoverImage", fm.bookinfo.getCoverImage, fm.bookinfo, nil, book.file)
    book.cover = cover_ok and cover or nil
    return book
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

--- Voortgang (0..1) van een boek op dit apparaat, of nil als het nooit geopend is.
function M.percent(file)
    local ok, percent = try("books.percent", function()
        local BookList = require("ui/widget/booklist")
        if not BookList.hasBookBeenOpened(file) then return nil end
        return BookList.getDocSettings(file):readSetting("percent_finished")
    end)
    return ok and percent or nil
end

return M
