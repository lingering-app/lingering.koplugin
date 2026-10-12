--[[--
Homescreen: statusregel, huidig boek eronder, navigatiebalk onderaan
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

local Books = require("lingering.koreader.books")
local ReadingTime = require("lingering.domain.reading_time")
local DeviceAdapter = require("lingering.koreader.device")
local Navigation = require("lingering.koreader.navigation")
local Network = require("lingering.koreader.network")
local Widgets = require("lingering.ui.widgets")

-- Zo lang ingedrukt houden op de statusregel opent het noodluik (na de hold-drempel).
local EMERGENCY_HOLD_SECONDS = 2.5

-- "4 u 20 min" of "35 min".
local function formatDuration(secs)
    local hours, minutes = ReadingTime.split(secs)
    if hours > 0 then
        return T(_("%1 u %2 min"), hours, string.format("%02d", minutes))
    end
    return T(_("%1 min"), minutes)
end

--[[--
Blok voor een map op het homescreen: stapel omslagen (Widgets.coverStack) met de naam
eronder; zonder omslagen een klein mapicoon. Een tik roept callback() aan.
]]
local CollectionTile = InputContainer:extend{
    title = nil,
    covers = nil,       -- BlitBuffers (voorste eerst), of leeg
    width = nil,
    stack_w = nil,
    stack_h = nil,
    callback = nil,
}

function CollectionTile:init()
    local stack = Widgets.coverStack(self.covers, self.stack_w, self.stack_h)
        or CenterContainer:new{
            dimen = Geom:new{ w = self.stack_w, h = self.stack_h },
            Widgets.icon({ icon_file = "folder.svg" }, math.floor(math.min(self.stack_w, self.stack_h) * 0.4)),
        }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = self.stack_h + Size.padding.large + Screen:scaleBySize(24) },
        ignore = "height",
        VerticalGroup:new{
            align = "center",
            stack,
            VerticalSpan:new{ width = Size.padding.large },
            TextWidget:new{
                text = self.title,
                face = Font:getFace("cfont", 16),
                bold = true,
                max_width = self.width,
            },
        },
    }
    self.ges_events = {
        TapTile = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function CollectionTile:onTapTile()
    if self.callback then Widgets.safeCall("map " .. tostring(self.title), self.callback) end
    return true
end

local HomeScreen = InputContainer:extend{
    fm = nil,               -- FileManager-instantie
    library = nil,          -- app/library_service (mappen in de catalogus)
    collections = nil,      -- namen van mappen voor de blokken (config.collections)
    on_open_collection = nil, -- function(adres, naam)
    nav = nil,              -- { home = fn, library = fn, settings = fn }, zie Widgets.mainNav
    on_emergency = nil,
    on_closed = nil,
    covers_fullscreen = true,
    -- Niet modal: anders komen dialogen van KOReader (bijv. MultiInputDialog) eronder
    -- (UIManager:show zet niet-modale vensters onder het bovenste modale venster).
    stop_events_propagation = true,
}
Widgets.guardPaint(HomeScreen, "homescreen")
Widgets.guardEvents(HomeScreen, "homescreen")
Widgets.followRotation(HomeScreen)

function HomeScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.book = Books.currentBook(self.fm)
    if self.book then
        self.book.stats = ReadingTime.estimate(Books.stats(self.fm, self.book.file), self.book.percent)
    end
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
Statusregel: "Lingering" links; rechts lamp en wifi (aantikbaar), tijd, batterij-icoon en
batterij in procenten.
De iconen blijven bestaan; refreshStatus werkt ze en de teksten ter plekke bij.
]]
function HomeScreen:buildStatus(width)
    local padding = Size.padding.large * 2
    local face = Font:getFace("cfont", 16)
    local height = Screen:scaleBySize(60)
    local inner = Geom:new{ w = width - 2 * padding, h = height }
    local Item = require("lingering.ui.actionbar").Item

    -- Ruim tikvlak per icoon (de hele hoogte van de statusregel).
    local function item(action)
        return Item:new{
            action = action,
            width = height,
            height = height,
            icon_size = Screen:scaleBySize(30),
            show_parent = self,
        }
    end

    self.light_item = item{
        name = "licht",
        switch = true,
        icon_on = "light_mode.svg",
        icon_off = "dark_mode.svg",
        enabled = Device:hasFrontlight(),
        state = DeviceAdapter.isFrontlightOn(),
        on_toggle = function(on)
            logger.info("Lingering: homescreen, licht", on and "aan" or "uit")
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
            logger.info("Lingering: homescreen, wifi", on and "aan" or "uit")
            Network.setWifi(on, function()
                self.wifi_item:setState(Network.isWifiOn())
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
        HorizontalSpan:new{ width = 0 },               -- batterij-icoon
        HorizontalSpan:new{ width = 0 },               -- ruimte tussen icoon en getal
        TextWidget:new{ text = "", face = face },      -- batterij in procenten
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
    local battery = DeviceAdapter.batteryPercent()
    self.status_right[4] = TextWidget:new{ text = time, face = self.status_face }
    if battery then
        self.status_right[6] = Widgets.battery(battery, DeviceAdapter.isCharging())
        self.status_right[7] = HorizontalSpan:new{ width = Size.padding.default }
    end
    self.status_right[8] = TextWidget:new{ text = battery and T(_("%1%"), battery) or "", face = self.status_face }
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
            Widgets.icon({ icon_file = "menu_book.svg" }, math.floor(cover_w / 2)),
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
        -- Lichtgrijze baan, gelezen deel donkergrijs, geen rand.
        bordersize = 0,
        bgcolor = Blitbuffer.COLOR_LIGHT_GRAY,
        fillcolor = Blitbuffer.COLOR_DARK_GRAY,
    })
    table.insert(info, VerticalSpan:new{ width = Size.padding.default })
    -- Met de statistics-plugin aan: resterende en gelezen tijd; anders het percentage.
    local stats = self.book.stats
    local line
    if stats then
        line = T(_("Nog ± %1 · %2 gelezen"), formatDuration(stats.left_secs), formatDuration(stats.read_secs))
    else
        line = T(_("%1% gelezen"), math.floor(percent * 100 + 0.5))
    end
    table.insert(info, TextBoxWidget:new{
        text = line,
        face = Font:getFace("cfont", 18),
        width = text_w,
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

    local nav = Widgets.mainNav(width, self.nav, "home")

    local status = self:buildStatus(width)
    local status_h = status:getSize().h
    local area_h = height - status_h - nav:getSize().h

    -- Blokken met mappen (stapels omslagen) onder het huidige boek, als ze passen.
    local shelf = self:buildCollections(width)
    local shelf_h = shelf and shelf:getSize().h or 0
    if shelf and area_h - shelf_h < Screen:scaleBySize(240) then
        shelf, shelf_h = nil, 0
    end
    local book_h = area_h - shelf_h
    local book = self:buildBook(width, book_h)
    local card_h = math.min(book:getSize().h, book_h)

    self.status_dimen = Geom:new{ x = 0, y = 0, w = width, h = status_h }
    self.book_dimen = Geom:new{ x = 0, y = status_h, w = width, h = card_h }
    self.shelf_dimen = Geom:new{ x = 0, y = status_h + card_h, w = width, h = shelf_h }

    -- Statusregel boven (zonder lijn), huidig boek, mappen, navigatiebalk onderaan.
    self.layout_group = VerticalGroup:new{
        align = "left",
        status,
        book,
    }
    if shelf then table.insert(self.layout_group, shelf) end
    table.insert(self.layout_group, VerticalSpan:new{ width = math.max(0, area_h - card_h - shelf_h) })
    table.insert(self.layout_group, nav)
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.layout_group,
    }
end

--[[--
Blokken naast elkaar voor de mappen uit config.collections (alleen mappen die in de
catalogus bestaan): stapel van de eerste drie omslagen uit de cache, naam eronder.
]]
function HomeScreen:buildCollections(width)
    if not (self.library and self.collections) then return nil end
    local found = {}
    for _, title in ipairs(self.collections) do
        local ok, url = pcall(self.library.collectionUrl, self.library, title)
        if ok and url then table.insert(found, { title = title, url = url }) end
    end
    if #found == 0 then return nil end

    local padding = Size.padding.large * 2
    local gap = Size.padding.large * 2
    local tile_w = math.floor((width - 2 * padding - (#found - 1) * gap) / #found)
    -- Stapel: omslag hooguit 40% van de blokbreedte.
    local cover_w = math.floor(tile_w * 0.4)
    local cover_h = math.floor(cover_w * 3 / 2)
    local stack_w, stack_h = Widgets.stackSize(cover_w, cover_h)

    local row = HorizontalGroup:new{ align = "top" }
    for i, collection in ipairs(found) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        local covers = {}
        local ok, books = pcall(self.library.collectionBooks, self.library, collection.title)
        for _, entry in ipairs(ok and books or {}) do
            local bb = entry.thumbnail and Widgets.loadCover(self.library, entry.thumbnail, cover_w, cover_h)
            if bb then table.insert(covers, bb) end
            if #covers == 3 then break end
        end
        table.insert(row, CollectionTile:new{
            title = collection.title,
            covers = covers,
            width = tile_w,
            stack_w = stack_w,
            stack_h = stack_h,
            show_parent = self,
            callback = function()
                logger.info("Lingering: homescreen, map", collection.title)
                if self.on_open_collection then self.on_open_collection(collection.url, collection.title) end
            end,
        })
    end
    return FrameContainer:new{
        padding = 0,
        padding_left = padding,
        padding_right = padding,
        padding_bottom = padding,
        bordersize = 0,
        row,
    }
end

--[[--
Met verbinding: mappen verversen (hooguit eens per tien minuten) en hun eerste omslagen
ophalen; daarna alleen het deel onder het huidige boek opnieuw tekenen.
]]
function HomeScreen:refreshCollections()
    if self.closed or not (self.library and self.collections) or not Network.isOnline() then return end
    self.library:refreshCollections(self.collections, function(changed)
        if self.closed or not changed then return end
        self:build()
        UIManager:setDirty(self, "ui", Geom:new{
            x = 0, y = self.book_dimen.y, w = self.dimen.w, h = self.dimen.h - self.book_dimen.y,
        })
    end)
end

function HomeScreen:onTapBook()
    if self.book then
        logger.info("Lingering: homescreen, boek openen")
        local file = self.book.file
        self:close()
        Navigation.openBook(file)
    else
        Widgets.safeCall("mijn boeken", self.nav.library)
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
    self.wifi_item:setState(Network.isWifiOn())
    self.light_item:setState(DeviceAdapter.isFrontlightOn())
    UIManager:setDirty(self, "ui", self.status_dimen)
end
-- Licht veranderd (hier, in Instellingen of in KOReaders helderheidsscherm).
function HomeScreen:onFrontlightStateChanged()
    if self.light_item then self.light_item:setState(DeviceAdapter.isFrontlightOn()) end
end

HomeScreen.onResume = HomeScreen.refreshStatus
HomeScreen.onNetworkConnected = HomeScreen.refreshStatus
HomeScreen.onNetworkDisconnected = HomeScreen.refreshStatus
-- Lader in of uit (Device:_beforeCharging / _afterNotCharging).
HomeScreen.onCharging = HomeScreen.refreshStatus
HomeScreen.onNotCharging = HomeScreen.refreshStatus

-- Een andere route opent een boek (bijv. de OPDS-browser): dan gaan wij ook weg.
function HomeScreen:onShowingReader()
    self:close()
end

function HomeScreen:onCloseWidget()
    self.closed = true
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
    UIManager:scheduleIn(1, function()
        Widgets.safeCall("mappen verversen", function() self:refreshCollections() end)
    end)
end

function HomeScreen:close()
    self.closed = true
    UIManager:close(self, "full")
end

return HomeScreen
