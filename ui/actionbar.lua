--[[--
Actiebalk bovenaan het leesscherm: de statusbalk van het homescreen (ui/statusbar.lua)
met extra knoppen. Opent met een tik in de strook bovenaan, sluit met een tik erbuiten.
Item (hieronder) is één icoon in de balk; ook gebruikt in andere balken.

Soorten acties:
- knop:        { icon | icon_file, callback = fn }                 (balk sluit)
- schakelaar:  { switch = true, icon_on, icon_off, state, on_toggle = fn(state) }
- taak:        { task = true, icon_file, frames = {...}, run = fn(done) }
               Tijdens de taak wisselt het icoon door de frames; done(ok) stopt dat.
]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local time = require("ui/time")
local Style = require("lingering.ui.style")
local Screen = Device.screen

local plugin_dir = require("lingering.plugin").dir

-- Tijd tussen twee frames van een draaiend icoon, en hoe lang een taak maximaal mag duren.
local FRAME_INTERVAL = 0.4
-- Ruim, want wifi aanzetten en verbinden kost op een Kobo al 10-20 seconden.
local TASK_TIMEOUT = 60
-- Minimale draaitijd van een taak-icoon, in seconden.
local MIN_SPIN = 1.2

-- Callbacks vallen niet onder de HandlerSandbox van de pluginloader: zelf afvangen.
local function safeCall(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        logger.warn("Lingering: fout in actiebalk,", label, err)
    end
    return ok
end

local Item = InputContainer:extend{
    action = nil,
    width = nil,
    height = nil,
    icon_size = nil,    -- standaard 40 (geschaald)
    on_tap = nil,
}

function Item:init()
    self.state = self.action.state and true or false
    self.enabled = self.action.enabled ~= false
    self.frame = 0
    self:build()
    self.ges_events = {
        TapItem = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

-- Geeft { icon = naam } of { icon_file = bestand }, optioneel met dim = true.
-- Een schakelaar kan icon_spec(state) meegeven voor meer dan twee toestanden.
function Item:currentIcon()
    local action = self.action
    if action.switch then
        if action.icon_spec then
            return action.icon_spec(self.state)
        end
        return { icon_file = self.state and action.icon_on or action.icon_off }
    end
    if action.task and self.frame > 0 then
        return { icon_file = action.frames[self.frame] }
    end
    return { icon = action.icon, icon_file = action.icon_file }
end

function Item:build()
    local spec = self:currentIcon()
    local icon_size = self.icon_size or Screen:scaleBySize(40)
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        IconWidget:new{
            icon = spec.icon,
            file = spec.icon_file and (plugin_dir .. "/icons/" .. spec.icon_file) or nil,
            width = icon_size,
            height = icon_size,
            alpha = true,
            dim = spec.dim or not self.enabled,
        },
    }
end

--- Stand van buitenaf bijwerken (bijv. na een netwerk-event), zonder on_toggle.
function Item:setState(state)
    state = state and true or false
    if state == self.state and not self.action.icon_spec then return end
    self.state = state
    self:redraw()
end

-- Alleen dit vak verversen; standaard met de snelle e-ink-modus (laat wat schaduw achter).
function Item:redraw(mode)
    self:build()
    UIManager:setDirty(self.show_parent, mode or "fast", self.dimen)
end

function Item:startTask()
    if self.busy then return end
    self.busy = true
    self.frame = 1
    self:redraw()
    -- Het gedraaide icoon eerst echt tonen: de taak kan de UI even blokkeren.
    UIManager:forceRePaint()
    local started = UIManager:getElapsedTimeSinceBoot()

    self.next_frame = function()
        self.frame = self.frame % #self.action.frames + 1
        self:redraw()
        UIManager:scheduleIn(FRAME_INTERVAL, self.next_frame)
    end
    UIManager:scheduleIn(FRAME_INTERVAL, self.next_frame)

    local finished = false
    local function finish(ok)
        self:stopTask()
        logger.info("Lingering: taak", self.action.name or "?", ok and "gelukt" or "mislukt")
        if self.action.on_done then
            safeCall("on_done", self.action.on_done, ok)
        end
    end
    local function done(ok)
        if finished then return end
        finished = true
        -- Minstens MIN_SPIN laten draaien, zodat ook een snelle taak zichtbaar is.
        local elapsed = time.to_s(UIManager:getElapsedTimeSinceBoot() - started)
        if elapsed < MIN_SPIN then
            UIManager:scheduleIn(MIN_SPIN - elapsed, function() safeCall("taak afronden", finish, ok) end)
        else
            finish(ok)
        end
    end
    self.timeout = function() done(false) end
    UIManager:scheduleIn(TASK_TIMEOUT, self.timeout)

    -- In de volgende tik beginnen, na het tekenen van het eerste frame.
    UIManager:nextTick(function()
        if not safeCall("taak", self.action.run, done) then
            done(false)
        end
    end)
end

function Item:stopTask()
    if self.next_frame then UIManager:unschedule(self.next_frame) end
    if self.timeout then UIManager:unschedule(self.timeout) end
    self.next_frame, self.timeout = nil, nil
    self.busy = false
    if self.frame ~= 0 then
        self.frame = 0
        -- Schone verversing, zodat duidelijk is dat het icoon stilstaat.
        if not self.closed then self:redraw("ui") end
    end
end

function Item:onTapItem()
    if not self.enabled then return true end
    local action = self.action
    if action.switch then
        self.state = not self.state
        self:redraw()
        if action.on_toggle then
            safeCall("schakelaar", action.on_toggle, self.state)
        end
    elseif action.task then
        self:startTask()
    elseif self.on_tap then
        safeCall("knop", self.on_tap)
    end
    return true
end

local ActionBar = InputContainer:extend{
    left = nil,     -- acties links in de statusbalk (bijv. huis)
    extra = nil,    -- acties rechts vóór licht en wifi (bijv. inhoudsopgave, sync, draaien)
    modal = true,
    stop_events_propagation = true,
}
require("lingering.ui.widgets").guardPaint(ActionBar, "actiebalk")
require("lingering.ui.widgets").guardEvents(ActionBar, "actiebalk")

-- Knoppen sluiten eerst de balk; schakelaars en taken laten hem open.
function ActionBar:wrap(actions)
    local wrapped = {}
    for _, action in ipairs(actions or {}) do
        if action.switch or action.task then
            table.insert(wrapped, action)
        else
            local copy = {}
            for k, v in pairs(action) do copy[k] = v end
            copy.callback = function()
                self:dismiss()
                safeCall("knop", action.callback)
            end
            table.insert(wrapped, copy)
        end
    end
    return wrapped
end

function ActionBar:init()
    local screen_w = Screen:getWidth()
    -- Dezelfde statusbalk als op het homescreen (ui/statusbar.lua), met extra knoppen.
    self.status_bar = require("lingering.ui.statusbar"):new{
        width = screen_w,
        show_parent = self,
        left = self:wrap(self.left),
        extra = self:wrap(self.extra),
    }
    self.items = self.status_bar.items

    -- Witte balk over de volle breedte; een lijn (Style.line) scheidt hem van de tekst van het boek.
    self[1] = VerticalGroup:new{
        FrameContainer:new{
            padding = 0,
            bordersize = 0,
            background = Style.background,
            self.status_bar,
        },
        require("lingering.ui.widgets").line(screen_w),
    }
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }

    -- Een tik ergens anders op het scherm sluit de balk.
    self.ges_events = {
        TapOutside = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = screen_w, h = Screen:getHeight() },
            },
        },
    }
end

function ActionBar:onTapOutside(_, ges)
    if not (ges and ges.pos and ges.pos:intersectWith(self.dimen)) then
        self:dismiss()
    end
    return true
end

function ActionBar:onClose()
    self:dismiss()
    return true
end

function ActionBar:onCloseWidget()
    -- Geplande frames stoppen; een lopende taak mag zelf afmaken.
    for _, item in ipairs(self.items) do
        item.closed = true
        if item.next_frame then UIManager:unschedule(item.next_frame) end
    end
end

function ActionBar:show()
    UIManager:show(self, "ui", self.dimen)
end

function ActionBar:dismiss()
    UIManager:close(self, "ui", self.dimen)
end

ActionBar.Item = Item

return ActionBar
