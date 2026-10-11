--[[--
Apparaat: voorlicht, helderheid, batterij.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

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
function M.batteryPercent()
    local Device = require("device")
    if not Device:hasBattery() then return nil end
    local ok, capacity = try("getCapacity", function()
        return Device:getPowerDevice():getCapacity()
    end)
    return ok and capacity or nil
end

return M
