--[[--
Mijn boeken: de OPDS-catalogus als raster met omslagen, verticaal te schuiven.

- Toont meteen de gecachete versie (ook zonder wifi).
- Met wifi: synchroniseert op de achtergrond (sync-icoon draait); handmatig via het icoon.
- Mappen uit de catalogus openen met een terugknop; elke map wordt apart gecachet.
- Tik op een boek: staat het op het apparaat, dan openen; anders downloaden en openen.
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
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local Compat = require("lingering_compat")
local Widgets = require("lingering_widgets")
local Item = require("lingering_actionbar").Item

-- Titel onder een tegel: twee regels. Regelhoogte zoals TextBoxWidget die berekent:
-- (1 + line_height) * face.size, met line_height = 0.3 als standaard.
local TITLE_FACE = Font:getFace("cfont", 15)
local TITLE_HEIGHT = 2 * math.floor((1 + 0.3) * TITLE_FACE.size + 0.5)

-- Omslag zelf decoderen in een pcall: een kapotte afbeelding mag het scherm niet breken.
local function loadCover(library, url, w, h)
    if not library:hasCover(url) then return nil end
    local path = library:coverPath(url)
    local ok, bb = pcall(function()
        return require("ui/renderimage"):renderImageFile(path, false, w, h)
    end)
    if ok and bb then return bb end
    logger.warn("Lingering: omslag onleesbaar, verwijderd:", url)
    os.remove(path)
end

--[[--
Eén tegel in het raster: omslag (of mapicoon) met de titel klein eronder.
Een boek dat al op het apparaat staat krijgt een vinkje rechtsonder op de omslag.
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
    if entry.kind == "book" then
        local bb = entry.thumbnail and loadCover(self.library, entry.thumbnail, cover_w, cover_h)
        if bb then
            -- Schalen met behoud van verhouding, onderaan uitgelijnd zoals op een plank.
            local scale = math.min(cover_w / bb:getWidth(), cover_h / bb:getHeight())
            local w, h = math.floor(bb:getWidth() * scale), math.floor(bb:getHeight() * scale)
            cover = ImageWidget:new{ image = bb, image_disposable = true, width = w, height = h, scale_factor = 0 }
        else
            -- Geen omslag: titel (en auteur) in een vak van omslaggrootte.
            local inner_w = cover_w - 2 * Size.border.thin - 2 * Size.padding.default
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
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
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
                bordersize = Size.border.thin,
                color = Blitbuffer.COLOR_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{ w = cover_w - 2 * Size.border.thin, h = cover_h - 2 * Size.border.thin },
                    label,
                },
            }
        end
    else
        cover = CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = cover_h },
            Widgets.icon({ icon_file = "folder.svg" }, math.min(cover_h, math.floor(cover_w * 0.7))),
        }
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
    if entry.kind == "book" and self.library:isDownloaded(entry) then
        local badge_size = Screen:scaleBySize(24)
        local badge = Widgets.icon({ icon_file = "downloaded.svg" }, badge_size)
        badge.overlap_offset = {
            math.floor((cover_w + cover_size.w) / 2) - badge_size - Size.padding.small,
            cover_h - badge_size - Size.padding.small,
        }
        table.insert(cover_area, badge)
    end

    -- Boeken: alleen de omslag (de titel staat er meestal op). Mappen: icoon met naam.
    local content = VerticalGroup:new{ align = "center", cover_area }
    if entry.kind == "folder" then
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
        table.insert(content, TextBoxWidget:new{
            text = entry.title,
            face = TITLE_FACE,
            bold = true,
            width = self.width - 2 * Size.padding.default,
            alignment = "center",
            height = TITLE_HEIGHT,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        })
    end
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
    library = nil,
    on_open_book = nil,     -- function(path)
    covers_fullscreen = true,
    stop_events_propagation = true,
}
Widgets.guardPaint(LibraryScreen, "mijn boeken")

function LibraryScreen:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    self.stack = { { url = self.library:rootUrl(), title = _("Mijn boeken") } }
    self.synced = {}
    self.cover_failed = {}

    self:buildHeader()
    self:render()
end

function LibraryScreen:current()
    return self.stack[#self.stack]
end

-- Titelbalk: terug, titel, sync. Eén keer gebouwd, zodat een draaiend sync-icoon blijft.
function LibraryScreen:buildHeader()
    local width = self.dimen.w
    local h = Screen:scaleBySize(56)
    local icon_size = Screen:scaleBySize(28)

    local back = Item:new{
        action = { icon = "chevron.left" },
        width = h, height = h, icon_size = icon_size,
        show_parent = self,
        on_tap = function() self:goBack() end,
    }
    self.sync_item = Item:new{
        action = {
            name = "mijn boeken synchroniseren",
            task = true,
            icon_file = "sync.svg",
            frames = { "sync-45.svg", "sync-90.svg", "sync-135.svg", "sync.svg" },
            run = function(done) self:syncCurrent(done) end,
        },
        width = h, height = h, icon_size = icon_size,
        show_parent = self,
    }
    local inner = Geom:new{ w = width, h = h }
    self.title_box = CenterContainer:new{ dimen = inner, TextWidget:new{ text = "" } }
    self.header = VerticalGroup:new{
        OverlapGroup:new{
            dimen = inner,
            self.title_box,
            LeftContainer:new{ dimen = inner, back },
            RightContainer:new{ dimen = inner, self.sync_item },
        },
        Widgets.line(width),
    }
    self.header_h = h + Widgets.line(width):getSize().h
end

function LibraryScreen:setTitle(title)
    self.title_box[1] = TextWidget:new{
        text = title,
        face = Font:getFace("cfont", 22),
        bold = true,
        max_width = self.dimen.w - 2 * Screen:scaleBySize(56) - 2 * Size.padding.large,
    }
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

function LibraryScreen:render()
    local width, height = self.dimen.w, self.dimen.h
    local current = self:current()
    self:setTitle(current.title)

    local body_h = height - self.header_h
    -- Raster: minstens 3 kolommen; de omslag krimpt als het scherm laag is (2 rijen zichtbaar).
    -- Breedte zonder de verticale schuifbalk, anders ontstaat een horizontale schuifbalk.
    local grid_w = width - ScrollableContainer:getScrollbarWidth()
    local feed = self.library:cached(current.url)
    local items = feed and feed.items
    local has_books = false
    for _, entry in ipairs(items or {}) do
        if entry.kind == "book" then has_books = true break end
    end

    -- Boeken: raster van 4 met omslagen zo groot als past. Alleen collecties: raster van 2.
    local columns = has_books and 4 or 2
    local tile_w = math.floor(grid_w / columns)
    local gap = Size.padding.default
    local cover_w, cover_h
    local tile_h
    if has_books then
        -- Alleen omslagen, zonder titel eronder.
        cover_w = tile_w - 2 * gap
        cover_h = math.floor(cover_w * 3 / 2)
        -- Eén tegel moet altijd in beeld passen.
        local max_cover_h = body_h - 3 * gap
        if cover_h > max_cover_h then
            cover_h = max_cover_h
            cover_w = math.floor(cover_h * 2 / 3)
        end
        tile_h = cover_h + 2 * gap
    else
        cover_w = tile_w - 2 * gap
        cover_h = Screen:scaleBySize(110)
        tile_h = cover_h + gap + TITLE_HEIGHT + 2 * gap
    end

    -- Schuifpositie bewaren bij opnieuw opbouwen (omslagen binnen, na sync).
    if self.scroll and self.scroll_url == current.url then
        current.offset = self.scroll:getScrolledOffset()
    end

    local body
    self.page_entries = items or {}
    self.scroll, self.cropping_widget = nil, nil
    if not items then
        body = self:message(self.sync_item.busy and _("Bezig met synchroniseren…")
            or _("Nog niets gesynchroniseerd.\nZet wifi aan en tik op het sync-icoon."), width, body_h)
    elseif #items == 0 then
        body = self:message(_("Geen boeken."), width, body_h)
    else
        local grid = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = gap } }
        local rows_info = {}
        local y = gap
        local row
        for i, entry in ipairs(items) do
            if (i - 1) % columns == 0 then
                row = HorizontalGroup:new{ align = "top" }
                table.insert(grid, row)
                table.insert(rows_info, { top = y, bottom = y + tile_h - 1 })
                y = y + tile_h
            end
            table.insert(row, GridTile:new{
                entry = entry,
                library = self.library,
                width = tile_w,
                height = tile_h,
                cover_w = cover_w,
                cover_h = cover_h,
                show_parent = self,
                callback = function(e) self:openEntry(e) end,
            })
        end
        -- Verticaal schuiven (ScrollableContainer van KOReader); een veeg schuift een
        -- schermhoogte en lijnt uit op een rij tegels.
        self.scroll = ScrollableContainer:new{
            dimen = Geom:new{ w = width, h = body_h },
            show_parent = self,
            step_scroll_grid = rows_info,
            grid,
        }
        self.scroll_url = current.url
        -- UIManager gebruikt cropping_widget om verversingen tot het schuifgebied te beperken.
        self.cropping_widget = self.scroll
        body = self.scroll
    end

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.header,
            body,
        },
    }
    if self.scroll and current.offset then
        self.scroll:initState()
        self.scroll:setScrolledOffset(current.offset)
    end
    UIManager:setDirty(self, "ui")
    self:queueCovers()
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
        self:autoSync()
    elseif self.library:isDownloaded(entry) then
        self:openBook((self.library:bookPath(entry)))
    else
        self:downloadAndOpen(entry)
    end
end

function LibraryScreen:downloadAndOpen(entry)
    local started = Compat.turnOnWifiThen(function() Widgets.safeCall("downloaden", function()
        local busy = InfoMessage:new{ text = T(_("Downloaden…\n%1"), entry.title) }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local ok, path = self.library:download(entry)
        UIManager:close(busy)
        -- Bij een fout toont OPDSBrowser:downloadFile zelf een melding.
        if ok then
            self:openBook(path)
        end
    end) end)
    if not started then
        UIManager:show(InfoMessage:new{ text = _("Geen wifi-verbinding."), timeout = 3 })
    end
end

function LibraryScreen:openBook(path)
    logger.info("Lingering: mijn boeken, boek openen")
    self:close()
    if self.on_open_book then
        Widgets.safeCall("boek openen", self.on_open_book, path)
    end
end

-- Synchroniseert de huidige map. Wordt aangeroepen door de sync-taak (draaiend icoon).
function LibraryScreen:syncCurrent(done)
    local url = self:current().url
    local started = Compat.turnOnWifiThen(function()
        self.library:sync(url, function(ok)
            if ok then self.synced[url] = true end
            if not self.closed then self:render() end
            done(ok)
        end)
    end)
    if not started then done(false) end
    if not self.library:cached(url) and not self.closed then
        self:render() -- toont "Bezig met synchroniseren…"
    end
end

-- Met wifi aan: deze map één keer per bezoek aan het scherm op de achtergrond verversen.
function LibraryScreen:autoSync()
    local url = self:current().url
    if not self.synced[url] and Compat.isOnline() then
        self.sync_item:startTask()
    end
end

-- Ontbrekende omslagen ophalen, één per tik; per zes (en aan het eind) één verversing.
function LibraryScreen:queueCovers()
    if self.closed or not Compat.isOnline() then return end
    local missing = {}
    for _, entry in ipairs(self.page_entries or {}) do
        local url = entry.thumbnail
        if url and not self.cover_failed[url] and not self.library:hasCover(url) then
            table.insert(missing, url)
        end
    end
    if #missing == 0 then return end

    local token = {}
    self.cover_token = token
    local index, fetched = 0, 0
    local function step()
        if self.closed or self.cover_token ~= token then return end
        index = index + 1
        local url = missing[index]
        if url then
            local ok = pcall(function()
                if self.library:fetchCover(url) then
                    fetched = fetched + 1
                else
                    self.cover_failed[url] = true
                end
            end)
            if not ok then self.cover_failed[url] = true end
            -- Per zes omslagen één verversing, zodat ze geleidelijk verschijnen.
            if fetched >= 6 then
                fetched = 0
                self:render()
                return -- render() start een nieuwe ronde voor de rest
            end
            UIManager:scheduleIn(0.05, step)
        elseif fetched > 0 then
            self:render()
        end
    end
    UIManager:scheduleIn(0.1, step)
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
    UIManager:scheduleIn(0.5, function()
        Widgets.safeCall("automatisch synchroniseren", function() self:autoSync() end)
    end)
end

function LibraryScreen:close()
    if self.closed then return end
    self.closed = true
    self.cover_token = nil
    UIManager:close(self, "full")
end

return LibraryScreen
