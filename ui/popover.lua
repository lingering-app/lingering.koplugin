--[[--
Klein kader direct onder een icoon, met een paar regels tekst. Sluit bij een tik (waar dan
ook; die tik doet verder niets) of na een paar seconden. Alleen dat stukje scherm ververst.

Popover:new{
    anchor = Geom (schermpositie van het icoon, bijv. item.dimen),
    lines = { { text = "62%", bold = true }, { text = "Laadt op", gray = true } },
}:show()
Modal, zodat hij ook boven de (modale) actiebalk in het boek komt.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local Widgets = require("lingering.ui.widgets")

-- Zo lang blijft het kader staan zonder tik.
local TIMEOUT = 4

local Popover = InputContainer:extend{
    anchor = nil,
    lines = nil,
    modal = true,
}
Widgets.guardPaint(Popover, "popover")
Widgets.guardEvents(Popover, "popover")

function Popover:init()
    local group = VerticalGroup:new{ align = "center" }
    for _, line in ipairs(self.lines or {}) do
        table.insert(group, TextWidget:new{
            text = line.text,
            face = Widgets.topBarFace(),
            bold = line.bold,
            fgcolor = line.gray and Blitbuffer.COLOR_DARK_GRAY or nil,
        })
    end
    self[1] = FrameContainer:new{
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = Size.padding.large,
        padding_left = Size.padding.large * 2,
        padding_right = Size.padding.large * 2,
        background = Blitbuffer.COLOR_WHITE,
        group,
    }
    -- Onder het icoon, horizontaal gecentreerd erop, maar binnen het scherm.
    local size = self[1]:getSize()
    local margin = Size.padding.default
    local anchor = self.anchor or Geom:new{ x = 0, y = 0, w = 0, h = 0 }
    local x = anchor.x + math.floor((anchor.w - size.w) / 2)
    x = math.max(margin, math.min(x, Screen:getWidth() - size.w - margin))
    self.dimen = Geom:new{ x = x, y = anchor.y + anchor.h, w = size.w, h = size.h }

    self.ges_events = {
        TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
            },
        },
    }
end

function Popover:onTapClose()
    self:dismiss()
    return true
end

function Popover:onClose()
    self:dismiss()
    return true
end

function Popover:show()
    UIManager:show(self, "ui", self.dimen, self.dimen.x, self.dimen.y)
    self.timeout = function() self:dismiss() end
    UIManager:scheduleIn(TIMEOUT, self.timeout)
end

function Popover:dismiss()
    if self.closed then return end
    self.closed = true
    if self.timeout then UIManager:unschedule(self.timeout) end
    UIManager:close(self, "ui", self.dimen)
end

return Popover
