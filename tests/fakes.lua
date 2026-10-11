--[[--
Nep-versies voor unit tests zonder KOReader:
- algemene KOReader-bibliotheken (logger, ui/uimanager, ui/time);
- adapters uit koreader/ die app/ gebruikt (kosync, network), als instelbare singletons.
Fakes.reset() zet alles terug; tests passen de velden per geval aan.
]]
local Fakes = {}

local function noop() end

Fakes.logger = { info = noop, warn = noop, dbg = noop, err = noop }

-- UIManager: geplande functies worden pas uitgevoerd met Fakes.runScheduled().
Fakes.UIManager = {}
function Fakes.UIManager:scheduleIn(_, fn) table.insert(Fakes.scheduled, fn) end
function Fakes.UIManager:nextTick(fn) table.insert(Fakes.scheduled, fn) end
function Fakes.UIManager:getElapsedTimeSinceBoot() return Fakes.now end

Fakes.time = { to_s = function(t) return t end, s = function(s) return s end }

function Fakes.runScheduled()
    local queue = Fakes.scheduled
    Fakes.scheduled = {}
    for _, fn in ipairs(queue) do fn() end
end

-- Nep-netwerk.
Fakes.network = {}
function Fakes.network.isOnline() return Fakes.state.online end
function Fakes.network.isWifiOn() return Fakes.state.wifi_on end
function Fakes.network.disableWifi() Fakes.calls.disable_wifi = (Fakes.calls.disable_wifi or 0) + 1 end
function Fakes.network.turnOnWifiThen(fn)
    Fakes.calls.turn_on_wifi = (Fakes.calls.turn_on_wifi or 0) + 1
    if Fakes.state.wifi_fails then return false end
    Fakes.state.online, Fakes.state.wifi_on = true, true
    fn()
    return true
end

-- Nep-kosync: één sessie met instelbare server- en eigen stand.
Fakes.kosync = {}
function Fakes.kosync.session(handle)
    if not Fakes.state.logged_in then return nil end
    local session = {}
    function session:snapshot()
        return { digest = "d", progress = "local-pos", percent = Fakes.state.local_percent, metadata = {} }
    end
    function session:fetch(_, cb)
        Fakes.calls.fetch = (Fakes.calls.fetch or 0) + 1
        cb(Fakes.state.fetch_ok, Fakes.state.record)
    end
    function session:store(snap, cb)
        Fakes.calls.store = snap
        cb(Fakes.state.store_ok)
    end
    function session:jump(progress)
        Fakes.calls.jump = progress
    end
    return session
end
function Fakes.kosync.markActivity() Fakes.state.last_activity = Fakes.now end
function Fakes.kosync.secondsSinceActivity()
    if not Fakes.state.last_activity then return math.huge end
    return Fakes.now - Fakes.state.last_activity
end

-- Nep-opslag en -bestanden voor app/library_service.
local function newStore()
    local data = {}
    return {
        readSetting = function(_, key) return data[key] end,
        saveSetting = function(_, key, value) data[key] = value end,
        flush = function() Fakes.calls.flush = (Fakes.calls.flush or 0) + 1 end,
    }
end
Fakes.luasettings = { open = function() return Fakes.store end }
Fakes.datastorage = { getDataDir = function() return "/nep" end, getSettingsDir = function() return "/nep/settings" end }
Fakes.lfs = { attributes = function(path, what) if Fakes.state.files[path] then return what == "mode" and "file" or {} end end }
Fakes.util = { makePath = noop, getSafeFilename = function(name) return name end }
Fakes.sha2 = { md5 = function(text) return "md5:" .. tostring(text) end }
Fakes.opds = { filetype = function() return "epub" end, credentials = function() return "lezer", "geheim" end }

Fakes.books = {}
function Fakes.books.homeFolder() return "/boeken" end
function Fakes.books.percent(path) return Fakes.state.local_percents[path] end
function Fakes.books.partialDigest(path) return "digest:" .. path end

function Fakes.kosync.fetchStored(digest, cb)
    Fakes.calls.fetch_stored = (Fakes.calls.fetch_stored or 0) + 1
    local record = Fakes.state.server_records[digest]
    cb(Fakes.state.fetch_ok, record)
end

function Fakes.reset()
    Fakes.scheduled = {}
    Fakes.now = 1000
    Fakes.calls = {}
    Fakes.state = {
        online = true, wifi_on = true, wifi_fails = false,
        logged_in = true, local_percent = 0.5,
        fetch_ok = true, record = nil, store_ok = true,
        files = {}, local_percents = {}, server_records = {},
    }
    Fakes.store = newStore()
end

function Fakes.install()
    package.loaded["logger"] = Fakes.logger
    package.loaded["ui/uimanager"] = Fakes.UIManager
    package.loaded["ui/time"] = Fakes.time
    package.loaded["lingering.koreader.network"] = Fakes.network
    package.loaded["lingering.koreader.kosync"] = Fakes.kosync
    package.loaded["lingering.koreader.books"] = Fakes.books
    package.loaded["lingering.koreader.opds"] = Fakes.opds
    package.loaded["luasettings"] = Fakes.luasettings
    package.loaded["datastorage"] = Fakes.datastorage
    package.loaded["libs/libkoreader-lfs"] = Fakes.lfs
    package.loaded["util"] = Fakes.util
    package.loaded["ffi/sha2"] = Fakes.sha2
    Fakes.reset()
end

return Fakes
