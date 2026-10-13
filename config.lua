-- Vaste adressen. Er is geen scherm om ze te wijzigen. Bij het starten van KOReader kunnen
-- LINGERING_OPDS_URL en LINGERING_SYNC_URL ze vervangen (bijv. een lokale testserver, zie
-- tools/mock_server.py); op een Kobo zijn die niet gezet.
return {
    opds_url = os.getenv("LINGERING_OPDS_URL") or "https://opds.lingering.app",
    sync_url = os.getenv("LINGERING_SYNC_URL") or "https://koreader.lingering.app",
    -- Mappen uit de OPDS-catalogus die als blok (stapel omslagen) op het homescreen staan;
    -- een tik opent die map in Mijn boeken. Op naam (hoofdletters maken niet uit).
    collections = { "Wil ik lezen", "Al mijn boeken" },
    -- Map met boeken die op de website gelezen zijn: wat daarin staat en gedownload is, gaat
    -- ook op de e-reader op gelezen (app/library_service.lua syncFinished).
    finished_collection = "Gelezen",
    -- Woordenboeken in Instellingen → Woordenboek. name = naam in KOReaders lijst
    -- (frontend/ui/data/dictionaries.lua): de downloadlink komt daar vandaan. label staat
    -- in de eigen taal, niet vertaald.
    dictionaries = {
        { label = "Nederlands", name = "reader.dict Dutch" },
        { label = "English", name = "reader.dict English" },
    },
    -- Openbare GitHub-repo voor zelf-update (Instellingen → Update); tags als v1.2.3.
    update_repo = "lingering-app/lingering.koplugin",
}
