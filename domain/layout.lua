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

--[[--
stackRows(heights, top_gap): zoals gridRows, maar voor rijen van verschillende hoogte
(bijv. een rij mappen en een rij boeken). Aansluitend vanaf y = 0; de marge bovenaan hoort
bij de eerste rij.
]]
function Layout.stackRows(heights, top_gap)
    local rows = {}
    local y = 0
    for i, h in ipairs(heights) do
        local top = y
        y = y + h + (i == 1 and (top_gap or 0) or 0)
        table.insert(rows, { top = top, bottom = y - 1 })
    end
    return rows
end

--[[--
pages(heights, available, top_gap, row_gap): rijen verdelen over pagina's (Mijn boeken).
Een pagina is top_gap, dan rijen met row_gap ertussen, en past binnen available. Een rij die
hoger is dan available krijgt een eigen pagina. Geeft { { first = 1, last = 3 }, ... };
zonder rijen één lege pagina { first = 1, last = 0 }.
]]
function Layout.pages(heights, available, top_gap, row_gap)
    local pages = {}
    local first, used = 1, top_gap or 0
    for i, h in ipairs(heights) do
        local needed = h + (i > first and (row_gap or 0) or 0)
        if i > first and used + needed > available then
            table.insert(pages, { first = first, last = i - 1 })
            first, used = i, (top_gap or 0) + h
        else
            used = used + needed
        end
    end
    table.insert(pages, { first = first, last = #heights })
    return pages
end

--[[--
fitRows(available, tile_h, row_gap, top_gap, min_fill): hoeveel rijen tegels van tile_h op een
pagina passen, en de tegelhoogte daarvoor. Blijft er onderaan minstens min_fill (standaard 0,4)
van een rij over, dan krimpen de tegels zodat er één rij bij past (geen half lege pagina).
Geeft rijen, hoogte.
]]
function Layout.fitRows(available, tile_h, row_gap, top_gap, min_fill)
    local space = available - (top_gap or 0) + row_gap
    local step = tile_h + row_gap
    local rows = math.max(1, math.floor(space / step))
    if space - rows * step >= (min_fill or 0.4) * step then
        rows = rows + 1
        return rows, math.floor(space / rows - row_gap)
    end
    return rows, tile_h
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
