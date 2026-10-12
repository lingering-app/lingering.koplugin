-- Controleert, zonder KOReader te laden:
-- 1. elke aanroep X.f( / X:f( op een module uit require("lingering.…") bestaat in dat bestand;
-- 2. domain/ laadt niets buiten domain/ (business rules los van KOReader);
-- 3. ui/, app/ en main.lua gebruiken geen KOReader-internals (G_reader_settings, NetworkMgr,
--    Device:has…): dat gaat via koreader/, de anti-corruption layer.
-- Gebruik: luajit tools/check_refs.lua <pluginmap> <bestand>...
local root = arg[1]
local bad = 0

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function moduleFile(name)
    return root .. "/" .. name:gsub("%.", "/") .. ".lua"
end

local defined_cache = {}
local function defines(name, fn)
    local src = defined_cache[name]
    if src == nil then
        src = read(moduleFile(name)) or false
        defined_cache[name] = src
    end
    if not src then return false end
    return src:find("function%s+[%w_]+[.:]" .. fn .. "%s*%(") ~= nil
        or src:find("\n[%w_]+%." .. fn .. "%s*=") ~= nil
        or src:find("\n%s*" .. fn .. "%s*=%s*function") ~= nil
end

for i = 2, #arg do
    local path = arg[i]
    local rel = path:sub(#root + 2)
    local src = read(path) or ""
    local aliases = {}
    for alias, name in src:gmatch("local%s+([%w_]+)%s*=%s*require%(\"lingering%.([%w_%.]+)\"%)") do
        aliases[alias] = name
    end
    for alias, name in pairs(aliases) do
        for fn in src:gmatch("[^%w_]" .. alias .. "[.:]([%w_]+)%s*%(") do
            if not defines(name, fn) then
                print("FOUT " .. rel .. ": " .. alias .. "." .. fn .. " bestaat niet in lingering." .. name)
                bad = bad + 1
            end
        end
    end
    for name, fn in src:gmatch("require%(\"lingering%.([%w_%.]+)\"%)[.:]([%w_]+)%s*%(") do
        if not defines(name, fn) then
            print("FOUT " .. rel .. ": lingering." .. name .. "." .. fn .. " bestaat niet")
            bad = bad + 1
        end
    end
    if rel:match("^app/") then
        -- app/ mag algemene KOReader-bibliotheken gebruiken, geen internals van plugins of widgets.
        local allowed = {
            ["logger"] = true, ["ui/uimanager"] = true, ["ui/time"] = true, ["luasettings"] = true,
            ["datastorage"] = true, ["util"] = true, ["libs/libkoreader-lfs"] = true, ["ffi/sha2"] = true,
        }
        for req in src:gmatch("require%(\"([^\"]+)\"%)") do
            if not (req:match("^lingering%.") or allowed[req]) then
                print("FOUT " .. rel .. ": app/ mag geen \"" .. req .. "\" laden (alleen via koreader/)")
                bad = bad + 1
            end
        end
    end
    if rel:match("^ui/") or rel:match("^app/") or rel == "main.lua" then
        -- Schermen en use cases praten niet rechtstreeks met KOReader-internals: alles via
        -- koreader/ (de anti-corruption layer). Device.screen (schermmaten) mag wel.
        local code = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
        for _, pattern in ipairs({ "G_reader_settings", "G_defaults", "NetworkMgr",
                                   "getPowerDevice", "Device:has", "Device:is", "Device:get",
                                   "Device:show", "Device:toggle" }) do
            if code:find(pattern, 1, true) then
                print("FOUT " .. rel .. ": " .. pattern .. " rechtstreeks gebruikt (alleen via koreader/)")
                bad = bad + 1
            end
        end
    end
    if rel:match("^domain/") then
        for req in src:gmatch("require%(\"([^\"]+)\"%)") do
            if not req:match("^lingering%.domain%.") then
                print("FOUT " .. rel .. ": domain/ mag geen \"" .. req .. "\" laden")
                bad = bad + 1
            end
        end
    end
end
if bad == 0 then print("OK   verwijzingen en lagen kloppen") end
os.exit(bad == 0 and 0 or 1)
