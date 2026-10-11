--[[--
Alle haken in de interne onderdelen van KOReader staan hier.

Elke haak loopt via try(): faalt hij, dan logt Lingering een waarschuwing en blijft
alleen dat onderdeel bij het standaardgedrag van KOReader. Zie docs/koreader-notes.md
voor waar elke haak in de KOReader-bron op leunt.
]]
local logger = require("logger")

local Compat = {}

local function try(name, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        logger.warn("Lingering: haak", name, "mislukt, standaardgedrag van KOReader blijft:", result)
        return false
    end
    return true, result
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

--[[--
Voortgang nu wegschrijven, met terugmelding done(ok).
Gebruikt de kosync-instantie (ui.kosync) voor instellingen en document-gegevens en de
KOSyncClient van kosync voor het verzoek (zoals KOSync:updateProgress, maar met callback).
Wifi gaat zo nodig aan via NetworkMgr:runWhenOnline.
]]
function Compat.syncNow(ui, done)
    local kosync = ui.kosync
    if not (kosync and kosync.settings and kosync.settings.username and kosync.settings.userkey) then
        logger.warn("Lingering: synchroniseren niet mogelijk, kosync niet ingelogd of niet geladen")
        done(false)
        return
    end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local ok = try("syncNow", function()
            local Device = require("device")
            local KOSyncClient = require("KOSyncClient")
            local settings = kosync.settings
            local client = KOSyncClient:new{
                custom_url = settings.custom_server,
                service_spec = kosync.path .. "/api.json",
            }
            client:update_progress(
                settings.username,
                settings.userkey,
                kosync:getDocumentDigest(),
                kosync:getMetadata(),
                kosync:getLastProgress(),
                kosync:getLastPercent(),
                settings.kosync_hostname or Device.model,
                kosync.device_id,
                function(success, status)
                    logger.info("Lingering: voortgang weggeschreven:", success and "ok" or ("fout " .. tostring(status)))
                    done(success and true or false)
                end)
        end)
        if not ok then done(false) end
    end)
end

--- Licht aan/uit via DeviceListener:onToggleFrontlight (event ToggleFrontlight).
function Compat.toggleFrontlight(ui)
    return sendEvent("ToggleFrontlight", ui, "ToggleFrontlight")
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
