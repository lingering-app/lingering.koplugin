--[[--
Schermwissels: boek openen/sluiten, volledig KOReader-menu (noodluik).
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

--- Sluit het boek en gaat naar de bestandsbeheerder (waar het homescreen overheen komt).
function M.closeBook(ui)
    if try("ReaderUI:onHome", ui.onHome, ui) then
        return true
    end
    return try("ReaderUI:onClose", function()
        local file = ui.document and ui.document.file
        ui:onClose()
        ui:showFileManager(file)
    end)
end

--- Opent een boek (ReaderUI:showReader, de enige veilige manier volgens readerui.lua).
function M.openBook(file)
    return try("ReaderUI:showReader", function()
        require("apps/reader/readerui"):showReader(file)
    end)
end

--[[--
Opent het volledige menu van de bestandsbeheerder (noodluik), op het laatste tabblad (☰),
waar "Lingering UI uitschakelen" staat. Leest FileManagerMenu.tab_item_table (intern);
lukt dat niet, dan opent het menu op het laatst gebruikte tabblad.
]]
function M.showFullMenu(fm)
    return try("FileManagerMenu:onShowMenu", function()
        local menu = assert(fm and fm.menu, "FileManager.menu ontbreekt")
        local ok_tab, last_tab = pcall(function()
            if menu.tab_item_table == nil then menu:setUpdateItemTable() end
            return #menu.tab_item_table
        end)
        menu:onShowMenu(ok_tab and last_tab > 0 and last_tab or nil)
    end)
end

return M
