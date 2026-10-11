--[[--
Leesscherm: tikzones (met overrides), bovenmenu blokkeren, bladeren, inhoudsopgave.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local logger = require("logger")
local try = require("lingering.koreader.try")
local Layout = require("lingering.domain.layout")

local M = {}

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
function M.buildZones(handlers, allow_hold)
    local menu = readZone("DTAP_ZONE_MENU")
    local menu_ext = readZone("DTAP_ZONE_MENU_EXT")
    local config = readZone("DTAP_ZONE_CONFIG")

    -- Geometrie (derden tussen de stroken) uit domain/layout.lua; hier alleen KOReader-zones.
    local geo = Layout.readerZones(menu, menu_ext, config)
    local function area(r) return ratio(r.x, r.y, r.w, r.h) end

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
            screen_zone = area(geo.backward),
            overrides = TAP_OVERRIDES,
            handler = handlers.backward,
        },
        {
            id = "lingering_tap_close",
            ges = "tap",
            screen_zone = area(geo.close),
            overrides = TAP_OVERRIDES,
            handler = handlers.close,
        },
        {
            id = "lingering_tap_forward",
            ges = "tap",
            screen_zone = area(geo.forward),
            overrides = TAP_OVERRIDES,
            handler = handlers.forward,
        },
        {
            id = "lingering_top_tap",
            ges = "tap",
            screen_zone = area(geo.top),
            overrides = TAP_OVERRIDES,
            handler = handlers.top or swallow,
        },
        {
            id = "lingering_top_swipe",
            ges = "swipe",
            screen_zone = area(geo.top),
            overrides = SWIPE_OVERRIDES,
            handler = swallowSouth,
        },
        {
            id = "lingering_top_ext_swipe",
            ges = "swipe",
            screen_zone = area(geo.top_ext),
            overrides = SWIPE_OVERRIDES,
            handler = swallowSouth,
        },
        {
            id = "lingering_top_pan",
            ges = "pan",
            screen_zone = area(geo.top),
            overrides = PAN_OVERRIDES,
            handler = swallowSouth,
        },
        {
            id = "lingering_top_ext_pan",
            ges = "pan",
            screen_zone = area(geo.top_ext),
            overrides = PAN_OVERRIDES,
            handler = swallowSouth,
        },
    }
    for ges, ids in pairs(TOP_OTHER_GESTURES) do
        table.insert(zones, {
            id = "lingering_top_" .. ges,
            ges = ges,
            screen_zone = area(geo.top),
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
function M.registerZones(ui, zones)
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
function M.verifyZoneOrder(ui, zones)
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
function M.blockMenu(ui)
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

--- Bladert relatief, met het event dat ReaderPaging en ReaderRolling allebei afhandelen.
function M.turnPage(ui, direction)
    local Event = require("ui/event")
    local ok, handled = try("GotoViewRel", ui.handleEvent, ui, Event:new("GotoViewRel", direction))
    return ok and handled
end

--- Inhoudsopgave van het boek (event ShowToc, ReaderToc:onShowToc; Dispatcher-actie "toc").
function M.showToc(ui)
    local Event = require("ui/event")
    return try("ShowToc", ui.handleEvent, ui, Event:new("ShowToc"))
end

return M
