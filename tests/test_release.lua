local lu = require("luaunit")
local Release = require("lingering.domain.release")

TestRelease = {}

function TestRelease:test_parse()
    lu.assertEquals(Release.parse("v1.2.3"), { 1, 2, 3 })
    lu.assertEquals(Release.parse("0.10.0"), { 0, 10, 0 })
    lu.assertNil(Release.parse("v1.2"))
    lu.assertNil(Release.parse("latest"))
    lu.assertNil(Release.parse(nil))
end

function TestRelease:test_vergelijken_numeriek_niet_alfabetisch()
    lu.assertEquals(Release.compare("v0.10.0", "v0.9.9"), 1)
    lu.assertEquals(Release.compare("v1.0.0", "1.0.0"), 0)
    lu.assertEquals(Release.compare("v1.2.3", "v1.3.0"), -1)
end

function TestRelease:test_nieuwste_tag()
    lu.assertEquals(Release.latest({ "v0.9.0", "v0.10.0", "test", "v0.2.1" }), "v0.10.0")
    lu.assertNil(Release.latest({}))
    lu.assertNil(Release.latest({ "nightly" }))
end

function TestRelease:test_is_nieuwer()
    lu.assertTrue(Release.isNewer("v0.2.0", "0.1.0"))
    lu.assertFalse(Release.isNewer("v0.1.0", "0.1.0"))
    lu.assertFalse(Release.isNewer("v0.0.9", "0.1.0"))
    lu.assertTrue(Release.isNewer("v0.1.0", nil))
    lu.assertFalse(Release.isNewer("onzin", "0.1.0"))
end

function TestRelease:test_alleen_pluginbestanden()
    for _, path in ipairs({ "_meta.lua", "main.lua", "config.lua", "app/sync_service.lua",
                            "domain/release.lua", "koreader/kosync.lua", "ui/homescreen.lua", "icons/sync.svg", "l10n/en.lua", "LICENSE" }) do
        lu.assertTrue(Release.includes(path), path)
    end
    for _, path in ipairs({ "tests/run.lua", "tools/deploy.sh", "docs/koreader-notes.md", ".gitignore",
                            "app/.hidden.lua", "../main.lua", "/etc/passwd", "README.md", "" }) do
        lu.assertFalse(Release.includes(path), path)
    end
end
