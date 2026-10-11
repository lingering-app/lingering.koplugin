--[[--
Rekenregels voor de schermindeling. Pure Lua: geen KOReader.

readerZones(menu, menu_ext, config): tikzones van het leesscherm in ratio's (0..1).
  menu, menu_ext, config = { x, y, w, h } (KOReader's DTAP_ZONE_MENU, _MENU_EXT, _CONFIG).
  De derden (terug, sluiten, verder) liggen tussen de strook bovenaan en onderaan.

gridRows(count, columns, tile_h, top_gap): rijen voor ScrollableContainer.step_scroll_grid.
  Aansluitend vanaf y = 0 (anders crasht ScrollableContainer bij terugschuiven); de marge
  bovenaan hoort bij de eerste rij.
]]
local Layout = {}

local function rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

function Layout.readerZones(menu, menu_ext, config)
    local mid_y = menu.y + menu.h
    local mid_h = config.y - mid_y
    local third = 1 / 3
    return {
        top = rect(menu.x, menu.y, menu.w, menu.h),
        top_ext = rect(menu_ext.x, menu_ext.y, menu_ext.w, menu_ext.h),
        backward = rect(0, mid_y, third, mid_h),
        close = rect(third, mid_y, third, mid_h),
        forward = rect(2 * third, mid_y, 1 - 2 * third, mid_h),
    }
end

function Layout.gridRows(count, columns, tile_h, top_gap)
    local rows = {}
    local y = 0
    local row_count = math.ceil(count / columns)
    for i = 1, row_count do
        local top = y
        y = y + tile_h + (i == 1 and (top_gap or 0) or 0)
        table.insert(rows, { top = top, bottom = y - 1 })
    end
    return rows
end

return Layout
