--[[--
Netwerk: wifi aan/uit, verbonden/online, KOReaders netwerkscherm.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

--- Online? (NetworkMgr:isOnline)
function M.isOnline()
    local ok, online = try("isOnline", function()
        return require("ui/network/manager"):isOnline()
    end)
    return ok and online or false
end

--[[--
Zet wifi aan zonder te vragen en voert fn uit zodra er verbinding is
(NetworkMgr:turnOnWifiAndWaitForConnection). Al online: fn meteen.
Geeft false als verbinden direct mislukt of al een poging loopt (fn komt dan niet).
]]
function M.turnOnWifiThen(fn)
    local ok, started = try("turnOnWifiThen", function()
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isOnline() then
            fn()
            return true
        end
        -- Geeft het "Verbinden…"-venster als hij gaat verbinden; nil als fn al direct liep of
        -- bij EBUSY (fn komt dan nooit), false als verbinden mislukte.
        local called = false
        local result = NetworkMgr:turnOnWifiAndWaitForConnection(function()
            called = true
            fn()
        end)
        return called or (result ~= nil and result ~= false)
    end)
    return ok and started
end

--- Wifi-radio aan? (NetworkMgr:isWifiOn)
function M.isWifiOn()
    local ok, on = try("isWifiOn", function()
        return require("ui/network/manager"):isWifiOn()
    end)
    return ok and on or false
end

--- Verbonden met een netwerk? (NetworkMgr:isConnected; op Kobo ifHasAnAddress)
function M.isConnected()
    local ok, connected = try("isConnected", function()
        return require("ui/network/manager"):isConnected()
    end)
    return ok and connected or false
end

--[[--
Wifi stil uit (NetworkMgr:disableWifi, zonder "Turning off Wi-Fi…"-melding).
interactive = true zet wifi_was_on op false, zodat wifi bij ontwaken niet terugkomt.
]]
function M.disableWifi()
    return try("disableWifi", function()
        require("ui/network/manager"):disableWifi(nil, true)
    end)
end

--[[--
KOReaders eigen netwerkscherm (ui/widget/networksetting): scannen, netwerk kiezen,
wachtwoord. Zoals lang drukken op "Wi-Fi connection" in KOReaders menu
(NetworkMgr:getWifiToggleMenuTable): wifi uit → toggleWifiOn met long_press; wifi aan →
reconnectOrShowNetworkMenu, met wifi_toggle_long_press zodat de lijst ook bij een bestaande
verbinding verschijnt. done() volgt na verbinden.
]]
function M.showNetworkList(done)
    return try("showNetworkList", function()
        local NetworkMgr = require("ui/network/manager")
        NetworkMgr:queryNetworkState()
        if NetworkMgr.is_wifi_on then
            NetworkMgr.wifi_toggle_long_press = true
            NetworkMgr:reconnectOrShowNetworkMenu(done, true)
        else
            NetworkMgr:toggleWifiOn(done, true, true)
        end
    end)
end

--- Wifi aan/uit (NetworkMgr:toggleWifiOn/toggleWifiOff). Alleen als het apparaat het kan.
function M.setWifi(on, callback)
    return try("toggleWifi", function()
        local NetworkMgr = require("ui/network/manager")
        if on then
            NetworkMgr:toggleWifiOn(callback, false, true)
        else
            NetworkMgr:toggleWifiOff(callback, true)
        end
    end)
end

return M
