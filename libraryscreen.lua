--[[--
Mijn boeken: de OPDS-catalogus als lijst met omslagen, per pagina.

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

--[[--
Eén rij: een map (icoon, naam, pijltje) of een boek (omslag, titel, auteur, en een
vinkje als het al op het apparaat staat).
]]
local ListRow = InputContainer:extend{
    entry = nil,
    library = nil,
    width = nil,
    height = nil,
    callback = nil,
}

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

function ListRow:init()
    local entry = self.entry
    local padding = Size.padding.large * 2
    local cover_h = self.height - 2 * Size.padding.default
    local cover_w = math.floor(cover_h * 2 / 3)
    local icon_size = Screen:scaleBySize(28)

    local left
    if entry.kind == "book" then
        local bb = entry.thumbnail and loadCover(self.library, entry.thumbnail, cover_w, cover_h)
        if bb then
            left = CenterContainer:new{
                dimen = Geom:new{ w = cover_w, h = cover_h },
                ImageWidget:new{ image = bb, image_disposable = true, width = cover_w, height = cover_h, scale_factor = 0 },
            }
        else
            left = CenterContainer:new{
                dimen = Geom:new{ w = cover_w, h = cover_h },
                Widgets.icon({ icon = "book.opened" }, math.floor(cover_w * 0.6), true),
            }
        end
    else
        left = CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = cover_h },
            Widgets.icon({ icon_file = "folder.svg" }, math.floor(cover_w * 0.8)),
        }
    end

    local right
    if entry.kind == "folder" then
        right = Widgets.icon({ icon = "chevron.right" }, icon_size)
    elseif self.library:isDownloaded(entry) then
        right = Widgets.icon({ icon_file = "downloaded.svg" }, icon_size)
    end

    local text_w = self.width - 2 * padding - cover_w - padding - (right and (icon_size + padding) or 0)
    local texts = VerticalGroup:new{ align = "left" }
    table.insert(texts, TextBoxWidget:new{
        text = entry.title,
        face = Font:getFace("cfont", 20),
        bold = true,
        width = text_w,
        height = Screen:scaleBySize(20) * 2 + Size.padding.small,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    })
    if entry.kind == "book" and entry.author then
        table.insert(texts, VerticalSpan:new{ width = Size.padding.small })
        table.insert(texts, TextWidget:new{
            text = entry.author,
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = text_w,
        })
    end

    local inner = Geom:new{ w = self.width - 2 * padding, h = self.height }
    local overlap = OverlapGroup:new{
        dimen = inner,
        LeftContainer:new{
            dimen = inner,
            HorizontalGroup:new{
                align = "center",
                left,
                HorizontalSpan:new{ width = padding },
                texts,
            },
        },
    }
    if right then
        table.insert(overlap, RightContainer:new{ dimen = inner, right })
    end
    self[1] = FrameContainer:new{
        padding = 0,
        padding_left = padding,
        padding_right = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        overlap,
    }
    self.ges_events = {
        TapRow = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
    }
end

function ListRow:onTapRow()
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
    self.stack = { { url = self.library:rootUrl(), title = _("Mijn boeken"), page = 1 } }
    self.synced = {}
    self.cover_failed = {}

    self:buildHeader()
    self.ges_events = {
        Swipe = {
            GestureRange:new{ ges = "swipe", range = function() return self.body_dimen end },
        },
    }
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

    local footer_h = Screen:scaleBySize(56)
    local body_h = height - self.header_h - footer_h
    local row_h = Screen:scaleBySize(100)
    local line_h = Widgets.line(width):getSize().h
    local per_page = math.max(1, math.floor(body_h / (row_h + line_h)))
    self.body_dimen = Geom:new{ x = 0, y = self.header_h, w = width, h = body_h + footer_h }

    local feed = self.library:cached(current.url)
    local items = feed and feed.items
    local body, footer
    self.page_entries = {}
    self.pages = nil
    if not items then
        body = self:message(self.sync_item.busy and _("Bezig met synchroniseren…")
            or _("Nog niets gesynchroniseerd.\nZet wifi aan en tik op het sync-icoon."), width, body_h)
    elseif #items == 0 then
        body = self:message(_("Geen boeken."), width, body_h)
    else
        local pages = math.ceil(#items / per_page)
        current.page = math.max(1, math.min(current.page, pages))
        self.pages = pages
        local first = (current.page - 1) * per_page + 1
        body = VerticalGroup:new{ align = "left" }
        for i = first, math.min(first + per_page - 1, #items) do
            local entry = items[i]
            table.insert(self.page_entries, entry)
            table.insert(body, ListRow:new{
                entry = entry,
                library = self.library,
                width = width,
                height = row_h,
                callback = function(e) self:openEntry(e) end,
            })
            table.insert(body, Widgets.line(width))
        end
        if pages > 1 then
            footer = self:buildFooter(width, footer_h, current.page, pages)
        end
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
            FrameContainer:new{
                padding = 0, bordersize = 0,
                width = width, height = body_h,
                body,
            },
            footer or VerticalSpan:new{ width = footer_h },
        },
    }
    UIManager:setDirty(self, "ui")
    self:queueCovers()
end

function LibraryScreen:buildFooter(width, h, page, pages)
    local icon_size = Screen:scaleBySize(28)
    local function nav(icon, enabled, fn)
        return Item:new{
            action = { icon = icon, enabled = enabled },
            width = h, height = h, icon_size = icon_size,
            show_parent = self,
            on_tap = fn,
        }
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = h },
        HorizontalGroup:new{
            align = "center",
            nav("chevron.left", page > 1, function() self:changePage(-1) end),
            HorizontalSpan:new{ width = Size.padding.large * 2 },
            TextWidget:new{ text = T(_("%1 / %2"), page, pages), face = Font:getFace("cfont", 18) },
            HorizontalSpan:new{ width = Size.padding.large * 2 },
            nav("chevron.right", page < pages, function() self:changePage(1) end),
        },
    }
end

function LibraryScreen:changePage(delta)
    local current = self:current()
    local target = current.page + delta
    if not self.pages or target < 1 or target > self.pages then return end
    current.page = target
    self:render()
end

function LibraryScreen:onSwipe(_, ges)
    if ges.direction == "west" then
        self:changePage(1)
    elseif ges.direction == "east" then
        self:changePage(-1)
    end
    return true
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
        table.insert(self.stack, { url = entry.url, title = entry.title, page = 1 })
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

-- Ontbrekende omslagen van deze pagina ophalen, één per tik; daarna één verversing.
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
