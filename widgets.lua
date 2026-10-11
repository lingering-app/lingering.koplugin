--[[--
Gedeelde bouwstenen voor de schermen van Lingering.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local logger = require("logger")
local Screen = Device.screen

local Widgets = {}

Widgets.plugin_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

--- Callbacks van tikken vallen niet onder de HandlerSandbox van de pluginloader: zelf afvangen.
function Widgets.safeCall(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        logger.warn("Lingering: fout in", label, err)
    end
    return ok
end

--[[--
Vangnet voor het tekenen. Fouten in paintTo vangt KOReader niet af: die laten KOReader
crashen. Faalt het tekenen van dit scherm, dan loggen we en sluiten we het scherm; de
widgets eronder (bestandsbeheerder of lezer) blijven bruikbaar.
]]
function Widgets.guardPaint(class, label)
    local paintTo = class.paintTo
    class.paintTo = function(self, bb, x, y)
        if self.paint_failed then return end
        local ok, err = pcall(paintTo, self, bb, x, y)
        if not ok then
            self.paint_failed = true
            logger.warn("Lingering: tekenen van", label, "mislukt, scherm wordt gesloten:", err)
            local UIManager = require("ui/uimanager")
            UIManager:nextTick(function()
                pcall(UIManager.close, UIManager, self, "full")
            end)
        end
    end
end

--- Icoon uit KOReader (icon = naam) of uit de plugin (icon_file = bestandsnaam in icons/).
function Widgets.icon(spec, size, dim)
    return IconWidget:new{
        icon = spec.icon,
        file = spec.icon_file and (Widgets.plugin_dir .. "/icons/" .. spec.icon_file) or nil,
        width = size,
        height = size,
        alpha = true,
        dim = dim,
    }
end

function Widgets.line(width)
    return LineWidget:new{
        dimen = Geom:new{ w = width, h = Size.line.medium },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }
end

--[[--
Grote rij over de volle breedte: [icoon] tekst ............ [rechts]
rechts is een widget (bijv. pijltje of schakelaar-icoon) of nil.
]]
local Row = InputContainer:extend{
    width = nil,
    text = nil,
    icon = nil,         -- { icon = "..." } of { icon_file = "..." }
    right = nil,        -- { icon = "..." } of { icon_file = "..." }
    enabled = true,
    callback = nil,
}
Widgets.Row = Row

function Row:init()
    self.height = Screen:scaleBySize(72)
    self:build()
    self.ges_events = {
        TapRow = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function Row:build()
    local padding = Size.padding.large * 2
    local icon_size = Screen:scaleBySize(32)
    local fg = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY

    local left = HorizontalGroup:new{ align = "center" }
    if self.icon then
        table.insert(left, Widgets.icon(self.icon, icon_size, not self.enabled))
        table.insert(left, HorizontalSpan:new{ width = padding })
    end
    table.insert(left, TextWidget:new{
        text = self.text,
        face = Font:getFace("cfont", 22),
        fgcolor = fg,
        max_width = self.width - 2 * padding - 3 * icon_size,
    })

    local inner = Geom:new{ w = self.width - 2 * padding, h = self.height }
    local overlap = OverlapGroup:new{
        dimen = inner,
        LeftContainer:new{ dimen = inner, left },
    }
    if self.right then
        table.insert(overlap, RightContainer:new{
            dimen = inner,
            Widgets.icon(self.right, icon_size, not self.enabled),
        })
    end
    self[1] = FrameContainer:new{
        padding = 0,
        padding_left = padding,
        padding_right = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        overlap,
    }
end

function Row:update(fields)
    for k, v in pairs(fields) do self[k] = v end
    self:build()
end

function Row:onTapRow()
    if self.enabled and self.callback then
        Widgets.safeCall("rij " .. tostring(self.text), self.callback)
    end
    return true
end

return Widgets
