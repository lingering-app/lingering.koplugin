local lu = require("luaunit")
local try = require("lingering.koreader.try")

TestTry = {}

function TestTry:test_geeft_alle_resultaten_terug()
    -- Het wachtwoord ging ooit verloren omdat try maar één resultaat teruggaf.
    lu.assertEquals({ try("x", function() return "gebruiker", "wachtwoord" end) }, { true, "gebruiker", "wachtwoord" })
    lu.assertEquals({ try("x", function() return false, "reden" end) }, { true, false, "reden" })
    lu.assertEquals({ try("x", function() return nil, "x" end) }, { true, nil, "x" })
end

function TestTry:test_fout_geeft_false()
    lu.assertEquals({ try("x", function() error("boem") end) }, { false })
end
