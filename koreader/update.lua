--[[--
Zelf-update vanaf een openbare GitHub-repo: tags ophalen, de zip van een tag downloaden,
uitpakken, controleren, de pluginmap verwisselen, opruimen, herstarten.
Onderdeel van de anti-corruption layer (koreader/): socket.http (HTTPS), json, ffi/archiver
(libarchive, zoals de archiveviewer-plugin), ffi/util.purgeDir, UIManager:askForRestart.
]]
local logger = require("logger")
local try = require("lingering.koreader.try")

local M = {}

local function httpGet(url, sink)
    local http = require("socket.http")
    local socket = require("socket")
    local socketutil = require("socketutil")
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request{
        url = url,
        headers = { ["Accept-Encoding"] = "identity", ["User-Agent"] = "lingering.koplugin" },
        sink = sink,
    })
    socketutil:reset_timeout()
    return code
end

--- Namen van alle tags in de repo ("eigenaar/naam"), of nil, fout.
function M.fetchTags(repo)
    local ok, tags, err = try("update.fetchTags", function()
        local ltn12 = require("ltn12")
        local JSON = require("json")
        local body = {}
        local code = httpGet("https://api.github.com/repos/" .. repo .. "/tags?per_page=100", ltn12.sink.table(body))
        if code ~= 200 then return nil, "GitHub antwoordt met " .. tostring(code) end
        local list = JSON.decode(table.concat(body))
        local names = {}
        for _, tag in ipairs(list or {}) do
            if type(tag) == "table" and type(tag.name) == "string" then
                table.insert(names, tag.name)
            end
        end
        return names
    end)
    if not ok then return nil, "fout bij ophalen" end
    return tags, err
end

--- Downloadt de zip van een tag (bijv. "v1.2.3") naar path. Alleen tags, geen branches.
function M.downloadTag(repo, tag, path)
    local ok, success = try("update.downloadTag", function()
        local ltn12 = require("ltn12")
        local file = assert(io.open(path, "wb"))
        local code = httpGet("https://codeload.github.com/" .. repo .. "/zip/refs/tags/" .. tag, ltn12.sink.file(file))
        if code ~= 200 then
            os.remove(path)
            logger.warn("Lingering: update downloaden mislukt, code", tostring(code))
            return false
        end
        return true
    end)
    return ok and success or false
end

--[[--
Pakt de zip uit naar dest_dir. De bovenste map van de GitHub-zip ("repo-tag/") valt weg;
alleen paden waarvoor include(pad) true geeft komen mee. Geeft het aantal bestanden.
]]
function M.extract(zip_path, dest_dir, include)
    local ok, count = try("update.extract", function()
        local Archiver = require("ffi/archiver")
        local util = require("util")
        local reader = Archiver.Reader:new()
        assert(reader:open(zip_path), "zip niet te openen")
        local files = 0
        for entry in reader:iterate() do
            local relative = entry.path:match("^[^/]+/(.+)$")
            if relative and entry.mode == "file" and include(relative) then
                local target = dest_dir .. "/" .. relative
                util.makePath(target:match("^(.*)/"))
                assert(reader:extractToPath(entry.path, target), "uitpakken mislukt: " .. relative)
                files = files + 1
            end
        end
        reader:close()
        return files
    end)
    return ok and count or 0
end

--- Controle vóór het verwisselen: _meta.lua en main.lua aanwezig, alle Lua-bestanden geldig.
function M.validate(dir)
    local ok, valid, err = try("update.validate", function()
        local lfs = require("libs/libkoreader-lfs")
        for _, required in ipairs({ "_meta.lua", "main.lua" }) do
            if lfs.attributes(dir .. "/" .. required, "mode") ~= "file" then
                return false, required .. " ontbreekt"
            end
        end
        local function walk(path)
            for name in lfs.dir(path) do
                if name ~= "." and name ~= ".." then
                    local full = path .. "/" .. name
                    local mode = lfs.attributes(full, "mode")
                    if mode == "directory" then
                        local sub_ok, sub_err = walk(full)
                        if not sub_ok then return false, sub_err end
                    elseif name:match("%.lua$") then
                        local chunk, load_err = loadfile(full)
                        if not chunk then return false, load_err end
                    end
                end
            end
            return true
        end
        return walk(dir)
    end)
    if not ok then return false, "controle mislukt" end
    return valid, err
end

--- Is de pluginmap een symlink (ontwikkelopstelling)? Dan nooit verwisselen.
function M.isSymlink(path)
    local ok, mode = try("update.isSymlink", function()
        return require("libs/libkoreader-lfs").symlinkattributes(path, "mode")
    end)
    return ok and mode == "link"
end

--[[--
Verwisselt de pluginmap: oude reservekopie weg, huidige → <map>.bak, nieuwe → <map>.
Mislukt de laatste stap, dan wordt de huidige teruggezet.
]]
function M.swap(new_dir, plugin_dir)
    local ok, swapped, err = try("update.swap", function()
        local ffiUtil = require("ffi/util")
        local lfs = require("libs/libkoreader-lfs")
        local backup = plugin_dir .. ".bak"
        if lfs.attributes(backup, "mode") then ffiUtil.purgeDir(backup) end
        local moved, move_err = os.rename(plugin_dir, backup)
        if not moved then return false, "huidige versie niet te verplaatsen: " .. tostring(move_err) end
        local placed, place_err = os.rename(new_dir, plugin_dir)
        if not placed then
            os.rename(backup, plugin_dir)
            return false, "nieuwe versie niet te plaatsen: " .. tostring(place_err)
        end
        return true
    end)
    if not ok then return false, "verwisselen mislukt" end
    return swapped, err
end

--- Verwijdert een map of bestand als het bestaat (restanten van een update).
function M.remove(path)
    return try("update.remove", function()
        local lfs = require("libs/libkoreader-lfs")
        local mode = lfs.attributes(path, "mode")
        if mode == "directory" then
            require("ffi/util").purgeDir(path)
        elseif mode then
            os.remove(path)
        end
    end)
end

--- Versie uit _meta.lua van een pluginmap, of nil.
function M.installedVersion(plugin_dir)
    local ok, version = try("update.installedVersion", function()
        local meta = dofile(plugin_dir .. "/_meta.lua")
        return meta and meta.version
    end)
    return ok and version or nil
end

--- Vraagt KOReader te herstarten (UIManager:askForRestart).
function M.askForRestart(message)
    return try("update.askForRestart", function()
        require("ui/uimanager"):askForRestart(message)
    end)
end

return M
