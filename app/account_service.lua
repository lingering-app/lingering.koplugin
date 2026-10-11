--[[--
Account: inloggen met gebruikersnaam en wachtwoord.
verify(username, password) → ok, stap ("opds" | "kosync"), reden (reden alleen voor de log)
save(username, password, fm) → ok : OPDS-catalogus en kosync wegschrijven, automatische sync
  mogelijk maken, setup als voltooid markeren.
Gegevens worden alleen opgeslagen na een geslaagde verify (de UI roept save pas dan aan).
Wachtwoorden worden nooit gelogd.
]]
local logger = require("logger")

local Config = require("lingering.config")
local GlobalSettings = require("lingering.koreader.global_settings")
local Kosync = require("lingering.koreader.kosync")
local Opds = require("lingering.koreader.opds")
local Session = require("lingering.app.session")

local AccountService = {}

function AccountService.verify(username, password)
    local opds_ok, opds_reason = Opds.check(Config.opds_url, username, password)
    if not opds_ok then
        logger.warn("Lingering: inloggen mislukt bij OPDS", tostring(opds_reason))
        return false, "opds", opds_reason
    end
    local sync_ok, sync_reason = Kosync.check(Config.sync_url, username, password)
    if not sync_ok then
        logger.warn("Lingering: inloggen mislukt bij kosync", tostring(sync_reason))
        return false, "kosync", sync_reason
    end
    return true
end

function AccountService.save(username, password, fm)
    local written = Opds.writeAccount(Config.opds_url, username, password, fm)
        and Kosync.writeAccount(Config.sync_url, username, password)
    if not written then return false end
    GlobalSettings.ensureAutoWifi()
    Session:save("lingering_setup_done", true)
    logger.info("Lingering: setup voltooid")
    return true
end

--- Gebruikersnaam van het huidige account (om het veld vooraf in te vullen), of nil.
function AccountService.currentUsername()
    return (Opds.credentials(Config.opds_url))
end

return AccountService
