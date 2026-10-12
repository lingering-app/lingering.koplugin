--[[--
Keuzelijst vanuit Instellingen (Taal, Woordenboek): titelbalk, een rij per keuze, de
navigatiebalk onderaan. Rechts per rij een icoon (bijv. een vinkje bij de huidige keuze).

ChoiceScreen:new{
    title = "Taal",
    nav = { home = fn, library = fn, settings = fn },
    items = {
        { label = "Nederlands", icon = { icon_file = "language.svg" },
          right = function() return { icon_file = "check.svg" } or nil end,
          choose = function(screen) ... screen:refresh() end },
    },
}:show()
]]
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local Widgets = require("lingering.ui.widgets")
local Style = require("lingering.ui.style")

local ChoiceScreen = InputContainer:extend{
    title = nil,
    items = nil,
    nav = nil,
    covers_fullscreen = true,
    stop_events_propagation = true,
}
Widgets.guardPaint(ChoiceScreen, "keuzelijst")
Widgets.guardEvents(ChoiceScreen, "keuzelijst")
Widgets.followRotation(ChoiceScreen)

function ChoiceScreen:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }

    local title_bar = Widgets.header{
        width = width,
        title = self.title,
        on_back = function() self:close() end,
        show_parent = self,
    }
    self.rows = {}
    local group = VerticalGroup:new{ align = "left", title_bar, Widgets.line(width) }
    for i, item in ipairs(self.items) do
        local row = Widgets.Row:new{
            width = width,
            text = item.label,
            icon = item.icon,
            right = item.right and item.right() or nil,
            callback = function()
                Widgets.safeCall("keuze " .. tostring(item.label), item.choose, self)
            end,
        }
        self.rows[i] = row
        table.insert(group, row)
        table.insert(group, Widgets.line(width))
    end

    -- Navigatiebalk onderaan; Instellingen vet, een tik erop gaat terug naar Instellingen.
    local nav = Widgets.mainNav(width, self.nav, "settings", function() self:close() end)
    local used = nav:getSize().h
    for _, widget in ipairs(group) do used = used + widget:getSize().h end
    table.insert(group, VerticalSpan:new{ width = math.max(0, height - used) })
    table.insert(group, nav)

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Style.background,
        group,
    }
end

--- De rechter iconen opnieuw bepalen (na een keuze of een download).
function ChoiceScreen:refresh()
    if self.closed then return end
    for i, item in ipairs(self.items) do
        local row = self.rows[i]
        -- Direct zetten: update{ right = nil } zou het oude icoon laten staan.
        row.right = item.right and item.right() or nil
        row:update{}
    end
    UIManager:setDirty(self, "ui")
end

function ChoiceScreen:onClose()
    self:close()
    return true
end

function ChoiceScreen:show()
    UIManager:show(self, "full")
end

function ChoiceScreen:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "full")
end

return ChoiceScreen
