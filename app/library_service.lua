--[[--
Mijn boeken, de gegevenskant: de OPDS-catalogus ophalen, cachen, omslagen en downloaden.

- Elke catalogus-pagina (op adres) wordt gecachet per gebruiker in
  <datadir>/cache/lingering/library.lua, zodat Mijn boeken ook zonder wifi werkt.
- Ophalen en verwerken gaat via de OPDS-plugin (compat.lua: opdsFetchPage, opdsDownload).
- Boeken komen in <thuismap>/Lingering/; staat het bestand er al, dan is het gedownload.
]]
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local util = require("util")

local Books = require("lingering.koreader.books")
local Opds = require("lingering.koreader.opds")
local Config = require("lingering.config")
local Catalog = require("lingering.domain.catalog")

local CACHE_DIR = DataStorage:getDataDir() .. "/cache/lingering"
local COVER_DIR = CACHE_DIR .. "/covers"
-- Veiligheidsgrens voor "volgende"-pagina's per catalogus.
local MAX_PAGES = 100

local Library = {}

function Library:open()
    if self.store then return end
    util.makePath(COVER_DIR)
    self.store = LuaSettings:open(CACHE_DIR .. "/library.lua")
end

function Library:credentials()
    return Opds.credentials(Config.opds_url)
end

function Library:rootUrl()
    return Config.opds_url
end

-- Cache per gebruiker, zodat een ander account niet de boeken van de vorige ziet.
function Library:userFeeds()
    self:open()
    local username = self:credentials() or ""
    local all = self.store:readSetting("feeds") or {}
    all[username] = all[username] or {}
    return all, all[username]
end

--- Gecachete pagina { items = {...}, fetched = tijd } of nil.
function Library:cached(feed_url)
    local _, feeds = self:userFeeds()
    return feeds[feed_url]
end

function Library:saveFeed(feed_url, items)
    local all, feeds = self:userFeeds()
    feeds[feed_url] = { items = items, fetched = os.time() }
    self.store:saveSetting("feeds", all)
    self.store:flush()
end

-- Catalogusregels (map/boek, beste download-link, bestandsnaam): domain/catalog.lua.
local function normalize(item)
    return Catalog.normalize(item, Opds.filetype)
end

--[[--
Haalt een catalogus opnieuw op, inclusief alle "volgende"-pagina's, en werkt de cache bij.
Gaat stap voor stap (één verzoek per tik van de UIManager), zodat de interface blijft
reageren. done(ok) wordt altijd precies één keer aangeroepen.
]]
function Library:sync(feed_url, done)
    local username, password = self:credentials()
    local client = username and Opds.client(username, password)
    if not client then
        logger.warn("Lingering: geen OPDS-account, synchroniseren overgeslagen")
        done(false)
        return
    end
    logger.info("Lingering: catalogus synchroniseren")

    local items, seen, pages = {}, {}, 0
    local next_url = feed_url
    local function step()
        local ok, err = pcall(function()
            seen[next_url] = true
            local page = Opds.fetchPage(client, next_url)
            if not page then
                done(false)
                return
            end
            for _, item in ipairs(page.items) do
                local entry = normalize(item)
                if entry then table.insert(items, entry) end
            end
            pages = pages + 1
            next_url = page.next
            if next_url and not seen[next_url] and pages < MAX_PAGES then
                UIManager:scheduleIn(0.05, step)
            else
                self:saveFeed(feed_url, items)
                logger.info("Lingering: catalogus gesynchroniseerd,", #items, "items,", pages, "pagina's")
                done(true)
            end
        end)
        if not ok then
            logger.warn("Lingering: synchroniseren mislukt:", err)
            done(false)
        end
    end
    step()
end

--[[--
Mappen voor het homescreen (config.collections), op naam in de hoofdpagina van de catalogus.
collectionUrl(title)            → adres van de map, of nil
collectionBooks(title)          → boeken in die map (uit de cache)
refreshCollections(titles, done)→ hoofdpagina en mappen opnieuw ophalen plus de eerste
                                  omslagen (sync-knop van het homescreen); done(changed)
]]
local COVERS_PER_COLLECTION = 3

--[[--
Gelezen op de website → gelezen op de e-reader (sync-knop van het homescreen): de OPDS-map
config.finished_collection ophalen (mislukt dat, dan de cache) en elk gedownload boek daaruit
dat in KOReader nog "aan het lezen" is op gelezen zetten.
done(changed): changed = true als er een boek op gelezen is gezet.
]]
function Library:syncFinished(done)
    local url = self:collectionUrl(Config.finished_collection)
    if not url then return done(false) end
    local function apply()
        local changed = false
        local feed = self:cached(url)
        for _, entry in ipairs(feed and feed.items or {}) do
            if entry.kind == "book" and self:isDownloaded(entry) then
                local path = self:bookPath(entry)
                if Books.status(path) == "reading" then
                    logger.info("Lingering: gelezen op de website:", entry.title)
                    Books.markFinished(path)
                    changed = true
                end
            end
        end
        done(changed)
    end
    self:sync(url, function() apply() end)
end

function Library:collectionUrl(title)
    local root = self:cached(self:rootUrl())
    local folder = Catalog.findFolder(root and root.items, title)
    return folder and folder.url
end

function Library:collectionBooks(title)
    local url = self:collectionUrl(title)
    local feed = url and self:cached(url)
    local books = {}
    for _, entry in ipairs(feed and feed.items or {}) do
        if entry.kind == "book" then table.insert(books, entry) end
    end
    return books
end

function Library:refreshCollections(titles, done)
    local changed = false
    local index = 0
    local wanted = {}
    -- Eerste omslagen van een map om op te halen (in de achtergrond, aan het eind).
    local function covers(title)
        local count = 0
        for _, entry in ipairs(self:collectionBooks(title)) do
            if entry.thumbnail then
                table.insert(wanted, entry.thumbnail)
                count = count + 1
                if count == COVERS_PER_COLLECTION then break end
            end
        end
    end
    local function finish()
        self:fetchCoversAsync(wanted, function(fetched)
            done(changed or fetched > 0)
        end)
    end
    local function step()
        index = index + 1
        local title = titles[index]
        if not title then return finish() end
        local url = self:collectionUrl(title)
        if not url then return UIManager:scheduleIn(0.05, step) end
        self:sync(url, function(ok)
            if ok then changed = true end
            covers(title)
            UIManager:scheduleIn(0.05, step)
        end)
    end
    self:sync(self:rootUrl(), function(ok)
        if ok then changed = true end
        step()
    end)
end

--- Pad waar dit boek staat of komt te staan.
function Library:bookPath(book)
    local dir = Books.homeFolder() .. "/Lingering"
    return dir .. "/" .. util.getSafeFilename(Catalog.fileName(book), dir), dir
end

function Library:isDownloaded(book)
    return lfs.attributes((self:bookPath(book)), "mode") == "file"
end

--[[--
Downloadt een boek via OPDSBrowser:downloadFile, eerst naar een .part-bestand, zodat een
afgebroken download nooit als "gedownload" telt. Blokkeert tot het klaar is.
]]
function Library:download(book)
    local username, password = self:credentials()
    local client = username and Opds.client(username, password)
    if not client then return false end
    local path, dir = self:bookPath(book)
    util.makePath(dir)
    local part = path .. ".part"
    logger.info("Lingering: boek downloaden naar", path)
    if Opds.download(client, part, book.href, username, password) and os.rename(part, path) then
        return true, path
    end
    os.remove(part)
    return false
end

function Library:coverPath(thumbnail_url)
    return COVER_DIR .. "/" .. md5(thumbnail_url)
end

function Library:hasCover(thumbnail_url)
    return thumbnail_url and lfs.attributes(self:coverPath(thumbnail_url), "mode") == "file"
end

--- Haalt één omslag op naar de cache (stil, kort; via koreader/opds.lua).
--[[--
Omslagen ophalen zonder het scherm te laten wachten: in een subproces
(Opds.fetchCoversInBackground). Lukt starten niet, dan alsnog één voor één. Omslagen die er
al zijn worden overgeslagen. done(aantal_nieuw, opgevraagd) volgt als alles klaar is.
]]
function Library:fetchCoversAsync(urls, done)
    local username, password = self:credentials()
    local jobs, seen = {}, {}
    for _, url in ipairs(urls or {}) do
        if url and not seen[url] and not self:hasCover(url) then
            seen[url] = true
            table.insert(jobs, { url = url, path = self:coverPath(url) })
        end
    end
    if #jobs == 0 or not username then return done(0, {}) end
    self:open() -- zorgt dat de omslagenmap bestaat
    local function count()
        local fetched = 0
        for _, job in ipairs(jobs) do
            if lfs.attributes(job.path, "mode") == "file" then fetched = fetched + 1 end
        end
        return fetched
    end
    local started = Opds.fetchCoversInBackground(jobs, username, password, function()
        done(count(), jobs)
    end)
    if not started then
        for _, job in ipairs(jobs) do Opds.fetchCover(job.url, job.path, username, password) end
        done(count(), jobs)
    end
end

function Library:fetchCover(thumbnail_url)
    local username, password = self:credentials()
    return Opds.fetchCover(thumbnail_url, self:coverPath(thumbnail_url), username, password)
end

return Library
