--[[--
pcall-hulp voor alle haken in KOReader-internals: faalt een haak, dan een waarschuwing in de
log en blijft alleen dat onderdeel bij het standaardgedrag van KOReader.
try(naam, fn, ...) geeft true plus álle resultaten van fn terug, of false bij een fout.
]]
local logger = require("logger")

return function(name, fn, ...)
    local results = { pcall(fn, ...) }
    if not results[1] then
        logger.warn("Lingering: haak", name, "mislukt, standaardgedrag van KOReader blijft:", results[2])
        return false
    end
    return unpack(results, 1, table.maxn(results))
end
