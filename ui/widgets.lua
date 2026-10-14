--[[--
Gedeelde bouwstenen voor de schermen van Lingering.
]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local Style = require("lingering.ui.style")
local Screen = Device.screen

local Widgets = {}

Widgets.plugin_dir = require("lingering.plugin").dir

--- Callbacks van tikken vallen niet onder de HandlerSandbox van de pluginloader: zelf afvangen.
function Widgets.safeCall(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        logger.warn("Lingering: fout in", label, err)
    end
    return ok
end

--[[--
Vangnet voor het tekenen. Fouten in paintTo vangt KOReader niet af: die laten KOReader
crashen. Faalt het tekenen van dit scherm, dan loggen we en sluiten we het scherm; de
widgets eronder (bestandsbeheerder of lezer) blijven bruikbaar.
]]
function Widgets.guardPaint(class, label)
    local paintTo = class.paintTo
    class.paintTo = function(self, bb, x, y)
        if self.paint_failed then return end
        local ok, err = pcall(paintTo, self, bb, x, y)
        if not ok then
            self.paint_failed = true
            logger.warn("Lingering: tekenen van", label, "mislukt, scherm wordt gesloten:", err)
            local UIManager = require("ui/uimanager")
            UIManager:nextTick(function()
                pcall(UIManager.close, UIManager, self, "full")
            end)
        end
    end
end

--[[--
Vangnet voor gebaren en andere events. Ook fouten in KOReader-widgets binnen onze schermen
(bijv. ScrollableContainer) laten KOReader anders crashen: UIManager vangt ze niet af.
Bij een fout: loggen en het event als afgehandeld beschouwen.
]]
function Widgets.guardEvents(class, label)
    local handleEvent = class.handleEvent
    class.handleEvent = function(self, event)
        local ok, result = pcall(handleEvent, self, event)
        if not ok then
            logger.warn("Lingering: fout bij event", event and event.handler, "in", label, result)
            return true
        end
        return result
    end
end

--[[--
Volledige schermen draaien mee binnen portrait (rechtop ↔ ondersteboven). KOReader stuurt
SetRotationMode (g-sensor, gebaren) alleen naar het bovenste venster; zonder handler blijft
het scherm vast staan.
]]
function Widgets.followRotation(class)
    class.onSetRotationMode = function(_, mode)
        return require("lingering.koreader.device").rotateWithinOrientation(mode)
    end
end

-- Uitgepakte omslagen in het geheugen (zolang KOReader draait), per bestand en maat: opnieuw
-- opbouwen van een scherm pakt ze dan niet opnieuw uit. Hooguit COVER_CACHE_MAX; de oudste
-- gaat eruit.
local COVER_CACHE_MAX = 40
local cover_cache, cover_order = {}, {}

--[[--
Omslag uit de cache van Mijn boeken als BlitBuffer van w × h, of nil. Geeft een kopie (die mag
de aanroeper vrijgeven, bijv. via ImageWidget image_disposable); het origineel blijft in het
geheugen. Zelf decoderen in een pcall: een kapotte afbeelding mag het scherm niet breken (en
wordt verwijderd).
]]
function Widgets.loadCover(library, url, w, h)
    if not (url and library:hasCover(url)) then return nil end
    local path = library:coverPath(url)
    local key = path .. "@" .. tostring(w) .. "x" .. tostring(h)
    local cached = cover_cache[key]
    if cached then return cached:copy() end
    local ok, bb = pcall(function()
        return require("ui/renderimage"):renderImageFile(path, false, w, h)
    end)
    if not (ok and bb) then
        logger.warn("Lingering: omslag onleesbaar, verwijderd:", url)
        os.remove(path)
        return nil
    end
    cover_cache[key] = bb
    table.insert(cover_order, key)
    if #cover_order > COVER_CACHE_MAX then
        local oldest = table.remove(cover_order, 1)
        if cover_cache[oldest] then cover_cache[oldest]:free() end
        cover_cache[oldest] = nil
    end
    return bb:copy()
end

--[[--
Omslagen van een map, uitgewaaierd over de breedte (herbruikbaar): de voorste links, de andere
in vaste stappen naar rechts; een volle waaier (COVER_MAX) reikt tot de rechterrand. Elke omslag erachter
is COVER_SHRINK keer zo groot als de vorige; allemaal onderaan uitgelijnd, als op een plank.
Elke omslag krijgt een dun randje (Style.cover_border), zodat ze van elkaar loskomen.

Widgets.stackCoverSize(stack_w, stack_h) → breedte, hoogte van de voorste omslag (2:3)
Widgets.folderStackSize(tile_w, body_h)  → voorste omslag b/h en waaier b/h voor een maptegel
Widgets.coverStack(covers, stack_w, stack_h)
    covers: lijst BlitBuffers (voorste eerst; de waaier geeft ze vrij bij het sluiten).
    Geeft een widget van stack_w × stack_h, of nil bij een lege lijst.
]]
Widgets.COVER_MAX = 4
Widgets.COVER_SHRINK = 0.88

function Widgets.stackCoverSize(_, stack_h)
    return math.floor(stack_h * 2 / 3), stack_h
end

--[[--
Maat van de waaier in een maptegel, gelijk op het homescreen en in Mijn boeken: zo breed als de
tegel (een kolom van ui/grid.lua); de voorste omslag 42% van die breedte en hooguit 30% van body_h
(de hoogte tussen bovenbalk en navigatiebalk). Geeft omslag_b, omslag_h, waaier_b, waaier_h.
]]
function Widgets.folderStackSize(tile_w, body_h)
    local stack_w = tile_w
    local single_w = math.floor(stack_w * 0.42)
    local single_h = math.floor(single_w * 3 / 2)
    local max_h = math.floor(body_h * 0.3)
    if single_h > max_h then
        single_h = max_h
        single_w = math.floor(single_h * 2 / 3)
    end
    return single_w, single_h, stack_w, single_h
end

-- Titel onder een mapstapel (homescreen en Mijn boeken).
Widgets.FOLDER_TITLE_FACE = Font:getFace("cfont", 15)

-- Omslagen (FrameContainers, voorste eerst) uitwaaieren: de voorste op x = 0, elke volgende
-- een vaste stap verder, zo gekozen dat een volle waaier (COVER_MAX omslagen) precies tot de
-- rechterrand reikt. Minder omslagen staan dus links bij elkaar, zonder gat. Onderaan uitgelijnd.
local function fan(framed, stack_w, stack_h)
    local OverlapGroupW = require("ui/widget/overlapgroup")
    local n = #framed
    local front_w = Widgets.stackCoverSize(stack_w, stack_h)
    local last_full_w = front_w * Widgets.COVER_SHRINK ^ (Widgets.COVER_MAX - 1)
    local step = math.max(0, (stack_w - last_full_w) / (Widgets.COVER_MAX - 1))
    local group = OverlapGroupW:new{ dimen = Geom:new{ w = stack_w, h = stack_h } }
    -- Achterste eerst tekenen.
    for k = n, 1, -1 do
        local size = framed[k]:getSize()
        framed[k].overlap_offset = { math.floor(step * (k - 1)), stack_h - size.h }
        table.insert(group, framed[k])
    end
    return group
end

function Widgets.coverStack(covers, stack_w, stack_h)
    if not covers or #covers == 0 then return nil end
    local ImageWidget = require("ui/widget/imagewidget")
    local front_w, front_h = Widgets.stackCoverSize(stack_w, stack_h)
    local border = Style.cover_border.size
    local n = math.min(#covers, Widgets.COVER_MAX)
    -- Per omslag de maat (kleiner naar achteren), met behoud van de eigen verhouding.
    local framed = {}
    for k = 1, n do
        local bb = covers[k]
        local factor = Widgets.COVER_SHRINK ^ (k - 1)
        local box_w, box_h = front_w * factor - 2 * border, front_h * factor - 2 * border
        local scale = math.min(box_w / bb:getWidth(), box_h / bb:getHeight())
        local w, h = math.floor(bb:getWidth() * scale), math.floor(bb:getHeight() * scale)
        framed[k] = FrameContainer:new{
            padding = 0,
            bordersize = border,
            color = Style.cover_border.color,
            background = Style.background,
            ImageWidget:new{ image = bb, image_disposable = true, width = w, height = h, scale_factor = 0 },
        }
    end
    -- Omslagen boven het maximum worden niet getekend: meteen vrijgeven.
    for i = n + 1, #covers do covers[i]:free() end
    return fan(framed, stack_w, stack_h)
end

--[[--
Lege waaier voor een map zonder (geladen) omslagen: drie lichtgrijze omslagvakken in dezelfde
vorm als Widgets.coverStack, met een klein boekicoon op het voorste.
]]
function Widgets.emptyStack(stack_w, stack_h)
    local CenterContainerW = require("ui/widget/container/centercontainer")
    local front_w, front_h = Widgets.stackCoverSize(stack_w, stack_h)
    local border = Style.cover_border.size
    local framed = {}
    for k = 1, 3 do
        local factor = Widgets.COVER_SHRINK ^ (k - 1)
        local w, h = math.floor(front_w * factor), math.floor(front_h * factor)
        local inner = Geom:new{ w = w - 2 * border, h = h - 2 * border }
        framed[k] = FrameContainer:new{
            padding = 0,
            bordersize = border,
            color = Style.cover_border.color,
            background = Style.placeholder,
            CenterContainerW:new{
                dimen = inner,
                k == 1 and Widgets.icon({ icon_file = "menu_book.svg" }, math.floor(w * 0.3), true)
                    or require("ui/widget/horizontalspan"):new{ width = 0 },
            },
        }
    end
    return fan(framed, stack_w, stack_h)
end

--- Icoon uit KOReader (icon = naam) of uit de plugin (icon_file = bestandsnaam in icons/).
--[[--
Icoon dat gedimd minder licht wordt dan KOReaders eigen dim (lightenRect met 0.5):
Style.icon_dim wit erover. Zelfde opties als IconWidget, plus quiet = true voor grijs.
]]
local QuietIcon = IconWidget:extend{ quiet = false }

function QuietIcon:paintTo(bb, x, y)
    IconWidget.paintTo(self, bb, x, y)
    if self.quiet then
        local size = self:getSize()
        bb:lightenRect(x, y, size.w, size.h, Style.icon_dim)
    end
end
Widgets.QuietIcon = QuietIcon

function Widgets.icon(spec, size, dim)
    return QuietIcon:new{
        icon = spec.icon,
        file = spec.icon_file and (Widgets.plugin_dir .. "/icons/" .. spec.icon_file) or nil,
        width = size,
        height = size,
        alpha = true,
        quiet = dim and true or false,
    }
end

--[[--
Titelbalk van onze schermen: terug-knop links, titel in het midden, optioneel een knop
rechts. Eigen iconen (KOReaders TitleBar kent alleen zijn eigen iconen).
opts: width, title, on_back, right (een ActionBar.Item of nil), show_parent.
Geeft de balk; balk:setTitle(tekst) zet een andere titel, balk.height is de hoogte.
]]

function Widgets.header(opts)
    local Item = require("lingering.ui.actionbar").Item
    local width = opts.width
    local h = Screen:scaleBySize(Style.top_bar.height)
    local inner = Geom:new{ w = width, h = h }
    local back = Item:new{
        action = { icon_file = "chevron_left.svg" },
        width = h, height = h, icon_size = Screen:scaleBySize(Style.top_bar.icon_size),
        show_parent = opts.show_parent,
        on_tap = opts.on_back,
    }
    local title_box = CenterContainer:new{ dimen = inner, TextWidget:new{ text = "" } }
    -- Zonder lijn eronder, net als de statusregel van het homescreen.
    local bar = OverlapGroup:new{
        dimen = inner,
        title_box,
        LeftContainer:new{ dimen = inner, back },
        opts.right and RightContainer:new{ dimen = inner, opts.right } or nil,
    }
    function bar.setTitle(_, text)
        title_box[1] = TextWidget:new{
            text = text,
            face = Style.topBarFace(),
            bold = true,
            max_width = width - 2 * h - 2 * Size.padding.large,
        }
    end
    bar:setTitle(opts.title or "")
    bar.height = h
    return bar
end

--[[--
Bovenkant van een pagina (Mijn boeken, Instellingen, Over Lingering, keuzelijsten): de
statusbalk van het homescreen (ui/statusbar.lua: "Lingering", licht, wifi, batterij, tijd, met
eventuele extra knoppen zoals sync), daaronder de titelbalk (Widgets.header: terug en titel).
opts: width, title, on_back, show_parent, extra (acties voor de statusbalk).
Geeft de groep; .height, .status_bar en :setTitle(tekst) zoals bij Widgets.header.
]]
function Widgets.pageHeader(opts)
    local StatusBar = require("lingering.ui.statusbar")
    local status_bar = StatusBar:new{
        width = opts.width,
        show_parent = opts.show_parent,
        title = "Lingering",
        extra = opts.extra,
        -- Geen lijn onder de balk (anders dan in het boek): kaders direct eronder.
        popover_gap = -Size.padding.large,
    }
    local title_bar = Widgets.header{
        width = opts.width,
        title = opts.title,
        on_back = opts.on_back,
        show_parent = opts.show_parent,
    }
    local group = VerticalGroup:new{ align = "left", status_bar, title_bar }
    group.status_bar = status_bar
    group.height = status_bar:getSize().h + title_bar.height
    function group.setTitle(_, text) title_bar:setTitle(text) end
    return group
end

function Widgets.line(width)
    return LineWidget:new{
        dimen = Geom:new{ w = width, h = Style.line.size },
        background = Style.line.color,
    }
end

--[[--
Grote rij over de volle breedte: [icoon] tekst ............ [rechts]
rechts is een widget (bijv. pijltje of schakelaar-icoon) of nil.
]]
local Row = InputContainer:extend{
    width = nil,
    text = nil,
    icon = nil,         -- { icon = "..." } of { icon_file = "..." }
    right = nil,        -- { icon = "..." } of { icon_file = "..." }
    enabled = true,
    callback = nil,
    right_callback = nil,   -- optioneel: eigen actie voor een tik op het rechter-icoon
}
Widgets.Row = Row

function Row:init()
    self.height = Screen:scaleBySize(72)
    self:build()
    self.ges_events = {
        TapRow = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function Row:build()
    local padding = Size.padding.large * 2
    local icon_size = Screen:scaleBySize(32)
    local fg = self.enabled and Style.text or Style.text_secondary

    local left = HorizontalGroup:new{ align = "center" }
    if self.icon then
        table.insert(left, Widgets.icon(self.icon, icon_size, not self.enabled))
        table.insert(left, HorizontalSpan:new{ width = padding })
    end
    table.insert(left, TextWidget:new{
        text = self.text,
        face = Font:getFace("cfont", 22),
        fgcolor = fg,
        max_width = self.width - 2 * padding - 3 * icon_size,
    })

    local inner = Geom:new{ w = self.width - 2 * padding, h = self.height }
    local overlap = OverlapGroup:new{
        dimen = inner,
        LeftContainer:new{ dimen = inner, left },
    }
    if self.right then
        table.insert(overlap, RightContainer:new{
            dimen = inner,
            Widgets.icon(self.right, icon_size, not self.enabled),
        })
    end
    self[1] = FrameContainer:new{
        padding = 0,
        padding_left = padding,
        padding_right = padding,
        bordersize = 0,
        background = Style.background,
        overlap,
    }
end

function Row:update(fields)
    for k, v in pairs(fields) do self[k] = v end
    self:build()
end

function Row:onTapRow(_, ges)
    if not self.enabled then return true end
    -- Tik op het rechter-icoon (ruim vlak) met een eigen actie?
    local right_zone = Screen:scaleBySize(32) + 4 * Size.padding.large
    if self.right_callback and ges and ges.pos and self.dimen
            and ges.pos.x >= self.dimen.x + self.dimen.w - right_zone then
        Widgets.safeCall("rij " .. tostring(self.text) .. " (rechts)", self.right_callback)
    elseif self.callback then
        Widgets.safeCall("rij " .. tostring(self.text), self.callback)
    end
    return true
end

--- Batterij-icoon (Material Symbols): laden, vol vanaf 95%, anders 0..6 streepjes.
--- Grijs (gedimd), zodat het niet opvalt naast de bedienbare iconen.
function Widgets.battery(percent, charging, size)
    local icon_file
    if charging then
        icon_file = "battery_charging_full.svg"
    elseif percent >= 95 then
        icon_file = "battery_full.svg"
    else
        icon_file = "battery_" .. math.floor(math.max(0, percent) * 7 / 95) .. "_bar.svg"
    end
    return Widgets.icon({ icon_file = icon_file }, size or Screen:scaleBySize(24), true)
end

--[[--
Navigatiebalk onderaan: vakken van gelijke breedte met icoon en klein label.
items: { { text = "...", icon = {...}, callback = fn }, ... }
]]
local NavButton = InputContainer:extend{
    width = nil,
    height = nil,
    text = nil,
    icon = nil,
    callback = nil,
}

function NavButton:init()
    local VerticalSpan = require("ui/widget/verticalspan")
    local CenterContainer = require("ui/widget/container/centercontainer")
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        VerticalGroup:new{
            align = "center",
            Widgets.icon(self.icon, Screen:scaleBySize(30)),
            VerticalSpan:new{ width = Size.padding.small },
            TextWidget:new{
                text = self.text,
                face = Font:getFace("cfont", 14),
                bold = self.active,
                max_width = self.width - 2 * Size.padding.default,
            },
        },
    }
    self.ges_events = {
        TapNav = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function NavButton:onTapNav()
    if self.callback then
        Widgets.safeCall("navigatie " .. tostring(self.text), self.callback)
    end
    return true
end

function Widgets.navBar(width, items)
    local VerticalGroup = require("ui/widget/verticalgroup")
    local height = Screen:scaleBySize(72)
    local cell_w = math.floor(width / #items)
    local row = HorizontalGroup:new{}
    for _, item in ipairs(items) do
        table.insert(row, NavButton:new{
            width = cell_w,
            height = height,
            text = item.text,
            icon = item.icon,
            active = item.active,
            callback = item.callback,
        })
    end
    -- Lijn bovenaan per tabblad: boven het actieve dik en zwart (Style.nav_active_line),
    -- boven de andere de gewone lijn (Style.line). Bovenaan uitgelijnd.
    local lines = HorizontalGroup:new{ align = "top" }
    for i, item in ipairs(items) do
        local style = item.active and Style.nav_active_line or Style.line
        local w = i < #items and cell_w or width - cell_w * (#items - 1)
        table.insert(lines, LineWidget:new{
            dimen = Geom:new{ w = w, h = style.size },
            background = style.color,
        })
    end
    return VerticalGroup:new{
        align = "left",
        lines,
        FrameContainer:new{
            padding = 0,
            bordersize = 0,
            background = Style.background,
            row,
        },
    }
end

--[[--
De vaste navigatiebalk onderaan homescreen, Mijn boeken, Instellingen en Over Lingering.
nav = { home = fn, library = fn, settings = fn } (uit main.lua: wisselt van scherm).
active = "home" | "library" | "settings": dat tabblad staat vet; een tik erop roept
on_reselect aan (bijv. terug naar het begin van Mijn boeken) in plaats van te wisselen.
]]
function Widgets.mainNav(width, nav, active, on_reselect)
    local function item(key, text, icon_file)
        return {
            text = text,
            icon = { icon_file = icon_file },
            active = key == active,
            callback = function()
                if key == active then
                    if on_reselect then on_reselect() end
                else
                    nav[key]()
                end
            end,
        }
    end
    local _ = require("lingering.l10n.gettext")
    return Widgets.navBar(width, {
        item("home", _("Home"), "home.svg"),
        item("library", _("Mijn boeken"), "menu_book.svg"),
        item("settings", _("Instellingen"), "settings.svg"),
    })
end

return Widgets
