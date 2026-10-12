--[[--
Schuif: − [balk] +. Een tik op de balk springt naar die stand; − en + doen een stap.
Geen slepen: op e-ink is elke tik één nette verversing van alleen de balk.

Slider:new{
    width = totale breedte,
    min = 0, max = 100, value = 40,
    steps = 10,                     -- aantal stappen van − en + over het hele bereik
    on_change = function(value) end,
    show_parent = venster (voor verversingen),
}
]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Style = require("lingering.ui.style")

local Slider = InputContainer:extend{
    width = nil,
    min = 0,
    max = 100,
    value = 0,
    steps = 10,
    on_change = nil,
    show_parent = nil,
}

function Slider:init()
    local Item = require("lingering.ui.actionbar").Item
    local item_w = Screen:scaleBySize(Style.top_bar.item_width)
    local height = Screen:scaleBySize(Style.top_bar.height)
    local icon_size = Screen:scaleBySize(Style.top_bar.icon_size)
    local step = math.max(1, math.floor((self.max - self.min) / self.steps + 0.5))
    local function button(icon_file, delta)
        return Item:new{
            action = { icon_file = icon_file },
            width = item_w, height = height, icon_size = icon_size,
            show_parent = self.show_parent,
            on_tap = function() self:set(self.value + delta) end,
        }
    end
    local bar_w = self.width - 2 * item_w
    self.progress = ProgressWidget:new{
        width = bar_w,
        height = Screen:scaleBySize(12),
        percentage = self:fraction(),
        margin_h = 0,
        margin_v = 0,
        radius = 0,
        bordersize = 0,
        bgcolor = Style.progress.track,
        fillcolor = Style.progress.fill,
    }
    -- Ruim tikvlak: de hele hoogte van de rij. Een InputContainer onthoudt bij het tekenen
    -- zijn schermpositie (dimen.x/y), nodig om een tik om te rekenen naar een stand.
    self.bar_box = InputContainer:new{
        dimen = Geom:new{ w = bar_w, h = height },
        CenterContainer:new{ dimen = Geom:new{ w = bar_w, h = height }, self.progress },
    }
    self[1] = HorizontalGroup:new{
        align = "center",
        button("remove.svg", -step),
        self.bar_box,
        button("add.svg", step),
    }
    self.ges_events = {
        TapBar = { GestureRange:new{ ges = "tap", range = function() return self.bar_box.dimen end } },
    }
end

function Slider:fraction()
    if self.max <= self.min then return 0 end
    return (self.value - self.min) / (self.max - self.min)
end

function Slider:onTapBar(_, ges)
    local box = self.bar_box.dimen
    if not (box and ges and ges.pos) then return true end
    local fraction = (ges.pos.x - box.x) / box.w
    self:set(self.min + math.floor(fraction * (self.max - self.min) + 0.5))
    return true
end

function Slider:set(value)
    value = math.max(self.min, math.min(self.max, value))
    if value == self.value then return end
    self.value = value
    self.progress:setPercentage(self:fraction())
    UIManager:setDirty(self.show_parent, "ui", self.bar_box.dimen)
    if self.on_change then self.on_change(value) end
end

return Slider
