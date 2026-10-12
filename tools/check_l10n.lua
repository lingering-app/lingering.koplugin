-- Controleert dat elke _("…") in de plugin een Engelse vertaling heeft in l10n/en.lua,
-- en meldt vertalingen die nergens meer gebruikt worden.
-- Gebruik: luajit tools/check_l10n.lua <pluginmap> <bestand>...
local root = arg[1]
local english = dofile(root .. "/l10n/en.lua")
local used, bad = {}, 0

for i = 2, #arg do
    local path = arg[i]
    local f = io.open(path, "r")
    local src = f:read("*a")
    f:close()
    -- _("…") met escapes zoals \n: de letterlijke string laten uitrekenen door Lua zelf.
    for literal in src:gmatch('[^%w_]_%((%b"")%)') do
        local text = assert(loadstring("return " .. literal))()
        used[text] = true
        if english[text] == nil then
            print("FOUT " .. path:sub(#root + 2) .. ": geen Engelse vertaling voor " .. literal)
            bad = bad + 1
        end
    end
end
for text in pairs(english) do
    if not used[text] then
        print("LET OP: vertaling niet meer gebruikt: " .. string.format("%q", text))
    end
end
if bad > 0 then os.exit(1) end
print("OK   vertalingen compleet")
