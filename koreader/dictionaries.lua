--[[--
Woordenboeken: downloaden en kiezen via KOReaders eigen woordenboekmodule.
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.

- KOReaders lijst met downloadbare woordenboeken: ui/data/dictionaries.lua (naam, taal, url).
  Wij verwijzen op naam; de link houdt KOReader bij.
- Downloaden: ReaderDictionary:downloadDictionary (ook in de FileManager als fm.dictionary):
  vraagt bevestiging met de grootte, downloadt, pakt uit in <data_dir>/<veilige naam> en laadt
  de woordenboeken opnieuw.
- Aan/uit: G_reader_settings "dicts_disabled" (sleutel = pad van het .ifo-bestand), zoals
  ReaderDictionary:showDictionariesMenu.
]]
local try = require("lingering.koreader.try")

local M = {}

--- Het woordenboek met deze naam uit KOReaders lijst (een kopie), of nil.
function M.entry(name)
    local ok, entry = try("dictionaryEntry", function()
        for _, dict in ipairs(require("ui/data/dictionaries")) do
            if dict.name == name then
                local copy = {}
                for k, v in pairs(dict) do copy[k] = v end
                return copy
            end
        end
    end)
    return ok and entry or nil
end

-- Map waarin KOReader dit woordenboek uitpakt (zoals in downloadDictionary).
local function dictDir(fm, name)
    local util = require("util")
    local ffiUtil = require("ffi/util")
    local data_dir = fm.dictionary.data_dir
    return data_dir .. "/" .. util.getSafeFilename(name, ffiUtil.realpath(data_dir))
end

-- De .ifo-bestanden van een geïnstalleerd woordenboek (leeg als het er niet is).
local function ifoFiles(fm, name)
    local util = require("util")
    local lfs = require("libs/libkoreader-lfs")
    local dir = dictDir(fm, name)
    local files = {}
    if lfs.attributes(dir, "mode") ~= "directory" then return files end
    util.findFiles(dir, function(path, filename)
        if util.getFileNameSuffix(filename) == "ifo" then table.insert(files, path) end
    end)
    return files
end

--- Staat dit woordenboek op het apparaat?
function M.isInstalled(fm, name)
    local ok, installed = try("dictionaryInstalled", function()
        return #ifoFiles(fm, name) > 0
    end)
    return ok and installed or false
end

--- Staat het aan (geïnstalleerd en niet uitgezet in dicts_disabled)?
function M.isEnabled(fm, name)
    local ok, enabled = try("dictionaryEnabled", function()
        local files = ifoFiles(fm, name)
        if #files == 0 then return false end
        local disabled = G_reader_settings:readSetting("dicts_disabled") or {}
        for _, file in ipairs(files) do
            if disabled[file] then return false end
        end
        return true
    end)
    return ok and enabled or false
end

--[[--
Downloaden met KOReaders eigen afloop (bevestiging met grootte, "Downloading…", uitpakken).
Wifi moet al aan zijn. done() volgt als KOReader klaar is, ook na annuleren of een fout;
kijk daarna met isInstalled of het gelukt is.
]]
function M.download(fm, entry, done)
    return try("downloadDictionary", function()
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            -- In onze coroutine loopt downloadDictionary hierin door (ook de bevestiging).
            local ok, err = pcall(fm.dictionary.downloadDictionary, fm.dictionary, entry)
            if not ok then require("logger").warn("Lingering: woordenboek downloaden mislukt:", err) end
            if done then done() end
        end)
    end)
end

--[[--
Kiezen: het woordenboek `chosen` aan, de andere uit `managed` (namen) uit. Woordenboeken
die niet in `managed` staan blijven zoals ze zijn.
]]
function M.choose(fm, chosen, managed)
    return try("chooseDictionary", function()
        local disabled = G_reader_settings:readSetting("dicts_disabled") or {}
        for _, name in ipairs(managed) do
            for _, file in ipairs(ifoFiles(fm, name)) do
                disabled[file] = (name ~= chosen) or nil
            end
        end
        G_reader_settings:saveSetting("dicts_disabled", disabled)
        fm.dictionary.dicts_disabled = disabled
    end)
end

return M
