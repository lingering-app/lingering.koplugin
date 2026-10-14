--[[--
Voortgangssync via de kosync-plugin: sessie (ophalen/wegschrijven/springen), haken voor het
beleid, binary, controle en account. Beslissingen: domain/sync_rules.lua, afloop: app/sync_service.lua.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local UIManager = require("ui/uimanager")
local logger = require("logger")
local try = require("lingering.koreader.try")
local GlobalSettings = require("lingering.koreader.global_settings")

local M = {}

local function kosyncLoggedIn(kosync)
    return kosync and kosync.settings and kosync.settings.username and kosync.settings.userkey
end

-- Verschil in percentage (0..1) waaronder twee standen als gelijk gelden.
--[[--
Een sync-sessie voor één kosync-instantie: alleen KOReader-aanroepen, geen beslissingen
(die staan in domain/sync_rules.lua, de afloop in app/sync_service.lua).
Geeft nil als kosync niet geladen of niet ingelogd is.

session:snapshot()            → { digest, progress, percent, metadata } (eigen stand, nu)
session:fetch(snap, cb)       → cb(ok, record) met record = nil | { percent, progress, device }
session:store(snap, cb)       → cb(ok)
session:jump(progress)        → naar een stand springen (KOSync:syncToProgress)
Gebruikt van de kosync-instantie: settings, path, device_id, getDocumentDigest,
getLastProgress, getLastPercent, getMetadata, syncToProgress; KOSyncClient van de plugin.
]]
function M.session(kosync)
    if not kosyncLoggedIn(kosync) then return nil end
    local ok, session = try("kosync.session", function()
        local Device = require("device")
        local KOSyncClient = require("KOSyncClient")
        local settings = kosync.settings
        local client = KOSyncClient:new{
            custom_url = settings.custom_server,
            service_spec = kosync.path .. "/api.json",
        }
        local session = {}
        function session:snapshot()
            return {
                digest = kosync:getDocumentDigest(),
                progress = kosync:getLastProgress(),
                percent = tonumber(kosync:getLastPercent()) or 0,
                metadata = kosync:getMetadata(),
            }
        end
        function session:fetch(snap, cb)
            client:get_progress(settings.username, settings.userkey, snap.digest, function(success, body)
                local record
                if success and type(body) == "table" and body.percentage ~= nil then
                    record = { percent = body.percentage, progress = body.progress, device = body.device }
                end
                cb(success and true or false, record)
            end)
        end
        function session:store(snap, cb)
            client:update_progress(
                settings.username,
                settings.userkey,
                snap.digest,
                snap.metadata,
                snap.progress,
                snap.percent,
                settings.kosync_hostname or Device.model,
                kosync.device_id,
                function(success, status)
                    if not success then logger.warn("Lingering: wegschrijven mislukt, status", tostring(status)) end
                    cb(success and true or false)
                end)
        end
        function session:jump(progress)
            kosync:syncToProgress(progress)
        end
        return session
    end)
    return ok and session or nil
end

--[[--
Stand bij het openen van het boek (KOSync:getLastPercent), om later te weten of je sinds het
openen verder gelezen hebt (domain/sync_rules.lua: opnieuw lezen van een gelezen boek).
]]
function M.rememberOpen(kosync)
    return try("rememberOpen", function()
        kosync._lingering_open_percent = tonumber(kosync:getLastPercent()) or 0
    end)
end

function M.openPercent(kosync)
    return kosync and kosync._lingering_open_percent
end

--- Tijdstempel van de laatste sync-poging op deze instantie (tegen dubbele pogingen).
function M.markActivity(kosync)
    kosync._lingering_last_sync = UIManager:getElapsedTimeSinceBoot()
end

function M.secondsSinceActivity(kosync)
    local last = kosync._lingering_last_sync
    if not last then return math.huge end
    return require("ui/time").to_s(UIManager:getElapsedTimeSinceBoot() - last)
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

--[[--
Koppelt de automatische momenten van kosync aan een beleid (app/sync_service.lua), op deze
kosync-instantie, vóór KOSync:onReaderReady (dat registerEvents aanroept):
- getProgress (openen via onReaderReady, ontwaken via _onResume, nieuwe verbinding via
  _onNetworkConnected)                         → policy.pull(kosync)
- updateProgress (slaapstand via _onSuspend, tussentijds) → policy.push(kosync, on_suspend)
- _onCloseDocument                             → policy.close(kosync)
- drainQueue: niets (de wachtrij van kosync schrijft blind weg).
Interactieve aanroepen (kosync-menu) blijven bij kosync zelf.
]]
function M.installRules(ui, policy)
    return try("installKosyncRules", function()
        local kosync = assert(ui.kosync, "kosync niet geladen")
        local getProgress = assert(kosync.getProgress, "KOSync:getProgress ontbreekt")
        local updateProgress = assert(kosync.updateProgress, "KOSync:updateProgress ontbreekt")
        assert(kosync._onCloseDocument and kosync.drainQueue, "kosync-handlers ontbreken")

        kosync.getProgress = function(this, ensure_networking, interactive)
            if interactive then return getProgress(this, ensure_networking, interactive) end
            policy.pull(this)
        end
        kosync.updateProgress = function(this, ensure_networking, interactive, on_suspend)
            if interactive then return updateProgress(this, ensure_networking, interactive, on_suspend) end
            policy.push(this, on_suspend)
        end
        kosync._onCloseDocument = function(this)
            -- Zoals KOSync:_onCloseDocument: Suspend/Resume-handlers uit tijdens het sluiten.
            this.onResume = nil
            this.onSuspend = nil
            policy.close(this)
        end
        kosync.drainQueue = function()
            logger.info("Lingering: kosync-wachtrij overgeslagen (nooit blind wegschrijven)")
        end
    end) and M.rememberOpen(ui.kosync)
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
        local _ = require("lingering.l10n.gettext")
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

-- Account en client uit kosync.lua (gebruiker, userkey, server), zoals KOSync ze gebruikt,
-- voor boeken die niet open zijn. nil als kosync niet ingelogd is.
local function accountClient()
    local DataStorage = require("datastorage")
    local KOSyncClient = require("KOSyncClient")
    local LuaSettings = require("luasettings")
    local class = pluginClass("kosync")
    local store = (class and class.settings_obj)
        or LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua")
    local settings = store:readSetting("settings") or {}
    if not (settings.username and settings.userkey) then return nil end
    local client = KOSyncClient:new{
        custom_url = settings.custom_server,
        service_spec = kosyncServiceSpec(),
    }
    return settings, client
end

--[[--
Een boek als uit (100%) wegschrijven zonder het te openen: KOSyncClient:update_progress
met percentage 1, zoals KOSync:updateProgress, met G_reader_settings "device_id".
position = Books.syncPosition(file). done(ok) volgt als de server antwoordt; false als kosync
niet ingelogd is.
]]
function M.storeFinished(position, done)
    local ok, started = try("storeFinished", function()
        local Device = require("device")
        local settings, client = accountClient()
        if not settings then return false end
        client:update_progress(
            settings.username, settings.userkey, position.digest, nil, position.progress, 1,
            settings.kosync_hostname or Device.model, G_reader_settings:readSetting("device_id"),
            function(success, status)
                if not success then logger.warn("Lingering: uit wegschrijven mislukt, status", tostring(status)) end
                if done then done(success and true or false) end
            end)
        return true
    end)
    if not (ok and started) and done then done(false) end
end

--[[--
Leestijd per dag delen via de stats-API naast kosync (zoals crosspoint-sync), op dezelfde server
en met dezelfde inlog: headers x-auth-user en x-auth-key (md5 van het wachtwoord), uit
kosync.lua. Korte timeouts zoals KOSyncClient (PROGRESS_TIMEOUTS); synchroon.
Geeft de HTTP-code (of nil zonder antwoord/niet ingelogd) en de gedecodeerde JSON.
]]
local STATS_TIMEOUTS = { 2, 5 }

local function statsRequest(method, path, body)
    local settings = accountClient()
    if not (settings and settings.custom_server) then return nil end
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local JSON = require("json")
    local payload = body and JSON.encode(body) or nil
    local sink = {}
    socketutil:set_timeout(STATS_TIMEOUTS[1], STATS_TIMEOUTS[2])
    local code = socket.skip(1, http.request{
        url = settings.custom_server:gsub("/+$", "") .. path,
        method = method,
        headers = {
            ["Accept"] = "application/json",
            ["Accept-Encoding"] = "identity",
            ["Content-Type"] = payload and "application/json" or nil,
            ["Content-Length"] = payload and tostring(#payload) or nil,
            ["x-auth-user"] = settings.username,
            ["x-auth-key"] = settings.userkey,
        },
        source = payload and ltn12.source.string(payload) or nil,
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if type(code) ~= "number" then return nil end
    local ok, decoded = pcall(JSON.decode, table.concat(sink))
    return code, ok and type(decoded) == "table" and decoded or nil
end

--[[--
Leestijd van dit apparaat versturen: PUT /api/v1/stats/global met de momentopname
(snapshot: v, sessions, seconds, pages, completed, tod, dow, anchor_day, history_b64, streak;
verplicht volgens crosspoint-sync) plus device_id, device en daily = { { date, seconds }, ... }
(hooguit 20 dagen per keer; weggelaten als leeg). device_id en device zoals kosync ze stuurt
(G_reader_settings "device_id", kosync_hostname of Device.model). Geeft de HTTP-code of nil.
]]
function M.pushStats(daily, snapshot)
    local ok, code = try("pushStats", function()
        local Device = require("device")
        local settings = accountClient()
        if not settings then return nil end
        local body = {}
        for key, value in pairs(snapshot or {}) do body[key] = value end
        body.device_id = G_reader_settings:readSetting("device_id")
        body.device = settings.kosync_hostname or Device.model
        if daily and #daily > 0 then body.daily = daily end
        return (statsRequest("PUT", "/api/v1/stats/global", body))
    end)
    return ok and code or nil
end

--[[--
Leestijd van alle apparaten samen: GET /api/v1/stats/summary → { daily = { { date, seconds } } }.
Geeft de HTTP-code (of nil) en bij 200 het gedecodeerde antwoord (of nil als het geen JSON
was); controleren en omzetten: StatsSync.parseSummary.
]]
function M.fetchStats()
    local ok, code, days = try("fetchStats", function()
        local code, body = statsRequest("GET", "/api/v1/stats/summary")
        if code ~= 200 then return code end
        return code, body
    end)
    if not ok then return nil end
    return code, days
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
