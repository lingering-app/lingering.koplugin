--[[--
Voortgang van een sync-knop als lijst in een kader eronder (ui/popover.lua): alle stappen staan
er vanaf het begin, dus het kader springt niet. Klaar: vinkje en lichtgrijs; bezig: pijltje,
donker, met "…"; nog te doen: grijs zonder teken; mislukt: kruisje, met de reden eronder.
Klein lettertype (Style.popoverSmallFace). Gebruikt door Mijn boeken en het homescreen.

local status = SyncStatus.new{
    anchor = function() return sync_item.dimen end,
    gap = status_bar.popover_gap,                      -- zie Popover
    steps = { { id = "connect", label = _("Verbinden") }, ... },
    widest = { T(_("Boeken ophalen (%1 van %2)"), 99, 99) }, -- langere teksten voor de breedte
}
status:start("books")                    -- eerdere stappen zijn dan klaar
status:start("books", T(_("Boeken ophalen (%1 van %2)"), 2, 4)) -- zelfde stap, andere tekst
status:finish()                          -- alles klaar, sluit na 3 s
status:fail(_("Geen verbinding"))        -- huidige stap mislukt, sluit na 3 s
Sloot je het kader met een tik, dan komt het tijdens deze sync niet terug (de sync loopt door).
]]
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")

local Style = require("lingering.ui.style")
local Widgets = require("lingering.ui.widgets")

local SyncStatus = {}
SyncStatus.__index = SyncStatus

local CLOSE_AFTER = 3
local ELLIPSIS = "…"
local MARKS = { done = "check.svg", current = "chevron_right.svg", failed = "close.svg" }

function SyncStatus.new(opts)
    local self = setmetatable({
        anchor = opts.anchor,
        gap = opts.gap,
        steps = {},
        state = {},     -- id → "done" | "current" | "failed" | nil
        labels = {},    -- id → tekst (standaard het label van de stap)
    }, SyncStatus)
    for i, step in ipairs(opts.steps) do
        self.steps[i] = step.id
        self.labels[step.id] = step.label
    end
    -- Vaste breedte: de langste tekst die kan voorkomen (met "…").
    local face = Style.popoverSmallFace()
    local widest = 0
    local function measure(text)
        widest = math.max(widest, TextWidget:new{ text = text .. ELLIPSIS, face = face }:getSize().w)
    end
    for _, step in ipairs(opts.steps) do measure(step.label) end
    for _, text in ipairs(opts.widest or {}) do measure(text) end
    self.icon_size = Screen:scaleBySize(16)
    self.icon_gap = Size.padding.small
    self.text_w = widest
    self.width = self.icon_size + self.icon_gap + widest
    return self
end

function SyncStatus:row(mark, text, gray)
    local icon = MARKS[mark] and Widgets.icon({ icon_file = MARKS[mark] }, self.icon_size, gray)
    return HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = self.icon_size, h = self.icon_size },
            icon or HorizontalSpan:new{ width = 0 },
        },
        HorizontalSpan:new{ width = self.icon_gap },
        LeftContainer:new{
            dimen = Geom:new{ w = self.text_w, h = TextWidget:new{ text = "Ag", face = Style.popoverSmallFace() }:getSize().h },
            TextWidget:new{
                text = text,
                face = Style.popoverSmallFace(),
                fgcolor = gray and Style.text_secondary or nil,
                max_width = self.text_w,
            },
        },
    }
end

function SyncStatus:content()
    local group = VerticalGroup:new{ align = "left" }
    for _, id in ipairs(self.steps) do
        local state = self.state[id]
        local text = self.labels[id]
        if state == "current" then text = text .. ELLIPSIS end
        -- Alleen de stap die bezig is (of mislukte) is donker; de rest grijs.
        table.insert(group, self:row(state, text, state ~= "current" and state ~= "failed"))
        if state == "failed" and self.reason then
            table.insert(group, self:row(nil, self.reason, true))
        end
    end
    return group
end

function SyncStatus:render(finished)
    local popover = self.popover
    if popover and popover.closed then return end
    if popover then
        popover:refresh()
    else
        popover = require("lingering.ui.popover"):new{
            anchor = self.anchor(),
            gap = self.gap,
            stay = true,
            content_taps = false,
            content = function() return self:content() end,
        }
        popover:show()
        self.popover = popover
    end
    if finished then popover:closeIn(CLOSE_AFTER) end
end

--- Stap id begint (eerdere stappen zijn klaar); label: andere tekst voor deze stap (teller).
function SyncStatus:start(id, label)
    for _, step in ipairs(self.steps) do
        if step == id then break end
        self.state[step] = "done"
    end
    self.state[id] = "current"
    if label then self.labels[id] = label end
    self:render()
end

--- Alles klaar; het kader sluit na een paar seconden.
function SyncStatus:finish()
    for _, step in ipairs(self.steps) do self.state[step] = "done" end
    self:render(true)
end

--- De huidige stap is mislukt (reden eronder); het kader sluit na een paar seconden.
function SyncStatus:fail(reason)
    for _, step in ipairs(self.steps) do
        if self.state[step] == "current" then self.state[step] = "failed" end
    end
    self.reason = reason
    self:render(true)
end

--- Kader dicht (bijv. als het scherm sluit).
function SyncStatus:close()
    if self.popover then self.popover:dismiss() end
end

function SyncStatus:isOpen()
    return self.popover ~= nil and not self.popover.closed
end

return SyncStatus
