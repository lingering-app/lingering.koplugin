--[[--
OPDS via de opds-plugin: inloggegevens, catalogus ophalen, downloaden, account.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local logger = require("logger")
local try = require("lingering.koreader.try")
local GlobalSettings = require("lingering.koreader.global_settings")

local M = {}

--[[--
OPDS (plugins/opds.koplugin). Inloggegevens staan in <settings>/opds.lua, lijst "servers",
waar de OPDS-plugin ze zelf ook bewaart. Wachtwoorden worden nooit gelogd.
]]
local function sameUrl(a, b)
    return a and b and (a:gsub("/+$", "") == b:gsub("/+$", ""))
end

--- Gebruikersnaam en wachtwoord van de server met dit adres, of nil.
function M.credentials(opds_url)
    local ok, user, pass = try("opdsCredentials", function()
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local servers = LuaSettings:open(DataStorage:getSettingsDir() .. "/opds.lua"):readSetting("servers") or {}
        for _, server in ipairs(servers) do
            if sameUrl(server.url, opds_url) then
                return server.username, server.password
            end
        end
    end)
    if ok then return user, pass end
end

--[[--
Een "kaal" OPDSBrowser-object: de methoden van de OPDS-plugin zonder het scherm.
sync = true slaat in genItemTableFromCatalog het ophalen van zoek- en facetlinks over.
]]
function M.client(username, password)
    local ok, client = try("opdsClient", function()
        local OPDSBrowser = require("opdsbrowser")
        return setmetatable({
            root_catalog_username = username,
            root_catalog_password = password,
            sync = true,
        }, { __index = OPDSBrowser })
    end)
    return ok and client or nil
end

--[[--
Haalt één pagina van een catalogus op via OPDSBrowser:genItemTableFromURL
(parser van de plugin, OPDS 1 en 2). Geeft { items = {...}, next = url|nil } of nil.
Elk item: { title, author, url (map) | acquisitions (boek), thumbnail, image }.
]]
function M.fetchPage(client, feed_url)
    local ok, page = try("opdsFetchPage", function()
        local item_table = client:genItemTableFromURL(feed_url)
        local items = {}
        for _, item in ipairs(item_table) do
            table.insert(items, item)
        end
        return { items = items, next = item_table.hrefs and item_table.hrefs.next }
    end)
    return ok and page or nil
end

--- Bestandstype van een acquisitie-link (OPDSBrowser.getFiletype), bijv. "epub".
function M.filetype(acquisition)
    local ok, filetype = try("opdsFiletype", function()
        return require("opdsbrowser").getFiletype(acquisition)
    end)
    return ok and filetype or nil
end

--- Downloadt een boek met OPDSBrowser:downloadFile (toont zelf een melding bij een fout).
function M.download(client, local_path, remote_url, username, password)
    local ok, result = try("opdsDownload", client.downloadFile, client, local_path, remote_url, username, password)
    return ok and result == true
end

--[[--
Controle van de OPDS-catalogus voor het inlogscherm: één GET met inloggegevens.
Bewust geen OPDSBrowser:fetchFeed, want die toont zelf een melding; hier willen we
zelf zeggen wat er misging. Geeft true of false, reden.
]]
function M.check(opds_url, username, password)
    local ok, success, reason = try("checkOpds", function()
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socket = require("socket")
        local socketutil = require("socketutil")
        local _ = require("gettext")
        local sink = {}
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
        local code = socket.skip(1, http.request{
            url = opds_url,
            method = "GET",
            headers = {
                ["Accept-Encoding"] = "identity",
                ["Accept"] = "application/opds+json, application/atom+xml;profile=opds-catalog, */*",
            },
            sink = ltn12.sink.table(sink),
            user = username,
            password = password,
        })
        socketutil:reset_timeout()
        if type(code) ~= "number" then
            return false, _("server niet bereikbaar") .. " (" .. tostring(code) .. ")"
        elseif code == 401 or code == 403 then
            return false, _("gebruikersnaam of wachtwoord onjuist")
        elseif code ~= 200 then
            return false, _("server antwoordt met code") .. " " .. code
        end
        local first = table.concat(sink):match("^%s*(.)")
        if first ~= "<" and first ~= "{" then
            return false, _("geen geldige catalogus")
        end
        return true
    end)
    if not ok then return false, "?" end
    return success, reason
end

--[[--
Schrijft de OPDS-catalogus met inloggegevens in <settings>/opds.lua (lijst "servers"):
een bestaande ingang met hetzelfde adres wordt bijgewerkt, anders komt er een bij.
Een al geladen OPDS-instantie in de bestandsbeheerder (fm.opds.servers) krijgt dezelfde
wijziging, zodat die bij een eigen flush niets terugzet.
]]
function M.writeAccount(opds_url, username, password, fm)
    return try("writeOpdsAccount", function()
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local file = DataStorage:getSettingsDir() .. "/opds.lua"
        assert(GlobalSettings.backupOnce(file), "back-up van opds.lua mislukt")

        local function apply(servers)
            for _, server in ipairs(servers) do
                if sameUrl(server.url, opds_url) then
                    server.username, server.password = username, password
                    return
                end
            end
            table.insert(servers, { title = "Lingering", url = opds_url, username = username, password = password })
        end

        local store = LuaSettings:open(file)
        local servers = store:readSetting("servers") or {}
        apply(servers)
        store:saveSetting("servers", servers)
        store:flush()
        if fm and fm.opds and type(fm.opds.servers) == "table" and fm.opds.servers ~= servers then
            apply(fm.opds.servers)
        end
        logger.info("Lingering: OPDS-catalogus ingesteld voor gebruiker", username)
    end)
end

return M
