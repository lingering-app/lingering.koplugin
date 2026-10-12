--[[--
Eén stijl voor alle schermen van Lingering: kleuren, lijnen, randen en de maten van de
bovenbalk. Widgets halen hun waarden hier vandaan, zodat alles hetzelfde oogt; pas een
waarde hier aan in plaats van in een scherm.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Size = require("ui/size")

local Style = {
    background = Blitbuffer.COLOR_WHITE,
    text = Blitbuffer.COLOR_BLACK,
    -- Bijzaken: resterende tijd, versie, uitgeschakelde rijen.
    text_secondary = Blitbuffer.COLOR_DARK_GRAY,

    -- Alle lijnen: tussen rijen, boven de navigatiebalk, onder de actiebalk in het boek,
    -- en de rand van kaders (popover).
    line = { size = Size.line.medium, color = Blitbuffer.COLOR_DARK_GRAY },
    -- Rand om omslagen in een stapel en om een omslag zonder afbeelding.
    cover_border = { size = Size.border.thin, color = Blitbuffer.COLOR_DARK_GRAY },
    radius = Size.radius.window,

    -- Voortgangsbalk: lichtgrijze baan, gelezen deel donkergrijs.
    progress = { track = Blitbuffer.COLOR_LIGHT_GRAY, fill = Blitbuffer.COLOR_DARK_GRAY },

    -- Bovenbalk (homescreen, titelbalken, actiebalk in het boek). item_width: tikvlak per
    -- icoon, smaller dan de hoogte zodat er in het boek extra knoppen passen.
    top_bar = { height = 60, font_size = 16, icon_size = 30, item_width = 48 },
}

--- Lettertype van de bovenbalk (ook voor kaders die erbij horen).
function Style.topBarFace()
    return Font:getFace("cfont", Style.top_bar.font_size)
end

return Style
