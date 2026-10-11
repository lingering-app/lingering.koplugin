--[[--
Zelf-update naar de nieuwste versie uit de openbare repo (config.update_repo).
- check(done): done{ status = "newer" | "current" | "error", latest, installed }
- install(tag, done): done(ok, reden) — downloaden, uitpakken (alleen pluginbestanden),
  controleren, verwisselen; de zip en een half uitgepakte map worden altijd opgeruimd.
- cleanup(): restanten van een vorige update weg (de .bak pas bij de eerste start van de
  nieuwe versie: tot dan is dat de weg terug).
Regels in domain/release.lua, KOReader-aanroepen in koreader/update.lua.
]]
local logger = require("logger")

local Config = require("lingering.config")
local Network = require("lingering.koreader.network")
local Release = require("lingering.domain.release")
local Update = require("lingering.koreader.update")

local UpdateService = {}

local function pluginDir()
    return require("lingering.plugin").dir
end

-- Restanten naast de pluginmap (zelfde schijf, zodat verwisselen een rename kan zijn).
local function paths()
    local dir = pluginDir():gsub("/+$", "")
    return {
        plugin = dir,
        new = dir .. ".new",
        backup = dir .. ".bak",
        zip = dir .. ".update.zip",
    }
end

function UpdateService.installedVersion()
    return Update.installedVersion(pluginDir())
end

function UpdateService.check(done)
    local installed = UpdateService.installedVersion()
    local started = Network.turnOnWifiThen(function()
        local tags, err = Update.fetchTags(Config.update_repo)
        if not tags then
            logger.warn("Lingering: update controleren mislukt:", tostring(err))
            done{ status = "error", installed = installed }
            return
        end
        local latest = Release.latest(tags)
        logger.info("Lingering: update, geïnstalleerd", tostring(installed), "nieuwste", tostring(latest))
        if latest and Release.isNewer(latest, installed) then
            done{ status = "newer", latest = latest, installed = installed }
        else
            done{ status = "current", latest = latest, installed = installed }
        end
    end)
    if not started then done{ status = "error", installed = installed } end
end

function UpdateService.install(tag, done)
    -- Wifi aan zonder te vragen (kan tussen controleren en bijwerken zijn weggevallen).
    local started = Network.turnOnWifiThen(function()
        UpdateService._install(tag, done)
    end)
    if not started then done(false, "geen verbinding") end
end

function UpdateService._install(tag, done)
    local p = paths()
    if Update.isSymlink(p.plugin) then
        logger.warn("Lingering: pluginmap is een symlink (ontwikkelversie), niet bijgewerkt")
        done(false, "ontwikkelversie")
        return
    end
    local function fail(reason)
        logger.warn("Lingering: update mislukt:", reason)
        Update.remove(p.new)
        Update.remove(p.zip)
        done(false, reason)
    end
    Update.remove(p.new)
    Update.remove(p.zip)
    if not Release.parse(tag) then return fail("geen geldige tag") end
    if not Update.downloadTag(Config.update_repo, tag, p.zip) then return fail("downloaden") end
    local count = Update.extract(p.zip, p.new, Release.includes)
    if count == 0 then return fail("uitpakken") end
    local valid, err = Update.validate(p.new)
    if not valid then return fail("controle: " .. tostring(err)) end
    local swapped, swap_err = Update.swap(p.new, p.plugin)
    if not swapped then return fail(tostring(swap_err)) end
    Update.remove(p.zip)
    logger.info("Lingering: bijgewerkt naar", tag, "(" .. count .. " bestanden)")
    done(true)
end

function UpdateService.cleanup()
    local p = paths()
    Update.remove(p.new)
    Update.remove(p.zip)
    Update.remove(p.backup)
end

function UpdateService.askForRestart(message)
    return Update.askForRestart(message)
end

return UpdateService
