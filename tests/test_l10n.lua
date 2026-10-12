local lu = require("luaunit")

TestL10n = {}

-- l10n/gettext.lua leest de taal één keer bij het laden: per taal opnieuw laden.
local function gettextFor(lang)
    package.loaded["lingering.koreader.locale"] = { language = function() return lang end }
    package.loaded["lingering.l10n.gettext"] = nil
    local _ = require("lingering.l10n.gettext")
    package.loaded["lingering.l10n.gettext"] = nil
    package.loaded["lingering.koreader.locale"] = nil
    return _
end

function TestL10n:test_nederlands_blijft_nederlands()
    local _ = gettextFor("nl_NL")
    lu.assertEquals(_("Instellingen"), "Instellingen")
    lu.assertEquals(_("Mijn boeken"), "Mijn boeken")
end

function TestL10n:test_andere_taal_wordt_engels()
    for _, lang in ipairs({ "C", "en", "de" }) do
        local tr = gettextFor(lang)
        lu.assertEquals(tr("Instellingen"), "Settings", lang)
        lu.assertEquals(tr("Nog geen boek.\nTik hier om er een te kiezen uit Mijn boeken."),
            "No book yet.\nTap here to choose one from My books.", lang)
    end
end

function TestL10n:test_onbekende_tekst_blijft_staan()
    local _ = gettextFor("C")
    lu.assertEquals(_("Bestaat niet"), "Bestaat niet")
end

function TestL10n:test_plaatshouders_gelijk()
    local english = dofile((arg0_root or ".") .. "/l10n/en.lua")
    for dutch, en in pairs(english) do
        local function holders(s)
            local list = {}
            for h in s:gmatch("%%%d") do list[#list + 1] = h end
            table.sort(list)
            return table.concat(list, ",")
        end
        lu.assertEquals(holders(en), holders(dutch), dutch)
    end
end
