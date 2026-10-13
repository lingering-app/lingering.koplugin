--[[--
Rastersysteem voor homescreen en Mijn boeken: altijd dezelfde marge aan de rand van het
scherm en dezelfde tussenruimte tussen kolommen; per rij 1, 2 of 4 kolommen. Twee kolommen
zijn daardoor precies zo breed als twee 4-kolommen plus de tussenruimte ertussen, zodat
blokken in verschillende rijen op elkaar aansluiten.

Grid.columnWidth(screen_w, columns) → breedte van één kolom
Grid.row(screen_w, columns, cells) → HorizontalGroup met marges en tussenruimtes
    cells: widgets van columnWidth breed (minder dan columns mag: de rest blijft leeg).
    screen_w: de breedte voor het raster (in Mijn boeken met schuifbalk: de breedte ernaast).
Grid.ROW_GAP: verticale ruimte tussen rijen.
]]
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Size = require("ui/size")

local Grid = {
    MARGIN = Size.padding.large * 2,
    GUTTER = Size.padding.large * 2,
    ROW_GAP = Size.padding.large * 3,
}

function Grid.columnWidth(screen_w, columns)
    return math.floor((screen_w - 2 * Grid.MARGIN - (columns - 1) * Grid.GUTTER) / columns)
end

function Grid.row(screen_w, columns, cells)
    local row = HorizontalGroup:new{ align = "top" }
    table.insert(row, HorizontalSpan:new{ width = Grid.MARGIN })
    for i, cell in ipairs(cells) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = Grid.GUTTER }) end
        table.insert(row, cell)
    end
    -- Rechtermarge; lege kolommen tellen gewoon mee.
    local used = Grid.MARGIN + #cells * Grid.columnWidth(screen_w, columns) + math.max(0, #cells - 1) * Grid.GUTTER
    table.insert(row, HorizontalSpan:new{ width = math.max(0, screen_w - used) })
    return row
end

return Grid
