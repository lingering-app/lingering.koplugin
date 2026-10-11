-- Controleert, zonder KOReader te laden:
-- 1. elke aanroep X.f( / X:f( op een module uit require("lingering.…") bestaat in dat bestand;
-- 2. domain/ laadt niets buiten domain/ (business rules los van KOReader).
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
