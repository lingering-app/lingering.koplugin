--[[--
Leesscherm: tikzones (terug, sluiten, verder), bovenmenu dicht.
Wordt aangeroepen vanuit main.lua als de plugin in een ReaderUI draait.
]]
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local Compat = require("lingering.koreader.compat")
local Settings = require("lingering.app.session")

local Reader = {}

local function showActionBar(ui)
    local ActionBar = require("lingering.ui.actionbar")
    ActionBar:new{
        actions = {
            {
                name = "homescreen",
                icon = "home",
                callback = function()
                    logger.info("Lingering: actiebalk, naar homescreen")
                    Compat.closeBook(ui)
                end,
            },
            {
                name = "inhoudsopgave",
                icon = "appbar.navigation",
                callback = function()
                    logger.info("Lingering: actiebalk, inhoudsopgave")
                    Compat.showToc(ui)
                end,
            },
            {
                name = "synchroniseren",
                task = true,
                icon_file = "sync.svg",
                frames = { "sync-45.svg", "sync-90.svg", "sync-135.svg", "sync.svg" },
                run = function(done)
                    logger.info("Lingering: actiebalk, synchroniseren")
                    Compat.syncNow(ui, done)
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
                name = "licht",
                switch = true,
                icon_on = "light-on.svg",
                icon_off = "light-off.svg",
                enabled = Device:hasFrontlight(),
                state = Compat.isFrontlightOn(),
                state_func = Compat.isFrontlightOn,
                on_toggle = function(on)
                    logger.info("Lingering: actiebalk, licht", on and "aan" or "uit")
                    Compat.toggleFrontlight()
                end,
            },
        },
    }:show()
end

function Reader.install(ui)
    if not Device:isTouchDevice() then
        logger.info("Lingering: geen touchscreen, tikzones overgeslagen")
        return
    end

    local handlers = {
        backward = function()
            return Compat.turnPage(ui, -1)
        end,
        forward = function()
            return Compat.turnPage(ui, 1)
        end,
        top = function()
            logger.info("Lingering: tik bovenaan, actiebalk openen")
            showActionBar(ui)
            return true
        end,
        close = function()
            logger.info("Lingering: tik in het midden, boek sluiten")
            Compat.closeBook(ui)
            return true
        end,
    }
    local zones = Compat.buildReaderZones(handlers, Settings:read("lingering_allow_hold"))
    if Compat.registerReaderZones(ui, zones) then
        logger.info("Lingering: tikzones leesscherm geregistreerd")
        Compat.verifyZoneOrder(ui, zones)
        -- Alleen als onze zones er zijn: anders is het menu de enige weg uit het boek.
        Compat.blockReaderMenu(ui)
    end
end

return Reader
