--[[--
Leesscherm: tikzones (terug, sluiten, verder), bovenmenu dicht.
Wordt aangeroepen vanuit main.lua als de plugin in een ReaderUI draait.
]]
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("lingering.l10n.gettext")

local DeviceAdapter = require("lingering.koreader.device")
local SyncService = require("lingering.app.sync_service")
local Navigation = require("lingering.koreader.navigation")
local ReaderControl = require("lingering.koreader.reader")
local Settings = require("lingering.app.session")

local Reader = {}

local function showActionBar(ui)
    local ActionBar = require("lingering.ui.actionbar")
    ActionBar:new{
        left = {
            {
                name = "homescreen",
                icon_file = "home.svg",
                callback = function()
                    logger.info("Lingering: actiebalk, naar homescreen")
                    Navigation.closeBook(ui)
                end,
            },
            {
                name = "inhoudsopgave",
                icon_file = "toc.svg",
                callback = function()
                    logger.info("Lingering: actiebalk, inhoudsopgave")
                    ReaderControl.showToc(ui)
                end,
            },
        },
        -- Rechts vóór licht en wifi van de statusbalk.
        extra = {
            {
                name = "synchroniseren",
                task = true,
                icon_file = "sync.svg",
                frames = { "sync-45.svg", "sync-90.svg", "sync-135.svg", "sync.svg" },
                run = function(done)
                    logger.info("Lingering: actiebalk, synchroniseren")
                    SyncService.syncNow(ui, done)
                end,
                on_done = function(ok)
                    if not ok then
                        UIManager:show(InfoMessage:new{
                            text = _("Synchroniseren mislukt."),
                            timeout = 3,
                        })
                    end
                end,
            },
            {
                name = "automatisch draaien",
                switch = true,
                icon_on = "mobile_rotate.svg",
                icon_off = "mobile_rotate_lock.svg",
                enabled = DeviceAdapter.hasGSensor(),
                state = DeviceAdapter.isAutoRotateOn(),
                on_toggle = function(on)
                    logger.info("Lingering: actiebalk, automatisch draaien", on and "aan" or "uit")
                    DeviceAdapter.setAutoRotate(on)
                end,
            },
        },
    }:show()
end

function Reader.install(ui)
    if not DeviceAdapter.isTouchDevice() then
        logger.info("Lingering: geen touchscreen, tikzones overgeslagen")
        return
    end

    local handlers = {
        backward = function()
            return ReaderControl.turnPage(ui, -1)
        end,
        forward = function()
            return ReaderControl.turnPage(ui, 1)
        end,
        top = function()
            logger.info("Lingering: tik bovenaan, actiebalk openen")
            showActionBar(ui)
            return true
        end,
        close = function()
            logger.info("Lingering: tik in het midden, boek sluiten")
            Navigation.closeBook(ui)
            return true
        end,
    }
    local zones = ReaderControl.buildZones(handlers, Settings:read("lingering_allow_hold"))
    if ReaderControl.registerZones(ui, zones) then
        logger.info("Lingering: tikzones leesscherm geregistreerd")
        ReaderControl.verifyZoneOrder(ui, zones)
        -- Alleen als onze zones er zijn: anders is het menu de enige weg uit het boek.
        ReaderControl.blockMenu(ui)
        -- Rooktest en schermafdrukken in de emulator (tests/smoke.lua), alleen met
        -- LINGERING_TEST=reader of shots-reader.
        local test = os.getenv("LINGERING_TEST")
        local Smoke = (test == "reader" or test == "shots-reader")
            and dofile(require("lingering.plugin").dir .. "/tests/smoke.lua")
        if Smoke and test == "reader" then Smoke.reader(ui, function() showActionBar(ui) end) end
        if Smoke and test == "shots-reader" then Smoke.shotsReader(ui, function() showActionBar(ui) end) end
    end
end

return Reader
