--[[--
Inlogscherm: gebruikersnaam en wachtwoord. Bij "Inloggen":
1. wifi aan zonder te vragen (NetworkMgr:turnOnWifiAndWaitForConnection), 2. OPDS-catalogus en syncserver controleren,
3. gegevens wegschrijven naar de OPDS- en kosync-instellingen, automatische sync aan,
4. setup als voltooid markeren.
Bij een fout blijven de velden ingevuld en staat er welke van de twee mislukte, en waarom.
]]
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local Compat = require("lingering_compat")
local Config = require("lingering_config")
local Settings = require("lingering_settings")
local Widgets = require("lingering_widgets")

local Setup = {}

-- Invoervenster zonder rand en titel: "Lingering" en de uitleg staan er al boven.
-- In init, omdat KOReader het venster soms opnieuw opbouwt (bijv. bij het toetsenbord).
local LoginDialog = MultiInputDialog:extend{}

function LoginDialog:init()
    MultiInputDialog.init(self)
    Compat.plainDialog(self)
end

-- Witte achtergrond bij de eerste keer, zodat de bestandsbeheerder niet zichtbaar is.
local Background = InputContainer:extend{
    on_emergency = nil,
    covers_fullscreen = true,
    -- Krijgt ook gebaren die het invoervenster erboven niet afhandelt (zoals ingedrukt
    -- houden), voor de verborgen ingang naar het volledige menu.
    is_always_active = true,
    -- Niet modal: anders komen dialogen van KOReader (bijv. MultiInputDialog) eronder
    -- (UIManager:show zet niet-modale vensters onder het bovenste modale venster).
    stop_events_propagation = true,
}
Widgets.guardPaint(Background, "inlogscherm")

-- Zo lang "Lingering" ingedrukt houden opent het volledige menu (na de hold-drempel),
-- net als de statusregel op het homescreen. Bewust onzichtbaar.
local EMERGENCY_HOLD_SECONDS = 2.5

function Background:onHoldTitle()
    self.emergency_task = function()
        self.emergency_task = nil
        logger.info("Lingering: titel inlogscherm lang ingedrukt, noodluik")
        if self.on_emergency then Widgets.safeCall("noodluik", self.on_emergency) end
    end
    UIManager:scheduleIn(EMERGENCY_HOLD_SECONDS, self.emergency_task)
    return true
end

function Background:onHoldReleaseTitle()
    if self.emergency_task then
        UIManager:unschedule(self.emergency_task)
        self.emergency_task = nil
    end
    return true
end

function Background:onCloseWidget()
    self:onHoldReleaseTitle()
end

function Background:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    self.title_dimen = Geom:new{ x = 0, y = 0, w = width, h = math.floor(height / 4) }
    local GestureRange = require("ui/gesturerange")
    self.ges_events = {
        HoldTitle = {
            GestureRange:new{ ges = "hold", range = function() return self.title_dimen end },
        },
        HoldReleaseTitle = {
            GestureRange:new{ ges = "hold_release", range = function() return self.dimen end },
        },
    }
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = math.floor(height / 3) },
            VerticalGroup:new{
                align = "center",
                TextWidget:new{ text = "Lingering", face = Font:getFace("cfont", 32), bold = true },
                VerticalSpan:new{ width = Screen:scaleBySize(12) },
                TextWidget:new{ text = _("Log in met je account."), face = Font:getFace("cfont", 20) },
            },
        },
    }
end

--[[--
opts:
- first_run: eerste keer (witte achtergrond, alleen "Inloggen", niet weg te klikken)
- fm: FileManager-instantie
- on_done: na succesvol inloggen
- on_emergency: noodluik via "Lingering" lang ingedrukt (alleen bij first_run, onzichtbaar)
]]
function Setup.show(opts)
    local background
    local dialog
    if opts.first_run then
        background = Background:new{
            on_emergency = function()
                UIManager:close(dialog)
                UIManager:close(background, "full")
                if opts.on_emergency then opts.on_emergency() end
            end,
        }
        UIManager:show(background, "full")
    end

    local username_prefill = Compat.opdsCredentials(Config.opds_url) or ""

    local function closeAll()
        UIManager:close(dialog)
        if background then UIManager:close(background, "full") end
    end

    local function fail(service, reason)
        logger.warn("Lingering: inloggen mislukt bij", service, reason)
        UIManager:show(InfoMessage:new{
            text = T(_("Inloggen mislukt bij %1:\n%2"), service, reason),
        })
    end

    local function login()
        local fields = dialog:getFields()
        local username = util.trim(fields[1] or "")
        local password = fields[2] or ""
        if username == "" or password == "" then
            UIManager:show(InfoMessage:new{
                text = _("Vul je gebruikersnaam en wachtwoord in."),
                timeout = 3,
            })
            return
        end
        dialog:onCloseKeyboard()
        logger.info("Lingering: inloggen als", username)

        -- Wifi aan zonder te vragen. De functie kan later draaien (na verbinden): zelf afvangen.
        local started = Compat.turnOnWifiThen(function() Widgets.safeCall("inloggen", function()
            local busy = InfoMessage:new{ text = _("Bezig met inloggen…") }
            UIManager:show(busy)
            UIManager:forceRePaint()

            local opds_ok, opds_reason = Compat.checkOpds(Config.opds_url, username, password)
            local sync_ok, sync_reason
            if opds_ok then
                sync_ok, sync_reason = Compat.checkKosync(Config.sync_url, username, password)
            end
            UIManager:close(busy)

            if not opds_ok then
                fail(_("de bibliotheek (OPDS)"), opds_reason)
                return
            elseif not sync_ok then
                fail(_("de syncserver"), sync_reason)
                return
            end

            local written = Compat.writeOpdsAccount(Config.opds_url, username, password, opts.fm)
                and Compat.writeKosyncAccount(Config.sync_url, username, password)
            if not written then
                UIManager:show(InfoMessage:new{
                    text = _("Inloggen gelukt, maar de gegevens konden niet worden opgeslagen."),
                })
                return
            end
            Compat.ensureAutoWifi()
            Settings:save("lingering_setup_done", true)
            logger.info("Lingering: setup voltooid")

            closeAll()
            UIManager:show(InfoMessage:new{ text = _("Ingelogd."), timeout = 2 })
            if opts.on_done then
                Widgets.safeCall("na inloggen", opts.on_done)
            end
        end) end)
        if not started then
            UIManager:show(InfoMessage:new{ text = _("Geen wifi-verbinding. Probeer het opnieuw.") })
        end
    end

    -- Eerste keer: alleen "Inloggen". Zonder knop met id "close" sluit een tik naast het
    -- venster het ook niet (InputDialog:onCloseDialog). Vanuit Instellingen: ook "Annuleren".
    local row = {}
    if not opts.first_run then
        table.insert(row, {
            text = _("Annuleren"),
            id = "close",
            callback = closeAll,
        })
    end
    table.insert(row, {
        text = _("Inloggen"),
        is_enter_default = true,
        callback = function()
            Widgets.safeCall("inloggen", login)
        end,
    })

    dialog = LoginDialog:new{
        title = _("Inloggen"),
        fields = {
            {
                text = username_prefill,
                hint = _("Gebruikersnaam"),
            },
            {
                text = "",
                hint = _("Wachtwoord"),
                text_type = "password",
            },
        },
        buttons = { row },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return Setup
