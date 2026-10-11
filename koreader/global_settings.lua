--[[--
KOReader-instellingen die Lingering afdwingt (settings.reader.lua), met back-up.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local logger = require("logger")
local try = require("lingering.koreader.try")

local M = {}

--[[--
Instellingen van KOReader zelf die Lingering afdwingt (settings.reader.lua).
Sleutels gelezen in reader.lua (start_with) en frontend/ui/screensaver.lua.
]]
local ENFORCED_GLOBAL_SETTINGS = {
    -- Altijd starten in de bestandsbeheerder, waar het homescreen overheen komt.
    { key = "start_with", value = "filemanager" },
    -- Slaapscherm: omslag van het huidige boek, zonder tekst.
    { key = "screensaver_type", value = "cover" },
    { key = "screensaver_show_message", value = false },
    -- Het homescreen ligt over de bestandsbeheerder; ook daar de omslag tonen.
    { key = "screensaver_hide_cover_in_filemanager", value = false },
    -- Geen "Uitgeschakeld"/"Herstarten"-tekst over het slaapscherm.
    { key = "screensaver_hide_fallback_msg", value = true },
}

--- Maakt één keer een back-up van een instellingenbestand, vóór de eerste wijziging.
function M.backupOnce(path)
    local lfs = require("libs/libkoreader-lfs")
    local backup = path .. ".lingering-backup"
    if lfs.attributes(backup, "mode") or not lfs.attributes(path, "mode") then
        return true
    end
    local ffiUtil = require("ffi/util")
    local ok, err = pcall(ffiUtil.copyFile, path, backup)
    if ok and err == nil then
        logger.info("Lingering: back-up gemaakt:", backup)
        return true
    end
    logger.warn("Lingering: back-up mislukt, instellingen niet gewijzigd:", path, err)
    return false
end

function M.enforce()
    return try("enforceGlobalSettings", function()
        local changes = {}
        for _, setting in ipairs(ENFORCED_GLOBAL_SETTINGS) do
            if G_reader_settings:readSetting(setting.key) ~= setting.value then
                table.insert(changes, setting)
            end
        end
        if #changes == 0 then return end
        if not M.backupOnce(G_reader_settings.file) then return end
        for _, setting in ipairs(changes) do
            logger.info("Lingering: KOReader-instelling", setting.key, "=", tostring(setting.value))
            G_reader_settings:saveSetting(setting.key, setting.value)
        end
        G_reader_settings:flush()
    end)
end

--[[--
Automatische sync van kosync blijft alleen aan als wifi zonder vragen aan mag
(KOSync:init zet auto_sync anders uit op apparaten met hasSeamlessWifiToggle, zoals Kobo).
]]
function M.ensureAutoWifi()
    return try("ensureAutoWifi", function()
        local Device = require("device")
        if Device:hasSeamlessWifiToggle() and G_reader_settings:readSetting("wifi_enable_action") ~= "turn_on" then
            if not M.backupOnce(G_reader_settings.file) then return end
            logger.info("Lingering: KOReader-instelling wifi_enable_action = turn_on")
            G_reader_settings:saveSetting("wifi_enable_action", "turn_on")
            G_reader_settings:flush()
        end
    end)
end

return M
