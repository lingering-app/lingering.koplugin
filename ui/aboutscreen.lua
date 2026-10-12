--[[--
Over Lingering: versie, korte uitleg, copyright, licentie, repo.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local Config = require("lingering.config")
local UpdateService = require("lingering.app.update_service")
local Widgets = require("lingering.ui.widgets")

local AboutScreen = InputContainer:extend{
    covers_fullscreen = true,
    stop_events_propagation = true,
}
Widgets.guardPaint(AboutScreen, "over lingering")
Widgets.guardEvents(AboutScreen, "over lingering")
Widgets.followRotation(AboutScreen)

function AboutScreen:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    local text_w = width - 8 * Size.padding.large

    local title_bar = Widgets.header{
        width = width,
        title = _("Over Lingering"),
        on_back = function() self:close() end,
        show_parent = self,
    }

    local version = UpdateService.installedVersion()
    local function line(text, size, bold, color)
        return TextBoxWidget:new{
            text = text,
            face = Font:getFace("cfont", size),
            bold = bold,
            fgcolor = color,
            width = text_w,
            alignment = "center",
        }
    end
    local gap = VerticalSpan:new{ width = Size.padding.large * 3 }

    local content = VerticalGroup:new{
        align = "center",
        TextWidget:new{ text = "Lingering", face = Font:getFace("cfont", 34), bold = true },
        VerticalSpan:new{ width = Size.padding.large },
        line(version and T(_("Versie %1"), version) or _("Versie onbekend"), 18, false, Blitbuffer.COLOR_DARK_GRAY),
        VerticalSpan:new{ width = Size.padding.large * 2 },
        Button:new{
            text = _("Zoeken naar update"),
            width = math.floor(text_w * 0.6),
            radius = Size.radius.button,
            show_parent = self,
            callback = function()
                Widgets.safeCall("update", require("lingering.ui.update_flow").run)
            end,
        },
        gap,
        line(_("Een rustige leesomgeving bovenop KOReader: je boeken, je voortgang op al je apparaten, en verder niets."), 18),
        gap,
        line(_("© 2026 Lingering"), 16),
        VerticalSpan:new{ width = Size.padding.large },
        line(_("Vrije software onder de GNU Affero General Public License v3.0."), 15, false, Blitbuffer.COLOR_DARK_GRAY),
        VerticalSpan:new{ width = Size.padding.default },
        line("github.com/" .. Config.update_repo, 15, false, Blitbuffer.COLOR_DARK_GRAY),
        gap,
        line(_("Gebouwd op KOReader."), 15, false, Blitbuffer.COLOR_DARK_GRAY),
    }

    -- Navigatiebalk: Instellingen staat vet; een tik erop gaat terug naar Instellingen.
    local nav = Widgets.mainNav(width, self.nav, "settings", function() self:close() end)
    local body_h = height - title_bar.height - nav:getSize().h
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            title_bar,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = body_h },
                content,
            },
            nav,
        },
    }
end

function AboutScreen:onClose()
    self:close()
    return true
end

function AboutScreen:show()
    UIManager:show(self, "full")
end

function AboutScreen:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "full")
end

return AboutScreen
