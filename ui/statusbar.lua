--[[--
Statusbalk bovenaan: links een titel ("Lingering") of knoppen, rechts eventuele extra
knoppen, dan licht, wifi, batterij en helemaal rechts de tijd. Gebruikt op het homescreen
en (met knoppen voor huis, inhoudsopgave, sync en draaien) als actiebalk in het boek,
zodat beide hetzelfde zijn.

StatusBar:new{
    width = schermbreedte,
    show_parent = venster (voor verversingen),
    title = "Lingering",          -- of nil
    left = { actie, ... },        -- in plaats van de titel (optioneel)
    extra = { actie, ... },       -- rechts vóór licht en wifi (optioneel)
}
Acties zoals ActionBar.Item ze kent (knop met callback, schakelaar, taak).
Werkt zichzelf bij op Resume, netwerk-events, Charging/NotCharging en FrontlightStateChanged.
]]
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local logger = require("logger")
local Screen = Device.screen

local DeviceAdapter = require("lingering.koreader.device")
local Network = require("lingering.koreader.network")
local Widgets = require("lingering.ui.widgets")

local StatusBar = WidgetContainer:extend{
    width = nil,
    show_parent = nil,
    title = nil,
    left = nil,
    extra = nil,
}

function StatusBar:init()
    local Item = require("lingering.ui.actionbar").Item
    local padding = Size.padding.large * 2
    local height = Screen:scaleBySize(Widgets.TOP_BAR.height)
    local item_w = Screen:scaleBySize(Widgets.TOP_BAR.item_width)
    local icon_size = Screen:scaleBySize(Widgets.TOP_BAR.icon_size)
    self.face = Widgets.topBarFace()
    self.items = {}

    local function item(action)
        local new = Item:new{
            action = action,
            width = item_w,
            height = height,
            icon_size = icon_size,
            show_parent = self.show_parent,
            on_tap = action.callback,
        }
        table.insert(self.items, new)
        return new
    end

    local left = HorizontalGroup:new{ align = "center" }
    if self.left then
        for _, action in ipairs(self.left) do table.insert(left, item(action)) end
    elseif self.title then
        table.insert(left, TextWidget:new{ text = self.title, face = self.face, bold = true })
    end

    self.right = HorizontalGroup:new{ align = "center" }
    for _, action in ipairs(self.extra or {}) do table.insert(self.right, item(action)) end
    self.light_item = item{
        name = "licht",
        switch = true,
        icon_on = "light_mode.svg",
        icon_off = "dark_mode.svg",
        enabled = Device:hasFrontlight(),
        state = DeviceAdapter.isFrontlightOn(),
        on_toggle = function(on)
            logger.info("Lingering: statusbalk, licht", on and "aan" or "uit")
            DeviceAdapter.toggleFrontlight(function()
                self.light_item:setState(DeviceAdapter.isFrontlightOn())
            end)
        end,
    }
    self.wifi_item = item{
        name = "wifi",
        switch = true,
        enabled = Device:hasWifiToggle(),
        state = Network.isWifiOn(),
        -- Uit: doorgestreept. Aan zonder verbinding: grijs. Verbonden: zwart.
        icon_spec = function(on)
            if not on then
                return { icon_file = "wifi_off.svg" }
            end
            return { icon_file = "wifi.svg", dim = not Network.isConnected() }
        end,
        on_toggle = function(on)
            logger.info("Lingering: statusbalk, wifi", on and "aan" or "uit")
            Network.setWifi(on, function()
                self.wifi_item:setState(Network.isWifiOn())
            end)
        end,
    }
    table.insert(self.right, self.light_item)
    table.insert(self.right, self.wifi_item)
    -- Vaste plekken voor tijd en batterij, ingevuld door updateTexts.
    self.slot = #self.right
    table.insert(self.right, HorizontalSpan:new{ width = Size.padding.large })
    table.insert(self.right, HorizontalSpan:new{ width = 0 })                    -- batterij-icoon
    table.insert(self.right, HorizontalSpan:new{ width = padding })
    table.insert(self.right, TextWidget:new{ text = "", face = self.face })     -- tijd, helemaal rechts
    self:updateTexts()

    -- Met knoppen links begint de balk tegen de rand (eigen tikvlak); met een titel ingesprongen.
    local inner = Geom:new{ w = self.width - (self.left and 0 or padding) - padding, h = height }
    self[1] = FrameContainer:new{
        padding = 0,
        padding_left = self.left and 0 or padding,
        padding_right = padding,
        bordersize = 0,
        OverlapGroup:new{
            dimen = inner,
            LeftContainer:new{ dimen = inner, left },
            RightContainer:new{ dimen = inner, self.right },
        },
    }
end

function StatusBar:updateTexts()
    local s = self.slot
    local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local battery = DeviceAdapter.batteryPercent()
    -- Alleen het icoon (9 standen, zie Widgets.battery), geen percentage.
    if battery then
        self.right[s + 2] = Widgets.battery(battery, DeviceAdapter.isCharging())
    end
    self.right[s + 4] = TextWidget:new{ text = time, face = self.face }
    self.right:resetLayout()
end

--- Tijd, batterij, wifi en licht opnieuw lezen en de balk verversen.
function StatusBar:refresh()
    self:updateTexts()
    self.wifi_item:setState(Network.isWifiOn())
    self.light_item:setState(DeviceAdapter.isFrontlightOn())
    if self.dimen then UIManager:setDirty(self.show_parent, "ui", self.dimen) end
end

-- Licht veranderd (hier, in Instellingen of in KOReaders helderheidsscherm).
function StatusBar:onFrontlightStateChanged()
    self.light_item:setState(DeviceAdapter.isFrontlightOn())
end

-- Geen return true: de events gaan ook naar de rest van het venster.
function StatusBar:onResume() self:refresh() end
function StatusBar:onNetworkConnected() self:refresh() end
function StatusBar:onNetworkDisconnected() self:refresh() end
-- Lader in of uit (Device:_beforeCharging / _afterNotCharging).
function StatusBar:onCharging() self:refresh() end
function StatusBar:onNotCharging() self:refresh() end

return StatusBar
