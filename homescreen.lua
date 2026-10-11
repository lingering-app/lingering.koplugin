--[[--
Homescreen: statusregel, huidig boek in het midden, navigatiebalk onder
(Mijn boeken, Instellingen).
Ligt schermvullend over de bestandsbeheerder; vangt alle gebaren af, zodat het menu
van de bestandsbeheerder niet open kan.
]]
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local Compat = require("lingering_compat")
local Widgets = require("lingering_widgets")

-- Zo lang ingedrukt houden op de statusregel opent het noodluik (na de hold-drempel).
local EMERGENCY_HOLD_SECONDS = 2.5

local HomeScreen = InputContainer:extend{
    fm = nil,               -- FileManager-instantie
    on_local_books = nil,
    on_settings = nil,
    on_emergency = nil,
    on_closed = nil,
    covers_fullscreen = true,
    modal = true,
    stop_events_propagation = true,
}
Widgets.guardPaint(HomeScreen, "homescreen")

function HomeScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.book = Compat.currentBook(self.fm)
    self:build()

    self.ges_events = {
        TapBook = {
            GestureRange:new{ ges = "tap", range = function() return self.book_dimen end },
        },
        HoldStatus = {
            GestureRange:new{ ges = "hold", range = function() return self.status_dimen end },
        },
        HoldReleaseStatus = {
            GestureRange:new{ ges = "hold_release", range = function() return self.dimen end },
        },
    }
end

--[[--
Statusregel: "Lingering" links; rechts lamp en wifi (aantikbaar), tijd en batterij.
De iconen blijven bestaan; refreshStatus werkt ze en de teksten ter plekke bij.
]]
function HomeScreen:buildStatus(width)
    local padding = Size.padding.large * 2
    local face = Font:getFace("cfont", 16)
    local height = Screen:scaleBySize(48)
    local inner = Geom:new{ w = width - 2 * padding, h = height }
    local Item = require("lingering_actionbar").Item

    -- Ruim tikvlak per icoon (de hele hoogte van de statusregel).
    local function item(action)
        return Item:new{
            action = action,
            width = height,
            height = height,
            icon_size = Screen:scaleBySize(26),
            show_parent = self,
        }
    end

    self.light_item = item{
        name = "licht",
        switch = true,
        icon_on = "light-on.svg",
        icon_off = "light-off.svg",
        enabled = Device:hasFrontlight(),
        state = Compat.isFrontlightOn(),
        on_toggle = function(on)
            logger.info("Lingering: homescreen, licht", on and "aan" or "uit")
            Compat.toggleFrontlight(self.fm)
        end,
    }
    self.wifi_item = item{
        name = "wifi",
        switch = true,
        enabled = Device:hasWifiToggle(),
        state = Compat.isWifiOn(),
        -- Uit: doorgestreept. Aan zonder verbinding: grijs. Verbonden: zwart.
        icon_spec = function(on)
            if not on then
                return { icon_file = "wifi-off.svg" }
            end
            return { icon_file = "wifi-on.svg", dim = not Compat.isWifiConnected() }
        end,
        on_toggle = function(on)
            logger.info("Lingering: homescreen, wifi", on and "aan" or "uit")
            Compat.setWifi(on, function()
                self.wifi_item:setState(Compat.isWifiOn())
            end)
        end,
    }

    self.status_right = HorizontalGroup:new{
        align = "center",
        self.light_item,
        self.wifi_item,
        HorizontalSpan:new{ width = Size.padding.large },
        TextWidget:new{ text = "", face = face },      -- tijd, zie updateStatusTexts
        HorizontalSpan:new{ width = padding },
        TextWidget:new{ text = "", face = face },      -- batterij
    }
    self.status_face = face
    self:updateStatusTexts()

    return FrameContainer:new{
        padding = 0,
        padding_left = padding,
        padding_right = padding,
        bordersize = 0,
        OverlapGroup:new{
            dimen = inner,
            LeftContainer:new{ dimen = inner, TextWidget:new{ text = "Lingering", face = face, bold = true } },
            RightContainer:new{ dimen = inner, self.status_right },
        },
    }
end

function HomeScreen:updateStatusTexts()
    local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local battery = Compat.batteryPercent()
    self.status_right[4] = TextWidget:new{ text = time, face = self.status_face }
    self.status_right[6] = TextWidget:new{ text = battery and T(_("%1%"), battery) or "", face = self.status_face }
    self.status_right:resetLayout()
end

function HomeScreen:buildBook(width, height)
    local padding = Size.padding.large * 2
    local inner_w = width - 2 * padding

    if not self.book then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextBoxWidget:new{
                text = _("Nog geen boek.\nTik hier om er een te kiezen uit Mijn boeken."),
                face = Font:getFace("cfont", 22),
                width = inner_w,
                alignment = "center",
            },
        }
    end

    -- Omslag in de verhouding 2:3, zo groot als past.
    local cover_h = height - 2 * padding
    local cover_w = math.floor(math.min(cover_h * 2 / 3, inner_w * 0.42))
    cover_h = math.floor(cover_w * 3 / 2)
    local cover
    if self.book.cover then
        -- Schalen met behoud van de eigen verhouding, zodat er geen witte rand overblijft.
        local bb = self.book.cover
        local scale = math.min(cover_w / bb:getWidth(), cover_h / bb:getHeight())
        cover_w = math.floor(bb:getWidth() * scale)
        cover = ImageWidget:new{
            image = bb,
            -- Zelf vrijgeven in onCloseWidget: de omslag mag een herbouw overleven.
            image_disposable = false,
            width = cover_w,
            height = math.floor(bb:getHeight() * scale),
            scale_factor = 0,
        }
    else
        cover = CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = cover_h },
            Widgets.icon({ icon = "book.opened" }, math.floor(cover_w / 2)),
        }
    end

    local text_w = inner_w - cover_w - padding
    local info = VerticalGroup:new{ align = "left" }
    table.insert(info, TextBoxWidget:new{
        text = self.book.title,
        face = Font:getFace("cfont", 26),
        bold = true,
        width = text_w,
        height = Screen:scaleBySize(26) * 4,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    })
    if self.book.authors and self.book.authors ~= "" then
        table.insert(info, VerticalSpan:new{ width = Size.padding.large })
        table.insert(info, TextBoxWidget:new{
            text = self.book.authors,
            face = Font:getFace("cfont", 20),
            width = text_w,
            height = Screen:scaleBySize(20) * 2,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        })
    end
    local percent = self.book.percent or 0
    table.insert(info, VerticalSpan:new{ width = Size.padding.large * 3 })
    table.insert(info, ProgressWidget:new{
        width = text_w,
        height = Screen:scaleBySize(10),
        percentage = percent,
        margin_h = 0,
        margin_v = 0,
        radius = 0,
        fillcolor = Blitbuffer.COLOR_BLACK,
    })
    table.insert(info, VerticalSpan:new{ width = Size.padding.default })
    table.insert(info, TextWidget:new{
        text = T(_("%1% gelezen"), math.floor(percent * 100 + 0.5)),
        face = Font:getFace("cfont", 18),
    })

    return FrameContainer:new{
        padding = padding,
        bordersize = 0,
        HorizontalGroup:new{
            align = "center",
            cover,
            HorizontalSpan:new{ width = padding },
            info,
        },
    }
end

function HomeScreen:build()
    local width, height = self.dimen.w, self.dimen.h

    local nav = Widgets.navBar(width, {
        {
            text = _("Mijn boeken"),
            icon = { icon = "book.opened" },
            callback = function() self.on_local_books() end,
        },
        {
            text = _("Instellingen"),
            icon = { icon = "appbar.settings" },
            callback = function() self.on_settings() end,
        },
    })

    local status = self:buildStatus(width)
    local status_h = status:getSize().h
    local line_h = Widgets.line(width):getSize().h
    local book_h = height - status_h - line_h - nav:getSize().h
    local book = self:buildBook(width, book_h)

    self.status_dimen = Geom:new{ x = 0, y = 0, w = width, h = status_h }
    self.book_dimen = Geom:new{ x = 0, y = status_h + line_h, w = width, h = book_h }

    -- Statusregel boven, huidig boek in het midden, navigatiebalk onder.
    self.layout_group = VerticalGroup:new{
        align = "left",
        status,
        Widgets.line(width),
        CenterContainer:new{ dimen = Geom:new{ w = width, h = book_h }, book },
        nav,
    }
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.layout_group,
    }
end

function HomeScreen:onTapBook()
    if self.book then
        logger.info("Lingering: homescreen, boek openen")
        local file = self.book.file
        self:close()
        Compat.openBook(file)
    else
        Widgets.safeCall("mijn boeken", self.on_local_books)
    end
    return true
end

function HomeScreen:onHoldStatus()
    self.emergency_task = function()
        self.emergency_task = nil
        logger.info("Lingering: statusregel lang ingedrukt, noodluik")
        Widgets.safeCall("noodluik", self.on_emergency)
    end
    UIManager:scheduleIn(EMERGENCY_HOLD_SECONDS, self.emergency_task)
    return true
end

function HomeScreen:onHoldReleaseStatus()
    if self.emergency_task then
        UIManager:unschedule(self.emergency_task)
        self.emergency_task = nil
    end
    return true
end

-- Statusregel bijwerken bij ontwaken en netwerkwissels; verder geen verversingen.
function HomeScreen:refreshStatus()
    self:updateStatusTexts()
    self.wifi_item:setState(Compat.isWifiOn())
    self.light_item:setState(Compat.isFrontlightOn())
    UIManager:setDirty(self, "ui", self.status_dimen)
end
HomeScreen.onResume = HomeScreen.refreshStatus
HomeScreen.onNetworkConnected = HomeScreen.refreshStatus
HomeScreen.onNetworkDisconnected = HomeScreen.refreshStatus

-- Een andere route opent een boek (bijv. de OPDS-browser): dan gaan wij ook weg.
function HomeScreen:onShowingReader()
    self:close()
end

function HomeScreen:onCloseWidget()
    if self.emergency_task then
        UIManager:unschedule(self.emergency_task)
        self.emergency_task = nil
    end
    if self.book and self.book.cover then
        self.book.cover:free()
        self.book.cover = nil
    end
    if self.on_closed then
        Widgets.safeCall("homescreen gesloten", self.on_closed)
    end
end

function HomeScreen:show()
    UIManager:show(self, "full")
end

function HomeScreen:close()
    UIManager:close(self, "full")
end

return HomeScreen
