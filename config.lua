-- Vaste adressen. Er is geen scherm om ze te wijzigen.
return {
    opds_url = "https://opds.lingering.app",
    sync_url = "https://koreader.lingering.app",
    -- Mappen uit de OPDS-catalogus die als blok (stapel omslagen) op het homescreen staan;
    -- een tik opent die map in Mijn boeken. Op naam (hoofdletters maken niet uit).
    collections = { "Aan het lezen", "Al mijn boeken" },
    -- Openbare GitHub-repo voor zelf-update (Instellingen → Update); tags als v1.2.3.
    update_repo = "lingering-app/lingering.koplugin",
}
