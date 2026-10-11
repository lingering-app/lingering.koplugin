--[[--
Voortgangssync via de kosync-plugin: controle, account, binary, regels, vergelijken.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local UIManager = require("ui/uimanager")
local logger = require("logger")
local try = require("lingering.koreader.try")
local GlobalSettings = require("lingering.koreader.global_settings")
local Network = require("lingering.koreader.network")

local M = {}

local function kosyncLoggedIn(kosync)
    return kosync and kosync.settings and kosync.settings.username and kosync.settings.userkey
end

-- Verschil in percentage (0..1) waaronder twee standen als gelijk gelden.
local PERCENT_EPSILON = 0.0005

--[[--
Voortgang vergelijken volgens "verder wint" en "nooit blind wegschrijven":
1. momentopname van de eigen stand (digest, progress, percentage, metadata), want bij
   sluiten is het document weg als het antwoord binnenkomt;
2. ophalen (KOSyncClient:get_progress);
3. server verder → springen (KOSync:syncToProgress) als opts.jump, anders niets;
   apparaat verder of geen stand op de server → wegschrijven (update_progress);
   gelijk → niets; ophalen mislukt → níets wegschrijven.
done(ok) volgt altijd precies één keer.
Gebruikt van de kosync-instantie: settings, path, device_id, getDocumentDigest,
getLastProgress, getLastPercent, getMetadata, syncToProgress.
]]
function M.reconcile(kosync, opts, done)
    local finished = false
    local function finish(ok)
        if finished then return end
        finished = true
        if done then done(ok) end
    end
    if not kosyncLoggedIn(kosync) then
        logger.warn("Lingering: voortgang niet gesynchroniseerd, kosync niet ingelogd")
        finish(false)
        return
    end
    local ok = try("reconcile", function()
        local Device = require("device")
        local KOSyncClient = require("KOSyncClient")
        local settings = kosync.settings
        kosync._lingering_last_reconcile = UIManager:getElapsedTimeSinceBoot()
        local snapshot = {
            digest = kosync:getDocumentDigest(),
            progress = kosync:getLastProgress(),
            percent = tonumber(kosync:getLastPercent()) or 0,
            metadata = kosync:getMetadata(),
        }
        local client = KOSyncClient:new{
            custom_url = settings.custom_server,
            service_spec = kosync.path .. "/api.json",
        }

        local function push()
            client:update_progress(
                settings.username,
                settings.userkey,
                snapshot.digest,
                snapshot.metadata,
                snapshot.progress,
                snapshot.percent,
                settings.kosync_hostname or Device.model,
                kosync.device_id,
                function(success, status)
                    logger.info("Lingering: voortgang weggeschreven:", success and "ok" or ("fout " .. tostring(status)))
                    finish(success and true or false)
                end)
        end

        client:get_progress(settings.username, settings.userkey, snapshot.digest, function(success, body)
            local action = "fail"
            local server_percent
            local cb_ok, err = pcall(function()
                if not success then return end
                if type(body) ~= "table" or body.percentage == nil then
                    action = "push" -- nog geen stand op de server
                    return
                end
                server_percent = tonumber(body.percentage)
                if not server_percent then return end
                if server_percent > snapshot.percent + PERCENT_EPSILON then
                    action = opts.jump and "jump" or "none"
                elseif server_percent < snapshot.percent - PERCENT_EPSILON then
                    action = "push"
                else
                    action = "none"
                end
                if action == "jump" then
                    kosync:syncToProgress(body.progress)
                end
            end)
            if not cb_ok then
                logger.warn("Lingering: voortgang vergelijken mislukt:", err)
                action = "fail"
            end
            logger.info("Lingering: voortgang", action, "(server", tostring(server_percent), "hier", snapshot.percent .. ")")
            if action == "push" then
                if not pcall(push) then finish(false) end
            else
                finish(action ~= "fail")
            end
        end)
    end)
    if not ok then finish(false) end
end

--[[--
Sync-knop in het boek: wifi aan zonder te vragen, reconcile met springen, en wifi weer uit
als hij uit stond. done(ok).
]]
function M.syncNow(ui, done)
    local kosync = ui.kosync
    if not kosyncLoggedIn(kosync) then
        logger.warn("Lingering: synchroniseren niet mogelijk, kosync niet ingelogd of niet geladen")
        done(false)
        return
    end
    if not Network.isWifiOn() then
        local finish = done
        done = function(ok)
            logger.info("Lingering: wifi weer uit na synchroniseren")
            Network.disableWifi()
            finish(ok)
        end
    end
    -- Ook voor de verbinding er is: KOSync:_onNetworkConnected mag niet tegelijk reconcilen.
    kosync._lingering_last_reconcile = UIManager:getElapsedTimeSinceBoot()
    local started = Network.turnOnWifiThen(function()
        M.reconcile(kosync, { jump = true }, done)
    end)
    if not started then done(false) end
end

--[[--
Sync herkent een boek altijd aan de inhoud: checksum_method = BINARY (0), zoals
KOSync:getDocumentDigest het leest. Zet het terug als het (bijv. via het volledige menu)
op bestandsnaam (1) staat.
]]
function M.ensureBinary(ui)
    return try("ensureKosyncBinary", function()
        local kosync = assert(ui.kosync, "kosync niet geladen")
        if kosync.settings and kosync.settings.checksum_method ~= 0 then
            logger.info("Lingering: kosync checksum_method = binary")
            kosync.settings.checksum_method = 0
            kosync.updated = true
        end
    end)
end

-- Recent al vergeleken (sync-knop, openen)? Dan niet nog eens.
local RECONCILE_DEBOUNCE = 15
local function recentlyReconciled(kosync)
    local last = kosync._lingering_last_reconcile
    if not last then return false end
    local time = require("ui/time")
    return time.to_s(UIManager:getElapsedTimeSinceBoot() - last) < RECONCILE_DEBOUNCE
end

--[[--
Kosync volgt "verder wint" en schrijft nooit blind weg. Vervangt op deze kosync-instantie
(vóór KOSync:onReaderReady, dat registerEvents aanroept):
- getProgress (openen via onReaderReady, ontwaken via _onResume, nieuwe verbinding via
  _onNetworkConnected): zonder verbinding stil overslaan, anders reconcile met springen;
- updateProgress (slaapstand via _onSuspend, tussentijds): alleen met verbinding reconcile
  zonder springen, nooit wifi aanzetten; bij slaapstand daarna wifi uit (zoals kosync);
- _onCloseDocument: alleen met verbinding reconcile; offline niets (geen blinde wachtrij);
- drainQueue: niets (de wachtrij zou blind wegschrijven).
Interactieve aanroepen (kosync-menu) blijven bij kosync zelf.
]]
function M.installRules(ui)
    return try("installKosyncRules", function()
        local kosync = assert(ui.kosync, "kosync niet geladen")
        local getProgress = assert(kosync.getProgress, "KOSync:getProgress ontbreekt")
        local updateProgress = assert(kosync.updateProgress, "KOSync:updateProgress ontbreekt")
        assert(kosync._onCloseDocument and kosync.drainQueue, "kosync-handlers ontbreken")

        kosync.getProgress = function(this, ensure_networking, interactive)
            if interactive then return getProgress(this, ensure_networking, interactive) end
            if not Network.isOnline() then
                logger.info("Lingering: geen verbinding, voortgang ophalen overgeslagen")
                return
            end
            if recentlyReconciled(this) then return end
            -- Eén nieuwe poging als ophalen mislukt (bijv. net na het openen, netwerk nog niet klaar).
            M.reconcile(this, { jump = true }, function(ok)
                if ok then return end
                UIManager:scheduleIn(3, function()
                    if Network.isOnline() then M.reconcile(this, { jump = true }) end
                end)
            end)
        end

        kosync.updateProgress = function(this, ensure_networking, interactive, on_suspend)
            if interactive then return updateProgress(this, ensure_networking, interactive, on_suspend) end
            local function afterwards()
                if on_suspend then Network.disableWifi() end
            end
            -- Nooit wifi aanzetten voor automatisch wegschrijven (ook niet bij slaapstand,
            -- waar kosync ensure_networking vraagt): alleen als er al verbinding is.
            if Network.isOnline() then
                M.reconcile(this, { jump = false }, afterwards)
            else
                logger.info("Lingering: geen verbinding, voortgang wegschrijven overgeslagen")
            end
        end

        kosync._onCloseDocument = function(this)
            -- Zoals KOSync:_onCloseDocument: Suspend/Resume-handlers uit tijdens het sluiten.
            this.onResume = nil
            this.onSuspend = nil
            if Network.isOnline() then
                M.reconcile(this, { jump = false })
            else
                logger.info("Lingering: offline gesloten, voortgang volgt bij de volgende sync")
            end
        end

        kosync.drainQueue = function()
            logger.info("Lingering: kosync-wachtrij overgeslagen (nooit blind wegschrijven)")
        end
    end)
end

--- Pad naar api.json van de kosync-plugin (naast KOSyncClient.lua).
local function kosyncServiceSpec()
    local client_file = package.searchpath("KOSyncClient", package.path)
    return assert(client_file, "KOSyncClient niet gevonden"):match("^(.*)/[^/]*$") .. "/api.json"
end

--[[--
Controle van de syncserver: KOSyncClient:authorize met userkey = md5(wachtwoord),
zoals KOSync:doLogin. Geeft true of false, reden.
]]
function M.check(sync_url, username, password)
    local ok, success, reason = try("checkKosync", function()
        local KOSyncClient = require("KOSyncClient")
        local md5 = require("ffi/sha2").md5
        local _ = require("gettext")
        local client = KOSyncClient:new{
            custom_url = sync_url,
            service_spec = kosyncServiceSpec(),
        }
        local call_ok, authorized, body = pcall(client.authorize, client, username, md5(password))
        if not call_ok then
            return false, _("fout bij verbinden")
        elseif authorized then
            return true
        elseif body == nil then
            return false, _("server niet bereikbaar")
        end
        return false, (type(body) == "table" and body.message) or _("gebruikersnaam of wachtwoord onjuist")
    end)
    if not ok then return false, "?" end
    return success, reason
end

--- De geladen plugin-klasse met deze naam (PluginLoader.enabled_plugins), of nil.
local function pluginClass(name)
    local PluginLoader = require("pluginloader")
    for _, plugin in ipairs(PluginLoader.enabled_plugins or {}) do
        if plugin.name == name then return plugin end
    end
end

--[[--
Schrijft de kosync-instellingen in <settings>/kosync.lua (sleutel "settings"):
custom_server, username, userkey = md5(wachtwoord), auto_sync aan,
sync_forward = SILENT (2), sync_backward = PROMPT (1) (SYNC_STRATEGY in kosync main.lua),
checksum_method = BINARY (0) (CHECKSUM_METHOD in kosync main.lua).
Gebruikt het gedeelde KOSync.settings_obj als kosync dat deze sessie al opende.
]]
function M.writeAccount(sync_url, username, password)
    return try("writeKosyncAccount", function()
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local md5 = require("ffi/sha2").md5
        local file = DataStorage:getSettingsDir() .. "/kosync.lua"
        assert(GlobalSettings.backupOnce(file), "back-up van kosync.lua mislukt")

        local class = pluginClass("kosync")
        local store = (class and class.settings_obj) or LuaSettings:open(file)
        local settings = store:readSetting("settings") or {}
        settings.custom_server = sync_url
        settings.username = username
        settings.userkey = md5(password)
        settings.auto_sync = true
        settings.sync_forward = 2
        settings.sync_backward = 1
        -- Boek herkennen aan de inhoud (CHECKSUM_METHOD.BINARY = 0), niet aan de bestandsnaam.
        settings.checksum_method = 0
        store:saveSetting("settings", settings)
        store:flush()
        logger.info("Lingering: kosync ingesteld voor gebruiker", username)
    end)
end

return M
