--[[--
Mijn boeken: de OPDS-catalogus als raster met omslagen, in pagina's: zijwaarts vegen (naar
links: volgende, naar rechts: vorige, zoals in een boek) of de pijltjes onderaan
("‹ 3 / 25 ›", vanaf 6 pagina's ook « en » naar de eerste en laatste). Alleen de huidige pagina wordt gebouwd, ook bij een map met honderden boeken.

- Toont meteen de gecachete versie (ook zonder wifi).
- Synchroniseren alleen met de sync-knop (zet zo nodig wifi aan): de huidige map, de mappen
  op deze pagina, de ontbrekende omslagen en de leestijd van alle apparaten
  (app/stats_service.lua). Verder haalt het scherm zelf niets op.
- Mappen uit de catalogus openen met een terugknop; elke map wordt apart gecachet.
- Tik op een boek: staat het op het apparaat, dan openen; anders downloaden en openen.
]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("lingering.l10n.gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local Network = require("lingering.koreader.network")
local BookOpener = require("lingering.ui.book_opener")
local Widgets = require("lingering.ui.widgets")
local FolderTile = require("lingering.ui.folder_tile")
local Grid = require("lingering.ui.grid")
local Layout = require("lingering.domain.layout")
local Style = require("lingering.ui.style")

-- Onderaan bij meer dan één pagina: "‹ 3 / 25 ›", pijltjes om te bladeren, nummer klein en grijs.
local PAGE_NUMBER_FACE = Font:getFace("cfont", 13)
local PAGER_H = Screen:scaleBySize(44)
local PAGER_BUTTON_W = Screen:scaleBySize(56)
local PAGER_ICON = Screen:scaleBySize(24)
-- Vanaf zoveel pagina's ook « en » (naar de eerste en de laatste pagina).
local PAGER_JUMP_FROM = 6

local function loadCover(library, url, w, h)
    return Widgets.loadCover(library, url, w, h)
end

--[[--
Eén boek in het raster: de omslag, of zonder omslag de titel (en auteur) in een vak van
omslaggrootte. Mappen zijn een FolderTile (ui/folder_tile.lua).
]]
local GridTile = InputContainer:extend{
    entry = nil,
    library = nil,
    width = nil,
    height = nil,
    cover_w = nil,
    cover_h = nil,
    callback = nil,
}

function GridTile:init()
    local entry = self.entry
    local cover_w, cover_h = self.cover_w, self.cover_h

    local cover
    do
        local bb = entry.thumbnail and loadCover(self.library, entry.thumbnail, cover_w, cover_h)
        if bb then
            -- Schalen met behoud van verhouding, onderaan uitgelijnd zoals op een plank.
            local scale = math.min(cover_w / bb:getWidth(), cover_h / bb:getHeight())
            local w, h = math.floor(bb:getWidth() * scale), math.floor(bb:getHeight() * scale)
            cover = ImageWidget:new{ image = bb, image_disposable = true, width = w, height = h, scale_factor = 0 }
        else
            -- Geen omslag: titel (en auteur) in een vak van omslaggrootte.
            local inner_w = cover_w - 2 * Style.cover_border.size - 2 * Size.padding.default
            local label = VerticalGroup:new{
                align = "center",
                TextBoxWidget:new{
                    text = entry.title,
                    face = Font:getFace("cfont", 16),
                    bold = true,
                    width = inner_w,
                    alignment = "center",
                    height = math.floor(cover_h * 0.6),
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                },
            }
            if entry.author then
                table.insert(label, VerticalSpan:new{ width = Size.padding.default })
                table.insert(label, TextBoxWidget:new{
                    text = entry.author,
                    face = Font:getFace("cfont", 13),
                    fgcolor = Style.text_secondary,
                    width = inner_w,
                    alignment = "center",
                    height = math.floor(cover_h * 0.25),
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                })
            end
            cover = FrameContainer:new{
                width = cover_w, height = cover_h,
                padding = 0,
                bordersize = Style.cover_border.size,
                color = Style.cover_border.color,
                CenterContainer:new{
                    dimen = Geom:new{ w = cover_w - 2 * Style.cover_border.size, h = cover_h - 2 * Style.cover_border.size },
                    label,
                },
            }
        end
    end

    local cover_size = cover:getSize()
    local cover_area = OverlapGroup:new{
        dimen = Geom:new{ w = cover_w, h = cover_h },
    }
    local placed = CenterContainer:new{
        dimen = Geom:new{ w = cover_size.w, h = cover_size.h },
        cover,
    }
    placed.overlap_offset = { math.floor((cover_w - cover_size.w) / 2), cover_h - cover_size.h }
    table.insert(cover_area, placed)

    -- Alleen de omslag (de titel staat er meestal op).
    local content = VerticalGroup:new{ align = "center", cover_area }
    -- Alleen horizontaal centreren: alles staat bovenaan op één lijn.
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        ignore = "height",
        content,
    }
    self.ges_events = {
        TapTile = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
    }
end

function GridTile:onTapTile()
    if self.callback then
        Widgets.safeCall("boek of map", self.callback, self.entry)
    end
    return true
end

local LibraryScreen = InputContainer:extend{
    fm = nil,               -- FileManager-instantie (voor de leestijd, app/stats_service.lua)
    library = nil,
    on_open_book = nil,     -- function(path)
    start = nil,            -- optioneel { url, title }: in deze map beginnen
    covers_fullscreen = true,
    stop_events_propagation = true,
}
Widgets.guardPaint(LibraryScreen, "mijn boeken")
Widgets.guardEvents(LibraryScreen, "mijn boeken")
Widgets.followRotation(LibraryScreen)

function LibraryScreen:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    -- Start in een map (bijv. vanaf een blok op het homescreen); terug sluit dan het scherm.
    self.stack = { self.start or { url = self.library:rootUrl(), title = _("Mijn boeken") } }
    self.cover_failed = {}

    self:buildHeader()
    -- Navigatiebalk: Mijn boeken staat vet; een tik erop gaat terug naar het begin.
    self.nav_bar = Widgets.mainNav(width, self.nav, "library", function() self:goToRoot() end)
    self.nav_h = self.nav_bar:getSize().h
    self.ges_events = {
        Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.body_dimen end } },
    }
    self:render()
end

-- Zijwaarts vegen, zoals in een boek: naar links de volgende pagina, naar rechts de vorige.
function LibraryScreen:onSwipe(_, ges)
    local direction = ges and ges.direction
    if direction == "west" then
        self:turnPage(1)
    elseif direction == "east" then
        self:turnPage(-1)
    end
    return true
end

-- "‹ 3 / 25 ›" onderaan, vanaf PAGER_JUMP_FROM pagina's "« ‹ 3 / 25 › »": pijltjes (grijs en
-- zonder werking op de eerste/laatste pagina).
function LibraryScreen:pager(width, page, pages)
    local Item = require("lingering.ui.actionbar").Item
    local function arrow(icon_file, target, enabled)
        return Item:new{
            action = { name = "pagina", icon_file = icon_file, enabled = enabled },
            on_tap = function() self:goToPage(target) end,
            width = PAGER_BUTTON_W,
            height = PAGER_H,
            icon_size = PAGER_ICON,
            show_parent = self,
        }
    end
    local jump = pages >= PAGER_JUMP_FROM
    local row = HorizontalGroup:new{ align = "center" }
    if jump then table.insert(row, arrow("keyboard_double_arrow_left.svg", 1, page > 1)) end
    table.insert(row, arrow("chevron_left.svg", page - 1, page > 1))
    table.insert(row, TextWidget:new{
        text = T("%1 / %2", page, pages),
        face = PAGE_NUMBER_FACE,
        fgcolor = Style.text_secondary,
    })
    table.insert(row, arrow("chevron_right.svg", page + 1, page < pages))
    if jump then table.insert(row, arrow("keyboard_double_arrow_right.svg", pages, page < pages)) end
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = PAGER_H }, row }
end

function LibraryScreen:turnPage(delta)
    self:goToPage((self:current().page or 1) + delta)
end

function LibraryScreen:goToPage(page)
    local current = self:current()
    page = math.max(1, math.min(page, self.page_count or 1))
    if page == (current.page or 1) then return end
    current.page = page
    self:render(true)
end

function LibraryScreen:goToRoot()
    if #self.stack == 1 and self.stack[1].url == self.library:rootUrl() then return end
    self.stack = { { url = self.library:rootUrl(), title = _("Mijn boeken") } }
    self:render()
end

function LibraryScreen:current()
    return self.stack[#self.stack]
end

-- Titelbalk: terug, titel, sync. Eén keer gebouwd, zodat een draaiend sync-icoon blijft.
-- Bovenkant: statusbalk (met de sync-knop) en titelbalk (terug, titel), Widgets.pageHeader.
-- Eén keer gebouwd, zodat een draaiend sync-icoon blijft.
function LibraryScreen:buildHeader()
    self.header = Widgets.pageHeader{
        width = self.dimen.w,
        on_back = function() self:goBack() end,
        show_parent = self,
        extra = {
            {
                name = "mijn boeken synchroniseren",
                task = true,
                icon_file = "sync.svg",
                frames = { "sync-45.svg", "sync-90.svg", "sync-135.svg", "sync.svg" },
                run = function(done) self:syncCurrent(done) end,
            },
        },
    }
    -- De sync-knop is het eerste icoon van de statusbalk.
    self.sync_item = self.header.status_bar.items[1]
    self.header_h = self.header.height
end

function LibraryScreen:setTitle(title)
    self.header:setTitle(title)
end

function LibraryScreen:message(text, width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        TextBoxWidget:new{
            text = text,
            face = Font:getFace("cfont", 20),
            width = width - 4 * Size.padding.large,
            alignment = "center",
        },
    }
end

-- partial = true: alleen het raster verversen (omslagen binnen, sync klaar); anders het
-- hele scherm (andere map).
function LibraryScreen:render(partial)
    local width, height = self.dimen.w, self.dimen.h
    local current = self:current()
    self:setTitle(current.title)

    local body_h = height - self.header_h - self.nav_h
    -- Ruimte voor rijen op een pagina: onderaan dezelfde marge als bovenaan.
    local page_h = body_h - Grid.MARGIN
    -- Raster (ui/grid.lua): mappen in rijen van 2, boeken in rijen van 4, altijd dezelfde
    -- marges links en rechts.
    local feed = self.library:cached(current.url)
    local items = feed and feed.items

    -- Maten bij een bepaalde breedte van het raster.
    local function sizes(content_w)
        local z = {}
        -- Boeken: alleen de omslag; één rij moet altijd in beeld passen.
        z.book_w = Grid.columnWidth(content_w, 4)
        z.book_cover_w = z.book_w
        z.book_cover_h = math.floor(z.book_cover_w * 3 / 2)
        local max_cover_h = body_h - Grid.MARGIN - Grid.ROW_GAP
        if z.book_cover_h > max_cover_h then
            z.book_cover_h = max_cover_h
            z.book_cover_w = math.floor(z.book_cover_h * 2 / 3)
        end
        -- Past er bijna een rij bij, dan de omslagen iets kleiner (geen half lege pagina).
        local _, fitted_h = Layout.fitRows(page_h, z.book_cover_h, Grid.ROW_GAP, Grid.MARGIN)
        if fitted_h < z.book_cover_h then
            z.book_cover_h = fitted_h
            z.book_cover_w = math.floor(fitted_h * 2 / 3)
        end
        z.book_tile_h = z.book_cover_h
        -- Mappen: waaier zoals op het homescreen (Widgets.folderStackSize).
        z.folder_w = Grid.columnWidth(content_w, 2)
        local _
        _, _, z.stack_w, z.stack_h = Widgets.folderStackSize(z.folder_w, body_h)
        z.folder_tile_h = FolderTile.height(z.stack_h)
        return z
    end

    -- Opeenvolgende mappen in rijen van 2, opeenvolgende boeken in rijen van 4.
    local rows = {}
    for _, entry in ipairs(items or {}) do
        local columns = entry.kind == "folder" and 2 or 4
        local last = rows[#rows]
        if not last or last.kind ~= entry.kind or #last.entries >= columns then
            last = { kind = entry.kind, columns = columns, entries = {} }
            table.insert(rows, last)
        end
        table.insert(last.entries, entry)
    end
    local function rowHeights(z)
        local heights = {}
        for _, row in ipairs(rows) do
            table.insert(heights, row.kind == "folder" and z.folder_tile_h or z.book_tile_h)
        end
        return heights
    end
    -- Pagina's (domain/layout.lua): alleen de rijen van de huidige pagina worden gebouwd, dus
    -- een map met 300 boeken opent even snel als een kleine. Meer dan één pagina: onderaan het
    -- paginanummer; de rijen krijgen dan die hoogte minder.
    local content_w = width
    local number_h = PAGER_H
    local pages = Layout.pages(rowHeights(sizes(width)), page_h, Grid.MARGIN, Grid.ROW_GAP)
    if #pages > 1 then
        page_h = page_h - number_h
        pages = Layout.pages(rowHeights(sizes(width)), page_h, Grid.MARGIN, Grid.ROW_GAP)
    end
    local z = sizes(content_w)
    local book_w, book_cover_w, book_cover_h, book_tile_h = z.book_w, z.book_cover_w, z.book_cover_h, z.book_tile_h
    local folder_w, stack_w, stack_h, folder_tile_h = z.folder_w, z.stack_w, z.stack_h, z.folder_tile_h
    current.page = math.max(1, math.min(current.page or 1, #pages))
    self.page_count = #pages
    local page = pages[current.page]

    local body
    self.entries = items or {}
    self.body_dimen = Geom:new{ x = 0, y = self.header_h, w = width, h = body_h }
    if not items then
        body = self:message(self.sync_item.busy and _("Bezig met synchroniseren…")
            or _("Nog niets gesynchroniseerd.\nZet wifi aan en tik op het sync-icoon."), width, body_h)
    elseif #items == 0 then
        body = self:message(_("Geen boeken."), width, body_h)
    else
        local grid_rows = {}
        for r = page.first, page.last do
            local row = rows[r]
            local cells = {}
            for _, entry in ipairs(row.entries) do
                if entry.kind == "folder" then
                    -- Zelfde tegel als de mapblokken op het homescreen.
                    table.insert(cells, TopContainer:new{
                        dimen = Geom:new{ w = folder_w, h = folder_tile_h },
                        FolderTile:new{
                            library = self.library,
                            url = entry.url,
                            title = entry.title,
                            width = folder_w,
                            stack_w = stack_w,
                            stack_h = stack_h,
                            callback = function() self:openEntry(entry) end,
                        },
                    })
                else
                    table.insert(cells, GridTile:new{
                        entry = entry,
                        library = self.library,
                        width = book_w,
                        height = book_tile_h,
                        cover_w = book_cover_w,
                        cover_h = book_cover_h,
                        show_parent = self,
                        callback = function(e) self:openEntry(e) end,
                    })
                end
            end
            table.insert(grid_rows, { columns = row.columns, cells = cells })
        end
        body = Grid.rows(content_w, grid_rows)
        if #pages > 1 then
            body = VerticalGroup:new{
                align = "center",
                TopContainer:new{ dimen = Geom:new{ w = width, h = body_h - number_h }, body },
                self:pager(width, current.page, #pages),
            }
        end
    end

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Style.background,
        VerticalGroup:new{
            align = "left",
            self.header,
            TopContainer:new{ dimen = Geom:new{ w = width, h = body_h }, body },
            self.nav_bar,
        },
    }
    if partial then
        UIManager:setDirty(self, "ui", Geom:new{ x = 0, y = self.header_h, w = width, h = body_h })
    else
        UIManager:setDirty(self, "ui")
    end
end

--[[--
Sync-knop, na de huidige map: de mappen op deze pagina opnieuw ophalen, plus hun eerste
omslagen (in de achtergrond), zodat de mapstapels en aantallen kloppen. done() als het klaar is.
]]
function LibraryScreen:syncFolders(done)
    local todo = {}
    for _, entry in ipairs(self.entries or {}) do
        if entry.kind == "folder" then table.insert(todo, entry.url) end
    end
    if #todo == 0 then return done() end
    local index = 0
    local wanted = {}
    local function covers_of(url)
        local feed = self.library:cached(url)
        local count = 0
        for _, item in ipairs(feed and feed.items or {}) do
            if item.kind == "book" and item.thumbnail then
                if not self.cover_failed[item.thumbnail] then table.insert(wanted, item.thumbnail) end
                count = count + 1
                if count == Widgets.COVER_MAX then break end
            end
        end
    end
    local function step()
        if self.closed then return done() end
        index = index + 1
        local url = todo[index]
        if not url then
            -- Omslagen van de mappen in de achtergrond; daarna één keer verversen.
            self:syncStep("covers")
            return self.library:fetchCoversAsync(wanted, function()
                if not self.closed then self:render(true) end
                done()
            end)
        end
        self:syncStep("books", T(_("Boeken ophalen (%1 van %2)"), index, #todo))
        -- Eerst het kader tekenen: ophalen blokkeert het scherm.
        UIManager:scheduleIn(0.05, function()
            if self.closed then return done() end
            self.library:sync(url, function()
                covers_of(url)
                UIManager:scheduleIn(0.05, step)
            end)
        end)
    end
    step()
end

function LibraryScreen:goBack()
    if #self.stack > 1 then
        table.remove(self.stack)
        self:render()
    else
        self:close()
    end
end

function LibraryScreen:openEntry(entry)
    if entry.kind == "folder" then
        table.insert(self.stack, { url = entry.url, title = entry.title })
        self:render()
    else
        BookOpener.open(self.library, entry, function(path) self:openBook(path) end)
    end
end

function LibraryScreen:openBook(path)
    logger.info("Lingering: mijn boeken, boek openen")
    self:close()
    if self.on_open_book then
        Widgets.safeCall("boek openen", self.on_open_book, path)
    end
end

-- Sync-knop (draaiend icoon): de huidige map, dan de mappen op deze pagina, de ontbrekende
-- omslagen en de leestijd. Het icoon draait tot alles klaar is; of de leestijd lukt, telt niet
-- mee voor het icoon (zonder stats-API op de server werkt Mijn boeken gewoon).
function LibraryScreen:syncCurrent(done)
    local url = self:current().url
    self.sync_status = require("lingering.ui.sync_status").new{
        anchor = function() return self.sync_item.dimen end,
        gap = self.header.status_bar.popover_gap,
        steps = {
            { id = "connect", label = _("Verbinden") },
            { id = "books", label = _("Boeken ophalen") },
            { id = "covers", label = _("Omslagen ophalen") },
            { id = "stats", label = _("Leestijd delen") },
        },
        -- Met de teller (mappen op de pagina) wordt die regel langer.
        widest = { T(_("Boeken ophalen (%1 van %2)"), 99, 99) },
    }
    local function finish(ok, reason)
        if not (self.closed or not self.sync_status) then
            if ok then self.sync_status:finish() else self.sync_status:fail(reason) end
        end
        done(ok)
    end
    self:syncStep("connect")
    local started = Network.turnOnWifiThen(function()
        self:syncStep("books")
        -- Eerst het kader tekenen: ophalen blokkeert het scherm.
        UIManager:scheduleIn(0.05, function()
            self.library:sync(url, function(ok)
                if self.closed then return done(ok) end
                self:render(true)
                if not ok then return finish(false, _("Server niet bereikbaar")) end
                self:syncFolders(function()
                    self:queueCovers(function()
                        self:syncStep("stats")
                        UIManager:scheduleIn(0.05, function()
                            Widgets.safeCall("leestijd delen", function()
                                require("lingering.app.stats_service").refresh(self.fm, function() end, { manual = true })
                            end)
                            finish(true)
                        end)
                    end)
                end)
            end)
        end)
    end)
    if not started then finish(false, _("Geen verbinding")) end
    if not self.library:cached(url) and not self.closed then
        self:render() -- toont "Bezig met synchroniseren…"
    end
end

-- Voortgang van de sync-knop: stap id in de lijst onder de knop (ui/sync_status.lua).
function LibraryScreen:syncStep(id, label)
    if self.closed or not self.sync_status then return end
    self.sync_status:start(id, label)
end

-- Sync-knop: ontbrekende omslagen van deze pagina in de achtergrond ophalen (subproces, zie
-- Library:fetchCoversAsync); als ze binnen zijn één keer het raster verversen. done() daarna.
function LibraryScreen:queueCovers(done)
    if self.closed or self.covers_loading then return done() end
    local missing = {}
    for _, entry in ipairs(self.entries or {}) do
        local url = entry.thumbnail
        if url and not self.cover_failed[url] and not self.library:hasCover(url) then
            table.insert(missing, url)
        end
    end
    if #missing == 0 then return done() end
    self:syncStep("covers")
    self.covers_loading = true
    self.library:fetchCoversAsync(missing, function(fetched)
        self.covers_loading = false
        -- Wat er dan nog niet is, niet opnieuw proberen in deze sessie van het scherm.
        for _, url in ipairs(missing) do
            if not self.library:hasCover(url) then self.cover_failed[url] = true end
        end
        if fetched > 0 and not self.closed then self:render(true) end
        done()
    end)
end

function LibraryScreen:onShowingReader()
    self:close()
end

function LibraryScreen:onClose()
    self:goBack()
    return true
end

function LibraryScreen:show()
    UIManager:show(self, "full")
end

function LibraryScreen:close()
    if self.closed then return end
    self.closed = true
    self.cover_token = nil
    UIManager:close(self, "full")
end

return LibraryScreen
