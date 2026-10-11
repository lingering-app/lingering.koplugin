--[[--
Dialogen van KOReader aanpassen (kaal invoervenster).
Onderdeel van de anti-corruption layer (koreader/): het enige dat KOReader-internals kent.
Elke haak loopt via try(); zie docs/koreader-notes.md.
]]
local try = require("lingering.koreader.try")

local M = {}

--[[--
Maakt van een MultiInputDialog een kale kaart: geen rand om het venster en geen titelbalk;
de invoervelden houden hun rand. Leunt op MultiInputDialog:init
(frontend/ui/widget/multiinputdialog.lua): dialog_frame (FrameContainer) met als eerste
element een VerticalGroup waarvan [1] de title_bar is. Faalt het, dan blijft het venster
zoals KOReader het maakt.
]]
function M.plainDialog(dialog, framed_button_id)
    return try("plainDialog", function()
        local Blitbuffer = require("ffi/blitbuffer")
        local Size = require("ui/size")
        local frame = assert(dialog.dialog_frame, "dialog_frame ontbreekt")
        local group = assert(frame[1], "inhoud ontbreekt")
        frame.bordersize = 0
        frame.radius = 0
        if group[1] == dialog.title_bar then
            table.remove(group, 1)
        end
        -- InputDialog maakt de knoppenrij met zero_sep = true: een scheidingslijn bovenaan
        -- (ButtonTable:addVerticalSeparator). Zonder kaart hangt die los: weg ermee.
        local buttons = dialog.button_table and dialog.button_table.container
        if buttons and buttons[1] and buttons[1].dimen and buttons[1].background
                and buttons[1].dimen.h == dialog.button_table.sep_width then
            table.remove(buttons, 1)
        end
        -- Eén knop met een eigen rand, zodat hij als knop herkenbaar is (Button.frame).
        if framed_button_id then
            local button = dialog.button_table:getButtonById(framed_button_id)
            if button and button.frame then
                button.frame.bordersize = Size.border.button
                button.frame.color = Blitbuffer.COLOR_BLACK
                button.frame.radius = Size.radius.button
            end
        end
        if buttons then buttons:resetLayout() end
        group:resetLayout()
    end)
end

return M
