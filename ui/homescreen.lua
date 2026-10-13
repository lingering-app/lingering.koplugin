--[[--
Homescreen: statusregel, huidig boek eronder, navigatiebalk onderaan
(Mijn boeken, Instellingen).
Ligt schermvullend over de bestandsbeheerder; vangt alle gebaren af, zodat het menu
van de bestandsbeheerder niet open kan.
]]
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
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("lingering.l10n.gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local Books = require("lingering.koreader.books")
local ReadingTime = require("lingering.domain.reading_time")
local Navigation = require("lingering.koreader.navigation")
local Network = require("lingering.koreader.network")
local Widgets = require("lingering.ui.widgets")
local Style = require("lingering.ui.style")

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

-- Afgerond op hele uren ("7 uur"); onder het half uur in minuten ("20 min").
local function formatHours(secs)
    local hours = math.floor((secs or 0) / 3600 + 0.5)
    if hours == 1 then
        -- Apart, omdat het Engels een meervoud heeft (1 hour, 7 hours).
        return _("1 uur")
    elseif hours > 1 then
        return T(_("%1 uur"), hours)
    end
    return formatDuration(secs)
end


-- "⋮"-knop voor het menu van een boek; on_tap(anchor) krijgt de positie van de knop.
-- ink_right: afstand van de linkerkant van de knop tot de rechterkant van de puntjes (het
-- icoon heeft rechts 42% lege ruimte), om de puntjes tegen een rand uit te lijnen.
-- more_vert.svg is gewicht 700 (dikgedrukt), de andere iconen 300.
local function moreButton(on_tap)
    local Item = require("lingering.ui.actionbar").Item
    local icon_size = Screen:scaleBySize(20)
    local button = Item:new{
        action = {
            icon_file = "more_vert.svg",
            tap = function(item) on_tap(item.dimen) end,
        },
        width = Screen:scaleBySize(32),
        height = Screen:scaleBySize(40),
        icon_size = icon_size,
    }
    button.ink_right = math.floor(button.width / 2 + icon_size / 2 - icon_size * 0.42)
    return button
end

--[[--
Tegel in het raster "aan het lezen" (twee of meer boeken): omslag, "X% gelezen" en
lichter de resterende tijd (als de statistics-plugin aan staat). Een tik roept callback() aan.
]]
local ReadingTile = InputContainer:extend{
    book = nil,         -- { file, title, percent, cover, stats }
    width = nil,
    cover_w = nil,
    cover_h = nil,
    callback = nil,
    on_menu = nil,      -- function(anchor): menu van de "…"-knop
}

function ReadingTile:init()
    local book = self.book
    local cover
    if book.cover then
        -- Schalen met behoud van de eigen verhouding, onderaan uitgelijnd in het omslagvak.
        local bb = book.cover
        local scale = math.min(self.cover_w / bb:getWidth(), self.cover_h / bb:getHeight())
        cover = ImageWidget:new{
            image = bb,
            -- Zelf vrijgeven in HomeScreen:onCloseWidget: de omslag mag een herbouw overleven.
            image_disposable = false,
            width = math.floor(bb:getWidth() * scale),
            height = math.floor(bb:getHeight() * scale),
            scale_factor = 0,
        }
    else
        cover = Widgets.icon({ icon_file = "menu_book.svg" }, math.floor(self.cover_w / 2))
    end
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    -- Onder de omslag: teksten links en "⋮" rechts, precies zo breed als de omslag zelf
    -- (de omslag staat gecentreerd in de tegel).
    local more = moreButton(function(anchor) if self.on_menu then self.on_menu(anchor) end end)
    local cover_w = cover:getSize().w
    local left = math.floor((self.width - cover_w) / 2)
    local texts_w = cover_w - more.width
    local texts = VerticalGroup:new{
        align = "left",
        TextWidget:new{
            text = T(_("%1% gelezen"), math.floor((book.percent or 0) * 100 + 0.5)),
            face = Font:getFace("cfont", 15),
            bold = true,
            max_width = texts_w,
        },
    }
    if book.stats then
        table.insert(texts, TextWidget:new{
            text = T(_("%1 te gaan"), formatHours(book.stats.left_secs)),
            face = Font:getFace("cfont", 13),
            fgcolor = Style.text_secondary,
            max_width = texts_w,
        })
    end
    texts.overlap_offset = { left, 0 }
    -- ⋮ verticaal gecentreerd naast de twee regels, puntjes tegen de rechterrand van de omslag.
    local texts_h = texts:getSize().h
    -- Met een kleine verschuiving: iets lager en iets naar links (op het oog).
    local more_y = math.floor((texts_h - more.height) / 2) + Screen:scaleBySize(8)
    more.overlap_offset = { left + cover_w - more.ink_right - Screen:scaleBySize(3), more_y }
    local row = OverlapGroup:new{
        dimen = Geom:new{ w = self.width, h = math.max(texts_h, more.height) },
        texts,
        more,
    }
    self[1] = VerticalGroup:new{
        align = "center",
        BottomContainer:new{ dimen = Geom:new{ w = self.width, h = self.cover_h }, cover },
        VerticalSpan:new{ width = Size.padding.default },
        row,
    }
    self.ges_events = {
        TapTile = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function ReadingTile:onTapTile()
    if self.callback then Widgets.safeCall("boek " .. tostring(self.book.title), self.callback) end
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

-- Eén boek aan het lezen: de grote kaart (self.book); meer: een rij van hooguit 4.
function HomeScreen:loadBooks()
    self.books = Books.readingBooks(self.fm, 4)
    for _, book in ipairs(self.books) do
        book.stats = ReadingTime.estimate(Books.stats(self.fm, book.file), book.percent)
    end
    self.book = #self.books == 1 and self.books[1] or nil
end

local function freeCovers(books)
    for _, book in ipairs(books or {}) do
        if book.cover then
            book.cover:free()
            book.cover = nil
        end
    end
end

--- Boeken opnieuw laden en het scherm herbouwen (na "Gelezen" in het menu).
function HomeScreen:reloadBooks()
    if self.closed then return end
    freeCovers(self.books)
    self:loadBooks()
    self:build()
    UIManager:setDirty(self, "ui")
end

--- Menu van de "…"-knop op een boek (ui/popover_menu.lua).
function HomeScreen:showBookMenu(book, anchor)
    require("lingering.ui.popover_menu").show{
        anchor = anchor,
        items = {
            {
                text = _("Gelezen"),
                callback = function()
                    logger.info("Lingering: homescreen, gelezen:", book.title)
                    require("lingering.app.sync_service").markFinished(book.file, function()
                        self:reloadBooks()
                    end)
                end,
            },
        },
    }
end

function HomeScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self:loadBooks()
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

-- Statusregel bovenaan (ui/statusbar.lua): "Lingering", licht, wifi, tijd, batterij;
-- werkt zichzelf bij.
function HomeScreen:buildStatus(width)
    self.status_bar = require("lingering.ui.statusbar"):new{
        width = width,
        show_parent = self,
        title = "Lingering",
    }
    return self.status_bar
end

-- Tegels voor de rij van hooguit 4 boeken die je aan het lezen bent (4 kolommen); geeft de
-- tegels en hun hoogte.
function HomeScreen:readingTiles(width, height)
    local Grid = require("lingering.ui.grid")
    local tile_w = Grid.columnWidth(width, 4)
    local cover_w = tile_w
    local cover_h = math.floor(cover_w * 3 / 2)
    -- Ruimte voor de twee regels onder de omslag; de omslag krimpt als het niet past.
    local text_h = Screen:scaleBySize(15 + 13) + 3 * Size.padding.default
    if cover_h > height - text_h then
        cover_h = math.max(0, height - text_h)
        cover_w = math.floor(cover_h * 2 / 3)
    end
    local tiles, tiles_h = {}, 0
    for _, book in ipairs(self.books) do
        local tile = ReadingTile:new{
            book = book,
            width = tile_w,
            cover_w = cover_w,
            cover_h = cover_h,
            callback = function()
                logger.info("Lingering: homescreen, boek openen")
                self:close()
                Navigation.openBook(book.file)
            end,
            on_menu = function(anchor) self:showBookMenu(book, anchor) end,
        }
        tiles_h = math.max(tiles_h, tile:getSize().h)
        table.insert(tiles, tile)
    end
    return tiles, tiles_h
end

--- Rij 1 van het raster: { columns, cells } en de hoogte. Meer boeken: 4 kolommen; anders de
--- grote kaart of de melding "nog geen boek" over 1 kolom.
function HomeScreen:bookRow(width, height)
    if #self.books > 1 then
        local tiles, h = self:readingTiles(width, height)
        return { columns = 4, cells = tiles }, h
    end
    local Grid = require("lingering.ui.grid")
    local card = self:buildBook(Grid.columnWidth(width, 1), height)
    return { columns = 1, cells = { card } }, math.min(card:getSize().h, height)
end

-- De grote kaart (of "nog geen boek") voor één kolom van width breed; de marges komen uit het
-- raster, padding is alleen de ruimte tussen omslag en tekst.
function HomeScreen:buildBook(width, height)
    local padding = require("lingering.ui.grid").GUTTER
    local inner_w = width

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
    local cover_h = height
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
        -- Baan en gelezen deel uit Style.progress, geen rand.
        bordersize = 0,
        bgcolor = Style.progress.track,
        fillcolor = Style.progress.fill,
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

    local card = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        HorizontalGroup:new{
            align = "center",
            cover,
            HorizontalSpan:new{ width = padding },
            info,
        },
    }
    -- "⋮"-knop rechtsonder in de kaart (puntjes tegen de rechterrand van de inhoud), voor het
    -- menu van het boek.
    local book = self.book
    local more = moreButton(function(anchor) self:showBookMenu(book, anchor) end)
    local size = card:getSize()
    more.overlap_offset = { width - more.ink_right, size.h - more.height }
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = size.h },
        card,
        more,
    }
end

function HomeScreen:build()
    local Grid = require("lingering.ui.grid")
    local width, height = self.dimen.w, self.dimen.h

    local nav = Widgets.mainNav(width, self.nav, "home")
    local status = self:buildStatus(width)
    local status_h = status:getSize().h
    local area_h = height - status_h - nav:getSize().h

    -- Eén raster (ui/grid.lua): rij 1 het boek (grote kaart, 1 kolom) of de boeken (4 kolommen),
    -- rij 2 de mappen (2 kolommen) als die passen.
    local folders, folders_h = self:collectionRow(width, area_h)
    folders_h = folders_h or 0
    local book_h = area_h - Grid.rowsHeight({ 0 }) - (folders and folders_h + Grid.ROW_GAP or 0)
    if folders and book_h < Screen:scaleBySize(240) then
        folders, folders_h = nil, 0
        book_h = area_h - Grid.rowsHeight({ 0 })
    end
    local books, books_h = self:bookRow(width, book_h)
    local rows = { books }
    if folders then table.insert(rows, folders) end
    local grid = Grid.rows(width, rows)

    self.status_dimen = Geom:new{ x = 0, y = 0, w = width, h = status_h }
    self.book_dimen = Geom:new{ x = Grid.MARGIN, y = status_h + Grid.MARGIN, w = Grid.columnWidth(width, 1), h = books_h }
    self.shelf_dimen = Geom:new{
        x = 0, y = status_h + Grid.MARGIN + books_h + Grid.ROW_GAP, w = width, h = folders_h,
    }

    -- Statusregel boven (zonder lijn), het raster, ruimte, navigatiebalk onderaan.
    self.layout_group = VerticalGroup:new{
        align = "left",
        status,
        grid,
        VerticalSpan:new{ width = math.max(0, area_h - grid:getSize().h) },
        nav,
    }
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Style.background,
        self.layout_group,
    }
end

--[[--
Blokken naast elkaar voor de mappen uit config.collections (alleen mappen die in de
catalogus bestaan): stapel van de eerste drie omslagen uit de cache, naam eronder.
]]
--- Rij 2 van het raster: de mappen (2 kolommen) en hun hoogte, of nil.
function HomeScreen:collectionRow(width, area_h)
    if not (self.library and self.collections) then return nil end
    local found = {}
    for _, title in ipairs(self.collections) do
        local ok, url = pcall(self.library.collectionUrl, self.library, title)
        if ok and url then table.insert(found, { title = title, url = url }) end
    end
    if #found == 0 then return nil end

    -- Zelfde maat en plek als de mappen in Mijn boeken: 2 kolommen op het raster (ui/grid.lua),
    -- waaier volgens Widgets.folderStackSize met dezelfde beschikbare hoogte.
    local Grid = require("lingering.ui.grid")
    local tile_w = Grid.columnWidth(width, 2)
    local _, _, stack_w, stack_h = Widgets.folderStackSize(tile_w, area_h)

    -- Zelfde tegel als in Mijn boeken (ui/folder_tile.lua).
    local FolderTile = require("lingering.ui.folder_tile")
    local tiles = {}
    for _, collection in ipairs(found) do
        table.insert(tiles, FolderTile:new{
            library = self.library,
            url = collection.url,
            title = collection.title,
            width = tile_w,
            stack_w = stack_w,
            stack_h = stack_h,
            callback = function()
                logger.info("Lingering: homescreen, map", collection.title)
                if self.on_open_collection then self.on_open_collection(collection.url, collection.title) end
            end,
        })
    end
    return { columns = 2, cells = tiles }, FolderTile.height(stack_h)
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
    -- Raster: de tegels handelen hun eigen tik af; daartussen gebeurt niets.
    if #self.books > 1 then return true end
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
    freeCovers(self.books)
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
