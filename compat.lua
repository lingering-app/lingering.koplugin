--[[--
Alle haken in de interne onderdelen van KOReader staan hier.

Elke haak loopt via try(): faalt hij, dan logt Lingering een waarschuwing en blijft
alleen dat onderdeel bij het standaardgedrag van KOReader. Zie docs/koreader-notes.md
voor waar elke haak in de KOReader-bron op leunt.
]]
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Compat = {}

-- Geeft true plus álle resultaten van fn terug, of false bij een fout.
local function try(name, fn, ...)
    local results = { pcall(fn, ...) }
    if not results[1] then
        logger.warn("Lingering: haak", name, "mislukt, standaardgedrag van KOReader blijft:", results[2])
        return false
    end
    return unpack(results, 1, table.maxn(results))
end
Compat.try = try

-- Standaardmaten uit KOReader's defaults.lua, als terugval als G_defaults ontbreekt.
local FALLBACK_ZONES = {
    DTAP_ZONE_MENU = { x = 0, y = 0, w = 1, h = 1/8 },
    DTAP_ZONE_MENU_EXT = { x = 1/4, y = 0, w = 2/4, h = 1/5 },
    DTAP_ZONE_CONFIG = { x = 0, y = 7/8, w = 1, h = 1/8 },
}

local function readZone(key)
    local ok, zone = pcall(function() return G_defaults:readSetting(key) end)
    if ok and type(zone) == "table" and zone.x and zone.y and zone.w and zone.h then
        return zone
    end
    logger.warn("Lingering: zone", key, "niet gevonden in G_defaults, gebruik standaardmaat")
    return FALLBACK_ZONES[key]
end

local function ratio(x, y, w, h)
    return { ratio_x = x, ratio_y = y, ratio_w = w, ratio_h = h }
end

-- Tikzones van KOReader en de gestures-plugin die onze tikzones voor moeten gaan.
local TAP_OVERRIDES = {
    "tap_link",
    "readerhighlight_tap",
    "readerhighlight_tap_select_mode",
    "tap_top_left_corner",
    "tap_top_right_corner",
    "tap_left_bottom_corner",
    "tap_right_bottom_corner",
    "readerfooter_tap",
    "readermenu_ext_tap",
    "readermenu_tap",
    "readerconfigmenu_ext_tap",
    "readerconfigmenu_tap",
    "tap_forward",
    "tap_backward",
}

-- Andere gebaren in de strook bovenaan (gestures-plugin) die niets mogen doen.
local TOP_OTHER_GESTURES = {
    double_tap = { "double_tap_top_left_corner", "double_tap_top_right_corner", "double_tap_left_side", "double_tap_right_side" },
    two_finger_tap = { "two_finger_tap_top_left_corner", "two_finger_tap_top_right_corner" },
}

local SWIPE_OVERRIDES = {
    "one_finger_swipe_top_edge_right",
    "one_finger_swipe_top_edge_left",
    "one_finger_swipe_left_edge_down",
    "one_finger_swipe_right_edge_down",
    "swipe_link",
    "readermenu_ext_swipe",
    "readermenu_swipe",
    "readerconfigmenu_ext_swipe",
    "readerconfigmenu_swipe",
    "rolling_swipe",
    "paging_swipe",
}

local PAN_OVERRIDES = {
    "one_finger_swipe_top_edge_right_pan",
    "one_finger_swipe_top_edge_left_pan",
    "one_finger_swipe_left_edge_down_pan",
    "one_finger_swipe_right_edge_down_pan",
    "readermenu_ext_pan",
    "readermenu_pan",
    "rolling_pan",
    "paging_pan",
}

local HOLD_OVERRIDES = {
    "readerhighlight_hold",
    "readerfooter_hold",
    "hold_top_left_corner",
    "hold_top_right_corner",
    "hold_bottom_left_corner",
    "hold_bottom_right_corner",
}

--[[--
Bouwt de tikzones van het leesscherm.

handlers: { backward = fn, close = fn, forward = fn, top = fn }
allow_hold: false blokkeert ingedrukt houden (woordenboek).
]]
function Compat.buildReaderZones(handlers, allow_hold)
    local menu = readZone("DTAP_ZONE_MENU")
    local menu_ext = readZone("DTAP_ZONE_MENU_EXT")
    local config = readZone("DTAP_ZONE_CONFIG")

    local top_y, top_h = menu.y, menu.h
    local mid_y = top_y + top_h
    local mid_h = config.y - mid_y
    local third = 1/3

    -- Zone-handlers vallen niet onder de HandlerSandbox van de pluginloader: zelf afvangen.
    local function safe(name, fn)
        if not fn then return nil end
        return function(ges)
            local ok, result = pcall(fn, ges)
            if not ok then
                logger.warn("Lingering: fout in tikzone", name, result)
                return true
            end
            return result
        end
    end
    handlers = {
        backward = safe("backward", handlers.backward),
        close = safe("close", handlers.close),
        forward = safe("forward", handlers.forward),
        top = safe("top", handlers.top),
    }

    local function swallow() return true end
    -- Vegen naar beneden opent het bovenmenu; dat vangen we af. De rest (bladeren) gaat door.
    local function swallowSouth(ges)
        if ges and ges.direction == "south" then
            return true
        end
    end

    local zones = {
        {
            id = "lingering_tap_backward",
            ges = "tap",
            screen_zone = ratio(0, mid_y, third, mid_h),
            overrides = TAP_OVERRIDES,
            handler = handlers.backward,
        },
        {
            id = "lingering_tap_close",
            ges = "tap",
            screen_zone = ratio(third, mid_y, third, mid_h),
            overrides = TAP_OVERRIDES,
            handler = handlers.close,
        },
        {
            id = "lingering_tap_forward",
            ges = "tap",
            screen_zone = ratio(2 * third, mid_y, 1 - 2 * third, mid_h),
            overrides = TAP_OVERRIDES,
            handler = handlers.forward,
        },
        {
            id = "lingering_top_tap",
            ges = "tap",
            screen_zone = ratio(menu.x, top_y, menu.w, top_h),
            overrides = TAP_OVERRIDES,
            handler = handlers.top or swallow,
        },
        {
            id = "lingering_top_swipe",
            ges = "swipe",
            screen_zone = ratio(menu.x, menu.y, menu.w, menu.h),
            overrides = SWIPE_OVERRIDES,
            handler = swallowSouth,
        },
        {
            id = "lingering_top_ext_swipe",
            ges = "swipe",
            screen_zone = ratio(menu_ext.x, menu_ext.y, menu_ext.w, menu_ext.h),
            overrides = SWIPE_OVERRIDES,
            handler = swallowSouth,
        },
        {
            id = "lingering_top_pan",
            ges = "pan",
            screen_zone = ratio(menu.x, menu.y, menu.w, menu.h),
            overrides = PAN_OVERRIDES,
            handler = swallowSouth,
        },
        {
            id = "lingering_top_ext_pan",
            ges = "pan",
            screen_zone = ratio(menu_ext.x, menu_ext.y, menu_ext.w, menu_ext.h),
            overrides = PAN_OVERRIDES,
            handler = swallowSouth,
        },
    }
    for ges, ids in pairs(TOP_OTHER_GESTURES) do
        table.insert(zones, {
            id = "lingering_top_" .. ges,
            ges = ges,
            screen_zone = ratio(menu.x, top_y, menu.w, top_h),
            overrides = ids,
            handler = swallow,
        })
    end
    if not allow_hold then
        table.insert(zones, {
            id = "lingering_block_hold",
            ges = "hold",
            screen_zone = ratio(0, 0, 1, 1),
            overrides = HOLD_OVERRIDES,
            handler = swallow,
        })
        table.insert(zones, {
            id = "lingering_block_hold_release",
            ges = "hold_release",
            screen_zone = ratio(0, 0, 1, 1),
            overrides = { "readerhighlight_hold_release" },
            handler = swallow,
        })
        table.insert(zones, {
            id = "lingering_block_hold_pan",
            ges = "hold_pan",
            screen_zone = ratio(0, 0, 1, 1),
            overrides = { "readerhighlight_hold_pan" },
            handler = swallow,
        })
    end
    return zones
end

--- Registreert de tikzones op ReaderUI. Faalt dat, dan worden ze weer verwijderd.
function Compat.registerReaderZones(ui, zones)
    local ok = try("registerTouchZones", ui.registerTouchZones, ui, zones)
    if not ok then
        try("unRegisterTouchZones", ui.unRegisterTouchZones, ui, zones)
    end
    return ok
end

--[[--
Zelfcontrole voor de log: staat elke zone van ons vóór de zones die hij moet overriden?
Leest InputContainer._ordered_touch_zones (intern). Faalt dit, dan alleen een waarschuwing.
]]
function Compat.verifyZoneOrder(ui, zones)
    return try("verifyZoneOrder", function()
        local position = {}
        for i, tzone in ipairs(ui._ordered_touch_zones) do
            position[tzone.def.id] = i
        end
        local problems = 0
        for _, zone in ipairs(zones) do
            local mine = position[zone.id]
            if not mine then
                problems = problems + 1
                logger.warn("Lingering: zone ontbreekt na registratie:", zone.id)
            else
                for _, other in ipairs(zone.overrides or {}) do
                    if position[other] and position[other] < mine then
                        problems = problems + 1
                        logger.warn("Lingering: zone", other, "staat vóór", zone.id)
                    end
                end
            end
        end
        if problems == 0 then
            logger.info("Lingering: zonevolgorde OK,", #zones, "zones vóór die van KOReader")
        end
    end)
end

--[[--
Vangnet: houdt het bovenmenu van de lezer dicht, ook als het via een gebaar,
een Dispatcher-actie of een toets wordt aangevraagd. Vervangt de handlers alleen op
deze ReaderMenu-instantie, niet op de klasse.
]]
function Compat.blockReaderMenu(ui)
    return try("blockReaderMenu", function()
        local menu = assert(ui.menu, "ui.menu ontbreekt")
        assert(type(menu.onShowMenu) == "function", "ReaderMenu:onShowMenu ontbreekt")
        local function blocked()
            logger.info("Lingering: bovenmenu geblokkeerd")
            return true
        end
        menu.onShowMenu = blocked
        menu.onTapShowMenu = blocked
        menu.onSwipeShowMenu = blocked
    end)
end

--- Sluit het boek en gaat naar de bestandsbeheerder (waar het homescreen overheen komt).
function Compat.closeBook(ui)
    if try("ReaderUI:onHome", ui.onHome, ui) then
        return true
    end
    return try("ReaderUI:onClose", function()
        local file = ui.document and ui.document.file
        ui:onClose()
        ui:showFileManager(file)
    end)
end

--- Bladert relatief, met het event dat ReaderPaging en ReaderRolling allebei afhandelen.
function Compat.turnPage(ui, direction)
    local Event = require("ui/event")
    local ok, handled = try("GotoViewRel", ui.handleEvent, ui, Event:new("GotoViewRel", direction))
    return ok and handled
end

--[[--
Instellingen van KOReader zelf die Lingering afdwingt (settings.reader.lua).
Sleutels gelezen in reader.lua (start_with) en frontend/ui/screensaver.lua.
]]
local ENFORCED_GLOBAL_SETTINGS = {
    -- Altijd starten in de bestandsbeheerder, waar het homescreen overheen komt.
    { key = "start_with", value = "filemanager" },
    -- Slaapscherm: omslag van het huidige boek, zonder tekst.
    { key = "screensaver_type", value = "cover" },
    { key = "screensaver_show_message", value = false },
    -- Het homescreen ligt over de bestandsbeheerder; ook daar de omslag tonen.
    { key = "screensaver_hide_cover_in_filemanager", value = false },
    -- Geen "Uitgeschakeld"/"Herstarten"-tekst over het slaapscherm.
    { key = "screensaver_hide_fallback_msg", value = true },
}

--- Maakt één keer een back-up van een instellingenbestand, vóór de eerste wijziging.
function Compat.backupOnce(path)
    local lfs = require("libs/libkoreader-lfs")
    local backup = path .. ".lingering-backup"
    if lfs.attributes(backup, "mode") or not lfs.attributes(path, "mode") then
        return true
    end
    local ffiUtil = require("ffi/util")
    local ok, err = pcall(ffiUtil.copyFile, path, backup)
    if ok and err == nil then
        logger.info("Lingering: back-up gemaakt:", backup)
        return true
    end
    logger.warn("Lingering: back-up mislukt, instellingen niet gewijzigd:", path, err)
    return false
end

function Compat.enforceGlobalSettings()
    return try("enforceGlobalSettings", function()
        local changes = {}
        for _, setting in ipairs(ENFORCED_GLOBAL_SETTINGS) do
            if G_reader_settings:readSetting(setting.key) ~= setting.value then
                table.insert(changes, setting)
            end
        end
        if #changes == 0 then return end
        if not Compat.backupOnce(G_reader_settings.file) then return end
        for _, setting in ipairs(changes) do
            logger.info("Lingering: KOReader-instelling", setting.key, "=", tostring(setting.value))
            G_reader_settings:saveSetting(setting.key, setting.value)
        end
        G_reader_settings:flush()
    end)
end

--- Stuurt een event naar de lezer; geeft true terug als een module het afhandelde.
local function sendEvent(name, ui, event_name)
    local Event = require("ui/event")
    local ok, handled = try(name, ui.handleEvent, ui, Event:new(event_name))
    return ok and handled and true or false
end

local function kosyncLoggedIn(kosync)
    return kosync and kosync.settings and kosync.settings.username and kosync.settings.userkey
end

--[[--
Sync-knop in het boek: tweezijdig, met terugmelding done(ok).
1. wifi aan zonder te vragen (en na afloop weer uit als hij uit stond);
2. voortgang ophalen (KOSyncClient:get_progress). Is die van een ander apparaat en nieuwer
   dan de laatste paginawissel hier (zoals KOSync:getProgress het bepaalt), dan springt
   het boek erheen via KOSync:syncToProgress;
3. anders de eigen voortgang wegschrijven (KOSyncClient:update_progress).
Gebruikt van de kosync-instantie (ui.kosync): settings, path, device_id,
last_page_turn_timestamp, pull_timestamp, getDocumentDigest, getMetadata,
getLastProgress, getLastPercent, syncToProgress.
]]
function Compat.syncNow(ui, done)
    local kosync = ui.kosync
    if not kosyncLoggedIn(kosync) then
        logger.warn("Lingering: synchroniseren niet mogelijk, kosync niet ingelogd of niet geladen")
        done(false)
        return
    end
    if not Compat.isWifiOn() then
        local finish = done
        done = function(ok)
            logger.info("Lingering: wifi weer uit na synchroniseren")
            Compat.disableWifi()
            finish(ok)
        end
    end
    -- KOSync:_onNetworkConnected haalt bij een nieuwe verbinding zelf ook voortgang op;
    -- via zijn eigen vertraging (pull_timestamp, 25 s) slaan we die over: wij doen het al.
    pcall(function() kosync.pull_timestamp = UIManager:getElapsedTimeSinceBoot() end)

    local started = Compat.turnOnWifiThen(function()
        local ok = try("syncNow", function()
            local Device = require("device")
            local KOSyncClient = require("KOSyncClient")
            local settings = kosync.settings
            local client = KOSyncClient:new{
                custom_url = settings.custom_server,
                service_spec = kosync.path .. "/api.json",
            }
            local digest = kosync:getDocumentDigest()

            local function push()
                client:update_progress(
                    settings.username,
                    settings.userkey,
                    digest,
                    kosync:getMetadata(),
                    kosync:getLastProgress(),
                    kosync:getLastPercent(),
                    settings.kosync_hostname or Device.model,
                    kosync.device_id,
                    function(success, status)
                        logger.info("Lingering: voortgang weggeschreven:", success and "ok" or ("fout " .. tostring(status)))
                        done(success and true or false)
                    end)
            end

            client:get_progress(settings.username, settings.userkey, digest, function(success, body)
                local jumped = false
                local cb_ok, err = pcall(function()
                    if not (success and type(body) == "table" and body.percentage and body.progress) then
                        return
                    end
                    if body.device == Device.model and body.device_id == kosync.device_id then
                        return -- laatste stand komt van dit apparaat
                    end
                    if body.progress == kosync:getLastProgress() then
                        return -- al gelijk
                    end
                    local server_newer
                    if body.timestamp then
                        server_newer = body.timestamp > (kosync.last_page_turn_timestamp or 0)
                    else
                        server_newer = body.percentage > kosync:getLastPercent()
                    end
                    if server_newer then
                        logger.info("Lingering: nieuwere voortgang van", tostring(body.device), "ingesteld")
                        kosync:syncToProgress(body.progress)
                        jumped = true
                    end
                end)
                if not cb_ok then
                    logger.warn("Lingering: voortgang verwerken mislukt:", err)
                end
                if jumped then
                    done(true)
                elseif not pcall(push) then
                    done(false)
                end
            end)
        end)
        if not ok then done(false) end
    end)
    if not started then done(false) end
end

--[[--
Geen wifi: automatisch ophalen stil overslaan. KOSync roept bij openen (onReaderReady) en
ontwaken (_onResume) getProgress(true, false) aan; met ensure_networking zou dat wifi
aanzetten. Zonder verbinding slaan we dat over; de sync-knop in het boek haalt het op.
Vervangt getProgress alleen op deze kosync-instantie.
]]
function Compat.guardKosyncNetworking(ui)
    return try("guardKosyncNetworking", function()
        local kosync = assert(ui.kosync, "kosync niet geladen")
        local getProgress = assert(kosync.getProgress, "KOSync:getProgress ontbreekt")
        kosync.getProgress = function(this, ensure_networking, interactive)
            if ensure_networking and not interactive and not Compat.isOnline() then
                logger.info("Lingering: geen verbinding, voortgang ophalen overgeslagen")
                return
            end
            return getProgress(this, ensure_networking, interactive)
        end
    end)
end

--- Staat het voorlicht aan? (BasePowerD:isFrontlightOn, frontend/device/generic/powerd.lua)
function Compat.isFrontlightOn()
    local Device = require("device")
    if not Device:hasFrontlight() then return false end
    local ok, on = try("isFrontlightOn", function()
        return Device:getPowerDevice():isFrontlightOn()
    end)
    return ok and on or false
end

--[[--
Het boek dat het laatst gelezen is, voor het homescreen. nil als er geen is.
Gebruikt ReadHistory.hist (frontend/readhistory.lua), BookList.getDocSettings
(frontend/ui/widget/booklist.lua) en FileManagerBookInfo:getDocProps/getCoverImage.
Geeft { file, title, authors, percent, cover } terug; cover is een BlitBuffer of nil.
]]
function Compat.currentBook(fm)
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
function Compat.bookStats(fm, file, percent)
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

        read_pages, read_time = tonumber(read_pages) or 0, tonumber(read_time) or 0
        if read_pages == 0 or read_time == 0 then return nil end
        local avg_time = read_time / read_pages
        local pages_left = math.max(0, pages - math.floor((percent or 0) * pages + 0.5))
        return {
            read_secs = read_time,
            left_secs = pages_left * avg_time,
        }
    end)
    return ok and stats or nil
end

--[[--
OPDS (plugins/opds.koplugin). Inloggegevens staan in <settings>/opds.lua, lijst "servers",
waar de OPDS-plugin ze zelf ook bewaart. Wachtwoorden worden nooit gelogd.
]]
local function sameUrl(a, b)
    return a and b and (a:gsub("/+$", "") == b:gsub("/+$", ""))
end

--- Gebruikersnaam en wachtwoord van de server met dit adres, of nil.
function Compat.opdsCredentials(opds_url)
    local ok, user, pass = try("opdsCredentials", function()
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local servers = LuaSettings:open(DataStorage:getSettingsDir() .. "/opds.lua"):readSetting("servers") or {}
        for _, server in ipairs(servers) do
            if sameUrl(server.url, opds_url) then
                return server.username, server.password
            end
        end
    end)
    if ok then return user, pass end
end

--[[--
Een "kaal" OPDSBrowser-object: de methoden van de OPDS-plugin zonder het scherm.
sync = true slaat in genItemTableFromCatalog het ophalen van zoek- en facetlinks over.
]]
function Compat.opdsClient(username, password)
    local ok, client = try("opdsClient", function()
        local OPDSBrowser = require("opdsbrowser")
        return setmetatable({
            root_catalog_username = username,
            root_catalog_password = password,
            sync = true,
        }, { __index = OPDSBrowser })
    end)
    return ok and client or nil
end

--[[--
Haalt één pagina van een catalogus op via OPDSBrowser:genItemTableFromURL
(parser van de plugin, OPDS 1 en 2). Geeft { items = {...}, next = url|nil } of nil.
Elk item: { title, author, url (map) | acquisitions (boek), thumbnail, image }.
]]
function Compat.opdsFetchPage(client, feed_url)
    local ok, page = try("opdsFetchPage", function()
        local item_table = client:genItemTableFromURL(feed_url)
        local items = {}
        for _, item in ipairs(item_table) do
            table.insert(items, item)
        end
        return { items = items, next = item_table.hrefs and item_table.hrefs.next }
    end)
    return ok and page or nil
end

--- Bestandstype van een acquisitie-link (OPDSBrowser.getFiletype), bijv. "epub".
function Compat.opdsFiletype(acquisition)
    local ok, filetype = try("opdsFiletype", function()
        return require("opdsbrowser").getFiletype(acquisition)
    end)
    return ok and filetype or nil
end

--- Downloadt een boek met OPDSBrowser:downloadFile (toont zelf een melding bij een fout).
function Compat.opdsDownload(client, local_path, remote_url, username, password)
    local ok, result = try("opdsDownload", client.downloadFile, client, local_path, remote_url, username, password)
    return ok and result == true
end

--- Thuismap van KOReader (filemanagerutil.getHomeFolder).
function Compat.homeFolder()
    local ok, dir = try("getHomeFolder", function()
        return require("apps/filemanager/filemanagerutil").getHomeFolder()
    end)
    return ok and dir or "."
end

--- Online? (NetworkMgr:isOnline)
function Compat.isOnline()
    local ok, online = try("isOnline", function()
        return require("ui/network/manager"):isOnline()
    end)
    return ok and online or false
end

--[[--
Controle van de OPDS-catalogus voor het inlogscherm: één GET met inloggegevens.
Bewust geen OPDSBrowser:fetchFeed, want die toont zelf een melding; hier willen we
zelf zeggen wat er misging. Geeft true of false, reden.
]]
function Compat.checkOpds(opds_url, username, password)
    local ok, success, reason = try("checkOpds", function()
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socket = require("socket")
        local socketutil = require("socketutil")
        local _ = require("gettext")
        local sink = {}
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
        local code = socket.skip(1, http.request{
            url = opds_url,
            method = "GET",
            headers = {
                ["Accept-Encoding"] = "identity",
                ["Accept"] = "application/opds+json, application/atom+xml;profile=opds-catalog, */*",
            },
            sink = ltn12.sink.table(sink),
            user = username,
            password = password,
        })
        socketutil:reset_timeout()
        if type(code) ~= "number" then
            return false, _("server niet bereikbaar") .. " (" .. tostring(code) .. ")"
        elseif code == 401 or code == 403 then
            return false, _("gebruikersnaam of wachtwoord onjuist")
        elseif code ~= 200 then
            return false, _("server antwoordt met code") .. " " .. code
        end
        local first = table.concat(sink):match("^%s*(.)")
        if first ~= "<" and first ~= "{" then
            return false, _("geen geldige catalogus")
        end
        return true
    end)
    if not ok then return false, "?" end
    return success, reason
end

--- Pad naar api.json van de kosync-plugin (naast KOSyncClient.lua).
local function kosyncServiceSpec()
    local client_file = package.searchpath("KOSyncClient", package.path)
    return assert(client_file, "KOSyncClient niet gevonden"):match("^(.*)/[^/]*$") .. "/api.json"
end

--[[--
Controle van de syncserver: KOSyncClient:authorize met userkey = md5(wachtwoord),
zoals KOSync:doLogin. Geeft true of false, reden.
]]
function Compat.checkKosync(sync_url, username, password)
    local ok, success, reason = try("checkKosync", function()
        local KOSyncClient = require("KOSyncClient")
        local md5 = require("ffi/sha2").md5
        local _ = require("gettext")
        local client = KOSyncClient:new{
            custom_url = sync_url,
            service_spec = kosyncServiceSpec(),
        }
        local call_ok, authorized, body = pcall(client.authorize, client, username, md5(password))
        if not call_ok then
            return false, _("fout bij verbinden")
        elseif authorized then
            return true
        elseif body == nil then
            return false, _("server niet bereikbaar")
        end
        return false, (type(body) == "table" and body.message) or _("gebruikersnaam of wachtwoord onjuist")
    end)
    if not ok then return false, "?" end
    return success, reason
end

--- De geladen plugin-klasse met deze naam (PluginLoader.enabled_plugins), of nil.
local function pluginClass(name)
    local PluginLoader = require("pluginloader")
    for _, plugin in ipairs(PluginLoader.enabled_plugins or {}) do
        if plugin.name == name then return plugin end
    end
end

--[[--
Schrijft de OPDS-catalogus met inloggegevens in <settings>/opds.lua (lijst "servers"):
een bestaande ingang met hetzelfde adres wordt bijgewerkt, anders komt er een bij.
Een al geladen OPDS-instantie in de bestandsbeheerder (fm.opds.servers) krijgt dezelfde
wijziging, zodat die bij een eigen flush niets terugzet.
]]
function Compat.writeOpdsAccount(opds_url, username, password, fm)
    return try("writeOpdsAccount", function()
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local file = DataStorage:getSettingsDir() .. "/opds.lua"
        assert(Compat.backupOnce(file), "back-up van opds.lua mislukt")

        local function apply(servers)
            for _, server in ipairs(servers) do
                if sameUrl(server.url, opds_url) then
                    server.username, server.password = username, password
                    return
                end
            end
            table.insert(servers, { title = "Lingering", url = opds_url, username = username, password = password })
        end

        local store = LuaSettings:open(file)
        local servers = store:readSetting("servers") or {}
        apply(servers)
        store:saveSetting("servers", servers)
        store:flush()
        if fm and fm.opds and type(fm.opds.servers) == "table" and fm.opds.servers ~= servers then
            apply(fm.opds.servers)
        end
        logger.info("Lingering: OPDS-catalogus ingesteld voor gebruiker", username)
    end)
end

--[[--
Schrijft de kosync-instellingen in <settings>/kosync.lua (sleutel "settings"):
custom_server, username, userkey = md5(wachtwoord), auto_sync aan,
sync_forward = SILENT (2), sync_backward = PROMPT (1) (SYNC_STRATEGY in kosync main.lua).
Gebruikt het gedeelde KOSync.settings_obj als kosync dat deze sessie al opende.
]]
function Compat.writeKosyncAccount(sync_url, username, password)
    return try("writeKosyncAccount", function()
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local md5 = require("ffi/sha2").md5
        local file = DataStorage:getSettingsDir() .. "/kosync.lua"
        assert(Compat.backupOnce(file), "back-up van kosync.lua mislukt")

        local class = pluginClass("kosync")
        local store = (class and class.settings_obj) or LuaSettings:open(file)
        local settings = store:readSetting("settings") or {}
        settings.custom_server = sync_url
        settings.username = username
        settings.userkey = md5(password)
        settings.auto_sync = true
        settings.sync_forward = 2
        settings.sync_backward = 1
        store:saveSetting("settings", settings)
        store:flush()
        logger.info("Lingering: kosync ingesteld voor gebruiker", username)
    end)
end

--[[--
Automatische sync van kosync blijft alleen aan als wifi zonder vragen aan mag
(KOSync:init zet auto_sync anders uit op apparaten met hasSeamlessWifiToggle, zoals Kobo).
]]
function Compat.ensureAutoWifi()
    return try("ensureAutoWifi", function()
        local Device = require("device")
        if Device:hasSeamlessWifiToggle() and G_reader_settings:readSetting("wifi_enable_action") ~= "turn_on" then
            if not Compat.backupOnce(G_reader_settings.file) then return end
            logger.info("Lingering: KOReader-instelling wifi_enable_action = turn_on")
            G_reader_settings:saveSetting("wifi_enable_action", "turn_on")
            G_reader_settings:flush()
        end
    end)
end

--[[--
Zet wifi aan zonder te vragen en voert fn uit zodra er verbinding is
(NetworkMgr:turnOnWifiAndWaitForConnection). Al online: fn meteen.
Geeft false als verbinden direct mislukt.
]]
function Compat.turnOnWifiThen(fn)
    local ok, started = try("turnOnWifiThen", function()
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isOnline() then
            fn()
            return true
        end
        return NetworkMgr:turnOnWifiAndWaitForConnection(fn) ~= false
    end)
    return ok and started
end

--[[--
Maakt van een MultiInputDialog een kale kaart: geen rand om het venster en geen titelbalk;
de invoervelden houden hun rand. Leunt op MultiInputDialog:init
(frontend/ui/widget/multiinputdialog.lua): dialog_frame (FrameContainer) met als eerste
element een VerticalGroup waarvan [1] de title_bar is. Faalt het, dan blijft het venster
zoals KOReader het maakt.
]]
function Compat.plainDialog(dialog, framed_button_id)
    return try("plainDialog", function()
        local Blitbuffer = require("ffi/blitbuffer")
        local Size = require("ui/size")
        local frame = assert(dialog.dialog_frame, "dialog_frame ontbreekt")
        local group = assert(frame[1], "inhoud ontbreekt")
        frame.bordersize = 0
        frame.radius = 0
        if group[1] == dialog.title_bar then
            table.remove(group, 1)
        end
        -- InputDialog maakt de knoppenrij met zero_sep = true: een scheidingslijn bovenaan
        -- (ButtonTable:addVerticalSeparator). Zonder kaart hangt die los: weg ermee.
        local buttons = dialog.button_table and dialog.button_table.container
        if buttons and buttons[1] and buttons[1].dimen and buttons[1].background
                and buttons[1].dimen.h == dialog.button_table.sep_width then
            table.remove(buttons, 1)
        end
        -- Eén knop met een eigen rand, zodat hij als knop herkenbaar is (Button.frame).
        if framed_button_id then
            local button = dialog.button_table:getButtonById(framed_button_id)
            if button and button.frame then
                button.frame.bordersize = Size.border.button
                button.frame.color = Blitbuffer.COLOR_BLACK
                button.frame.radius = Size.radius.button
            end
        end
        if buttons then buttons:resetLayout() end
        group:resetLayout()
    end)
end

--- Opent een boek (ReaderUI:showReader, de enige veilige manier volgens readerui.lua).
function Compat.openBook(file)
    return try("ReaderUI:showReader", function()
        require("apps/reader/readerui"):showReader(file)
    end)
end

--- Batterij in procenten, of nil (BasePowerD:getCapacity).
function Compat.batteryPercent()
    local Device = require("device")
    if not Device:hasBattery() then return nil end
    local ok, capacity = try("getCapacity", function()
        return Device:getPowerDevice():getCapacity()
    end)
    return ok and capacity or nil
end

--- Wifi-radio aan? (NetworkMgr:isWifiOn)
function Compat.isWifiOn()
    local ok, on = try("isWifiOn", function()
        return require("ui/network/manager"):isWifiOn()
    end)
    return ok and on or false
end

--- Verbonden met een netwerk? (NetworkMgr:isConnected; op Kobo ifHasAnAddress)
function Compat.isWifiConnected()
    local ok, connected = try("isConnected", function()
        return require("ui/network/manager"):isConnected()
    end)
    return ok and connected or false
end

--[[--
Wifi stil uit (NetworkMgr:disableWifi, zonder "Turning off Wi-Fi…"-melding).
interactive = true zet wifi_was_on op false, zodat wifi bij ontwaken niet terugkomt.
]]
function Compat.disableWifi()
    return try("disableWifi", function()
        require("ui/network/manager"):disableWifi(nil, true)
    end)
end

--- Wifi aan/uit (NetworkMgr:toggleWifiOn/toggleWifiOff). Alleen als het apparaat het kan.
function Compat.setWifi(on, callback)
    return try("toggleWifi", function()
        local NetworkMgr = require("ui/network/manager")
        if on then
            NetworkMgr:toggleWifiOn(callback, false, true)
        else
            NetworkMgr:toggleWifiOff(callback, true)
        end
    end)
end

--[[--
Opent het volledige menu van de bestandsbeheerder (noodluik), op het laatste tabblad (☰),
waar "Lingering UI uitschakelen" staat. Leest FileManagerMenu.tab_item_table (intern);
lukt dat niet, dan opent het menu op het laatst gebruikte tabblad.
]]
function Compat.showFileManagerMenu(fm)
    return try("FileManagerMenu:onShowMenu", function()
        local menu = assert(fm and fm.menu, "FileManager.menu ontbreekt")
        local ok_tab, last_tab = pcall(function()
            if menu.tab_item_table == nil then menu:setUpdateItemTable() end
            return #menu.tab_item_table
        end)
        menu:onShowMenu(ok_tab and last_tab > 0 and last_tab or nil)
    end)
end

return Compat
