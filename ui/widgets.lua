--[[--
Gedeelde bouwstenen voor de schermen van Lingering.
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

--- Omslag uit de cache van Mijn boeken als BlitBuffer, of nil. Zelf decoderen in een pcall:
--- een kapotte afbeelding mag het scherm niet breken (en wordt verwijderd).
function Widgets.loadCover(library, url, w, h)
    if not (url and library:hasCover(url)) then return nil end
    local path = library:coverPath(url)
    local ok, bb = pcall(function()
        return require("ui/renderimage"):renderImageFile(path, false, w, h)
    end)
    if ok and bb then return bb end
    logger.warn("Lingering: omslag onleesbaar, verwijderd:", url)
    os.remove(path)
end

--[[--
Stapel omslagen (herbruikbaar): tot drie omslagen op elkaar, de voorste linksonder, de
achterste steken STACK_OFFSET × omslagbreedte naar rechtsboven uit. Elke omslag krijgt een
dun randje, zodat ze van elkaar loskomen; onderaan uitgelijnd.

Widgets.stackSize(cover_w, cover_h)      → breedte, hoogte van de hele stapel
Widgets.stackCoverSize(stack_w, stack_h) → breedte, hoogte van één omslag in die stapel
Widgets.coverStack(covers, stack_w, stack_h)
    covers: lijst BlitBuffers (voorste eerst; de stapel geeft ze vrij bij het sluiten).
    Geeft een widget van stack_w × stack_h, of nil bij een lege lijst.
]]
Widgets.STACK_OFFSET = 0.12
local STACK_MAX = 3

function Widgets.stackSize(cover_w, cover_h)
    local off = math.floor(cover_w * Widgets.STACK_OFFSET)
    return cover_w + 2 * off, cover_h + 2 * off
end

function Widgets.stackCoverSize(stack_w, stack_h)
    local cover_w = math.floor(stack_w / (1 + 2 * Widgets.STACK_OFFSET))
    local off = math.floor(cover_w * Widgets.STACK_OFFSET)
    return cover_w, stack_h - 2 * off
end

function Widgets.coverStack(covers, stack_w, stack_h)
    if not covers or #covers == 0 then return nil end
    local ImageWidget = require("ui/widget/imagewidget")
    local OverlapGroupW = require("ui/widget/overlapgroup")
    local cover_w, cover_h = Widgets.stackCoverSize(stack_w, stack_h)
    local off = math.floor(cover_w * Widgets.STACK_OFFSET)
    local border = Size.border.thin
    local group = OverlapGroupW:new{ dimen = Geom:new{ w = stack_w, h = stack_h } }
    -- Achterste eerst tekenen; k = 0 is de voorste.
    for i = math.min(#covers, STACK_MAX), 1, -1 do
        local k = i - 1
        local bb = covers[i]
        local scale = math.min((cover_w - 2 * border) / bb:getWidth(), (cover_h - 2 * border) / bb:getHeight())
        local w, h = math.floor(bb:getWidth() * scale), math.floor(bb:getHeight() * scale)
        local framed = FrameContainer:new{
            padding = 0,
            bordersize = border,
            color = Blitbuffer.COLOR_DARK_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            ImageWidget:new{ image = bb, image_disposable = true, width = w, height = h, scale_factor = 0 },
        }
        framed.overlap_offset = { k * off, (STACK_MAX - 1 - k) * off + (cover_h - (h + 2 * border)) }
        table.insert(group, framed)
    end
    -- Omslagen boven het maximum worden niet getekend: meteen vrijgeven.
    for i = STACK_MAX + 1, #covers do covers[i]:free() end
    return group
end

--- Icoon uit KOReader (icon = naam) of uit de plugin (icon_file = bestandsnaam in icons/).
function Widgets.icon(spec, size, dim)
    return IconWidget:new{
        icon = spec.icon,
        file = spec.icon_file and (Widgets.plugin_dir .. "/icons/" .. spec.icon_file) or nil,
        width = size,
        height = size,
        alpha = true,
        dim = dim,
    }
end

--[[--
Titelbalk van onze schermen: terug-knop links, titel in het midden, optioneel een knop
rechts, lijn eronder. Eigen iconen (KOReaders TitleBar kent alleen zijn eigen iconen).
opts: width, title, on_back, right (een ActionBar.Item of nil), show_parent.
Geeft de balk; balk:setTitle(tekst) zet een andere titel, balk.height is de hoogte.
]]
Widgets.HEADER_SIZE = 56
function Widgets.header(opts)
    local Item = require("lingering.ui.actionbar").Item
    local width = opts.width
    local h = Screen:scaleBySize(Widgets.HEADER_SIZE)
    local inner = Geom:new{ w = width, h = h }
    local back = Item:new{
        action = { icon_file = "chevron-left.svg" },
        width = h, height = h, icon_size = Screen:scaleBySize(28),
        show_parent = opts.show_parent,
        on_tap = opts.on_back,
    }
    local title_box = CenterContainer:new{ dimen = inner, TextWidget:new{ text = "" } }
    local bar = VerticalGroup:new{
        OverlapGroup:new{
            dimen = inner,
            title_box,
            LeftContainer:new{ dimen = inner, back },
            opts.right and RightContainer:new{ dimen = inner, opts.right } or nil,
        },
        Widgets.line(width),
    }
    function bar.setTitle(_, text)
        title_box[1] = TextWidget:new{
            text = text,
            face = Font:getFace("cfont", 22),
            bold = true,
            max_width = width - 2 * h - 2 * Size.padding.large,
        }
    end
    bar:setTitle(opts.title or "")
    bar.height = h + Widgets.line(width):getSize().h
    return bar
end

function Widgets.line(width)
    return LineWidget:new{
        dimen = Geom:new{ w = width, h = Size.line.medium },
        background = Blitbuffer.COLOR_DARK_GRAY,
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
    local fg = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY

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
        background = Blitbuffer.COLOR_WHITE,
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

--[[--
Batterij-icoon: omtrek met een vulling die meeloopt met het percentage, en een nopje.
Getekend met widgets (geen bestand), zodat elk percentage klopt.
]]
function Widgets.battery(percent)
    local body_w = Screen:scaleBySize(22)
    local body_h = Screen:scaleBySize(12)
    local border = Size.border.thick
    local gap = Size.border.thin
    local inner_w = body_w - 2 * border - 2 * gap
    local inner_h = body_h - 2 * border - 2 * gap
    local fill_w = math.floor(inner_w * math.max(0, math.min(100, percent or 0)) / 100 + 0.5)

    local fill = LeftContainer:new{
        dimen = Geom:new{ w = inner_w, h = inner_h },
        LineWidget:new{
            dimen = Geom:new{ w = math.max(fill_w, 0), h = inner_h },
            background = Blitbuffer.COLOR_BLACK,
        },
    }
    local body = FrameContainer:new{
        padding = gap,
        bordersize = border,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        fill,
    }
    local nub = LineWidget:new{
        dimen = Geom:new{ w = border + gap, h = math.floor(body_h / 2) },
        background = Blitbuffer.COLOR_BLACK,
    }
    return HorizontalGroup:new{ align = "center", body, nub }
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
            callback = item.callback,
        })
    end
    return VerticalGroup:new{
        LineWidget:new{
            dimen = Geom:new{ w = width, h = Size.line.thin },
            background = Blitbuffer.COLOR_BLACK,
        },
        FrameContainer:new{
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            row,
        },
    }
end

return Widgets
