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

--- Kiest de beste download-link: bij voorkeur EPUB, anders iets wat KOReader kan openen.
local function pickAcquisition(acquisitions)
    local fallback
    for _, acquisition in ipairs(acquisitions or {}) do
        if acquisition.href and acquisition.type ~= "borrow" then
            local filetype = Opds.filetype(acquisition)
            if filetype == "epub" then
                return acquisition, filetype
            elseif filetype and not fallback then
                fallback = { acquisition, filetype }
            end
        end
    end
    if fallback then return fallback[1], fallback[2] end
end

--- Zet een item van de OPDS-plugin om naar wat wij bewaren: een map of een boek.
local function normalize(item)
    if item.acquisitions and #item.acquisitions > 0 then
        local acquisition, filetype = pickAcquisition(item.acquisitions)
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

--- Pad waar dit boek staat of komt te staan.
function Library:bookPath(book)
    local dir = Books.homeFolder() .. "/Lingering"
    local name = book.title .. (book.author and (" - " .. book.author) or "") .. "." .. (book.filetype or "epub")
    return dir .. "/" .. util.getSafeFilename(name, dir), dir
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

--[[--
Haalt één omslag op naar de cache. Stil: een mislukte omslag geeft geen melding, het boek
toont dan het standaardicoon. Blokkeert kort (één verzoek met korte time-out).
]]
function Library:fetchCover(thumbnail_url)
    local username, password = self:credentials()
    local ok, success = pcall(function()
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socket = require("socket")
        local socketutil = require("socketutil")
        local path = self:coverPath(thumbnail_url)
        local part = path .. ".part"
        local file = assert(io.open(part, "wb"))
        socketutil:set_timeout(socketutil.DEFAULT_BLOCK_TIMEOUT, socketutil.DEFAULT_TOTAL_TIMEOUT)
        local code = socket.skip(1, http.request{
            url = thumbnail_url,
            headers = { ["Accept-Encoding"] = "identity" },
            sink = ltn12.sink.file(file),
            user = username,
            password = password,
        })
        socketutil:reset_timeout()
        if code == 200 and os.rename(part, path) then
            return true
        end
        os.remove(part)
        return false
    end)
    return ok and success
end

return Library
