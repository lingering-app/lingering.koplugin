--[[--
Klein menu in een kader onder een knop (bijv. "…" op een boek): een rij per item, een tik
voert het item uit en sluit het menu. Gebouwd op ui/popover.lua (zelfde rand, sluit bij een
tik ernaast of na een paar seconden).

PopoverMenu.show{
    anchor = Geom (schermpositie van de knop, bijv. item.dimen),
    items = { { text = _("Gelezen"), callback = function() ... end }, ... },
}
]]
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local Widgets = require("lingering.ui.widgets")
local Style = require("lingering.ui.style")

-- Eén regel in het menu: ruim tikvlak over de hele breedte van het menu.
local MenuItem = InputContainer:extend{
    text = nil,
    width = nil,
    height = nil,
    callback = nil,
}

function MenuItem:init()
    self[1] = LeftContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        TextWidget:new{ text = self.text, face = Style.topBarFace() },
    }
    self.ges_events = {
        TapMenuItem = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function MenuItem:onTapMenuItem()
    if self.callback then self.callback() end
    return true
end

local PopoverMenu = {}

function PopoverMenu.show(opts)
    local Popover = require("lingering.ui.popover")
    local face = Style.topBarFace()
    local height = Screen:scaleBySize(Style.top_bar.item_width)
    -- Zo breed als de langste tekst, minstens een paar keer de rijhoogte.
    local width = height * 3
    for _, item in ipairs(opts.items) do
        width = math.max(width, TextWidget:new{ text = item.text, face = face }:getSize().w + Size.padding.large)
    end
    local popover
    popover = Popover:new{
        anchor = opts.anchor,
        -- Direct onder de knop: de knop heeft zelf al wat ruimte rond het icoon.
        gap = 0,
        content = function()
            local group = VerticalGroup:new{ align = "left" }
            for _, item in ipairs(opts.items) do
                table.insert(group, MenuItem:new{
                    text = item.text,
                    width = width,
                    height = height,
                    callback = function()
                        popover:dismiss()
                        Widgets.safeCall("menu " .. tostring(item.text), item.callback)
                    end,
                })
            end
            return group
        end,
    }
    popover:show()
    return popover
end

return PopoverMenu
