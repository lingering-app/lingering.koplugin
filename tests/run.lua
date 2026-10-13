--[[--
Unit tests (luaunit), zonder KOReader. Gebruik: tools/test.sh
of: luajit tests/run.lua <pluginmap> [luaunit-opties]
]]
local root = arg[1] or "."
arg0_root = root -- luacheck: ignore (voor tests die bestanden uit de plugin lezen)
-- luaunit leest de globale arg al bij het laden; daar hoort de pluginmap niet in.
local args = {}
for i = 2, #arg do args[#args + 1] = arg[i] end
arg = args
package.path = root .. "/tests/vendor/?.lua;" .. root .. "/tests/?.lua;" .. package.path

-- lingering.<map>.<naam> → <pluginmap>/<map>/<naam>.lua (zoals in main.lua)
table.insert(package.loaders, 2, function(name)
    local relative = name:match("^lingering%.(.+)$")
    if not relative then return nil end
    local path = root .. "/" .. relative:gsub("%.", "/") .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then return "\n\t" .. tostring(err) end
    return chunk
end)

require("fakes").install()

for _, test in ipairs({
    "test_sync_rules", "test_catalog", "test_reading_time", "test_layout",
    "test_sync_service", "test_try", "test_release", "test_catalog_shelf", "test_library_service",
    "test_l10n", "test_reading_stats",
}) do
    require(test)
end

local lu = require("luaunit")
os.exit(lu.LuaUnit.run(unpack(args)))
