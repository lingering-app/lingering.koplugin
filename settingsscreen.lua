--[[--
Instellingen: wifi aan/uit, account (gebruikersnaam en wachtwoord), en onderaan
"Geavanceerd" (het noodluik naar het volledige KOReader-menu).
]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local Compat = require("lingering_compat")
local Widgets = require("lingering_widgets")

local SettingsScreen = InputContainer:extend{
    on_account = nil,
    on_emergency = nil,
    covers_fullscreen = true,
    -- Niet modal: anders komen dialogen van KOReader (bijv. MultiInputDialog) eronder
    -- (UIManager:show zet niet-modale vensters onder het bovenste modale venster).
    stop_events_propagation = true,
}
Widgets.guardPaint(SettingsScreen, "instellingen")

local function toggleIcon(on)
    return { icon_file = on and "toggle-on.svg" or "toggle-off.svg" }
end

function SettingsScreen:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }

    local title_bar = TitleBar:new{
        width = width,
        fullscreen = true,
        title = _("Instellingen"),
        with_bottom_line = true,
        left_icon = "chevron.left",
        left_icon_tap_callback = function() self:close() end,
    }

    local wifi_on = Compat.isWifiOn()
    self.wifi_row = Widgets.Row:new{
        width = width,
        text = _("Wifi"),
        icon = { icon = "wifi" },
        right = toggleIcon(wifi_on),
        enabled = Device:hasWifiToggle(),
        -- Rij: netwerk kiezen (KOReaders netwerkscherm); schakelaar rechts: wifi aan/uit.
        callback = function()
            logger.info("Lingering: instellingen, wifi-netwerken")
            Compat.showNetworkList(function() self:updateWifi() end)
        end,
        right_callback = function() self:toggleWifi() end,
    }

    local top_rows = {
        self.wifi_row,
        Widgets.Row:new{
            width = width,
            text = _("Account"),
            icon = { icon_file = "account.svg" },
            right = { icon = "chevron.right" },
            callback = function() self.on_account() end,
        },
    }
    local advanced = Widgets.Row:new{
        width = width,
        text = _("Geavanceerd"),
        right = { icon = "chevron.right" },
        callback = function()
            self:close()
            self.on_emergency()
        end,
    }

    local group = VerticalGroup:new{ align = "left", title_bar }
    for _, row in ipairs(top_rows) do
        table.insert(group, row)
        table.insert(group, Widgets.line(width))
    end
    -- "Geavanceerd" onderaan, los van de rest. (Hoogte berekenen zonder group:getSize():
    -- VerticalGroup onthoudt zijn maten, en latere elementen zouden dan geen positie krijgen.)
    local used = advanced:getSize().h + Widgets.line(width):getSize().h
    for _, widget in ipairs(group) do
        used = used + widget:getSize().h
    end
    table.insert(group, VerticalSpan:new{ width = math.max(0, height - used) })
    table.insert(group, Widgets.line(width))
    table.insert(group, advanced)

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        group,
    }
end

function SettingsScreen:toggleWifi()
    local turn_on = not Compat.isWifiOn()
    logger.info("Lingering: instellingen, wifi", turn_on and "aan" or "uit")
    Compat.setWifi(turn_on, function()
        self:updateWifi()
    end)
    self:updateWifi()
end

function SettingsScreen:updateWifi()
    self.wifi_row:update{ right = toggleIcon(Compat.isWifiOn()) }
    UIManager:setDirty(self, "ui", self.wifi_row.dimen)
end
SettingsScreen.onNetworkConnected = SettingsScreen.updateWifi
SettingsScreen.onNetworkDisconnected = SettingsScreen.updateWifi

function SettingsScreen:onClose()
    self:close()
    return true
end

function SettingsScreen:show()
    UIManager:show(self, "full")
end

function SettingsScreen:close()
    UIManager:close(self, "full")
end

return SettingsScreen
