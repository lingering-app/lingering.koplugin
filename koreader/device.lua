--[[--
Apparaat: voorlicht, helderheid, batterij.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

--[[--
Draaien binnen dezelfde stand (portrait ↔ omgekeerd portrait, of landscape ↔ omgekeerd
landscape), zoals Input:handleGyroEv bij een vergrendelde g-sensor: Screen:setRotationMode +
UIManager:onRotation, zonder nieuwe layout (breedte en hoogte blijven gelijk). Een draai naar
de andere stand wordt genegeerd: onze schermen zijn alleen voor portrait opgemaakt.
Bewaart fm_rotation_mode, zodat FileManager:setRotationMode na het sluiten van een boek
dezelfde kant op terugkomt. Geeft true (event afgehandeld).
]]
function M.rotateWithinOrientation(mode)
    try("rotateWithinOrientation", function()
        local Screen = require("device").screen
        local UIManager = require("ui/uimanager")
        local old_mode = Screen:getRotationMode()
        if mode == nil or mode == old_mode or mode % 2 ~= old_mode % 2 then return end
        Screen:setRotationMode(mode)
        G_reader_settings:saveSetting("fm_rotation_mode", mode)
        UIManager:onRotation()
    end)
    return true
end

--- Heeft het apparaat een g-sensor (automatisch draaien)?
function M.hasGSensor()
    local ok, has = try("hasGSensor", function() return require("device"):hasGSensor() end)
    return ok and has or false
end

--- Automatisch draaien aan? (KOReader-instelling input_ignore_gsensor, zoals DeviceListener:onToggleGSensor)
function M.isAutoRotateOn()
    local ok, on = try("isAutoRotateOn", function()
        return not G_reader_settings:isTrue("input_ignore_gsensor")
    end)
    return ok and on or false
end

--[[--
Automatisch draaien aan/uit, zoals DeviceListener:onToggleGSensor maar zonder melding:
input_ignore_gsensor bewaren en Device:toggleGSensor (Input:toggleGyroEvents).
]]
function M.setAutoRotate(on)
    return try("setAutoRotate", function()
        G_reader_settings:saveSetting("input_ignore_gsensor", not on)
        require("device"):toggleGSensor(on and true or false)
    end)
end

--[[--
KOReaders helderheidsscherm (Device:showLightDialog → ui/widget/frontlightwidget).
KOReader onthoudt de helderheid zelf (Kobo: frontlight_intensity in settings.reader.lua);
aan/uit gaat terug naar de laatste helderheid. Wijzigingen worden gemeld met het event
FrontlightStateChanged (BasePowerD:stateChanged).
]]
function M.showLightDialog()
    return try("showLightDialog", function()
        require("device"):showLightDialog()
    end)
end

--[[--
Licht aan/uit, rechtstreeks via BasePowerD:toggleFrontlight (frontend/device/generic/powerd.lua),
zoals DeviceListener:onToggleFrontlight het doet, maar zonder melding en zonder omweg via een
event, zodat het in de lezer en op het homescreen hetzelfde werkt. done() volgt als het licht
klaar is (een ramp kan even duren).
]]
function M.toggleFrontlight(done)
    return try("toggleFrontlight", function()
        local Device = require("device")
        local powerd = Device:getPowerDevice()
        local changed = powerd:toggleFrontlight(done)
        if powerd.updateResumeFrontlightState then
            powerd:updateResumeFrontlightState()
        end
        if changed == false and done then done() end
    end)
end

--- Staat het voorlicht aan? (BasePowerD:isFrontlightOn, frontend/device/generic/powerd.lua)
function M.isFrontlightOn()
    local Device = require("device")
    if not Device:hasFrontlight() then return false end
    local ok, on = try("isFrontlightOn", function()
        return Device:getPowerDevice():isFrontlightOn()
    end)
    return ok and on or false
end

--- Batterij in procenten, of nil (BasePowerD:getCapacity).
--- Aan het laden? (BasePowerD:isCharging; op Kobo ook nog waar als hij vol is)
function M.isCharging()
    local ok, charging = try("isCharging", function()
        return require("device"):getPowerDevice():isCharging()
    end)
    return ok and charging or false
end

function M.batteryPercent()
    local Device = require("device")
    if not Device:hasBattery() then return nil end
    local ok, capacity = try("getCapacity", function()
        return Device:getPowerDevice():getCapacity()
    end)
    return ok and capacity or nil
end

return M
