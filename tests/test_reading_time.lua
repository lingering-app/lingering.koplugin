local lu = require("luaunit")
local ReadingTime = require("lingering.domain.reading_time")

TestReadingTime = {}

function TestReadingTime:test_zonder_gegevens()
    lu.assertNil(ReadingTime.estimate(nil, 0.5))
    lu.assertNil(ReadingTime.estimate({ read_pages = 0, read_time = 0, pages = 100 }, 0.5))
end

function TestReadingTime:test_resterend_uit_gemiddelde()
    -- 10 pagina's in 600 s → 60 s per pagina; 200 pagina's, 25% gelezen → 150 over.
    local est = ReadingTime.estimate({ read_pages = 10, read_time = 600, pages = 200 }, 0.25)
    lu.assertEquals(est.read_secs, 600)
    lu.assertEquals(est.left_secs, 150 * 60)
end

function TestReadingTime:test_split_afronding()
    lu.assertEquals({ ReadingTime.split(15600) }, { 4, 20 })
    lu.assertEquals({ ReadingTime.split(3599) }, { 1, 0 })
    lu.assertEquals({ ReadingTime.split(89) }, { 0, 1 })
end
