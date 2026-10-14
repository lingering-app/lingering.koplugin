--[[--
Voortgang van een sync-knop in een kader eronder (ui/popover.lua), zoals het batterij-kader:
tekst vet, detail grijs eronder. Gebruikt door Mijn boeken en het homescreen.

local status = SyncStatus.new(function() return sync_item.dimen end)
status:show(_("Boeken ophalen…"))
status:show(_("Synchroniseren mislukt"), _("Geen verbinding"), true) -- finished: sluit na 3 s
Sloot je het kader met een tik, dan komt het tijdens deze sync niet terug (de sync loopt door).
]]
local SyncStatus = {}
SyncStatus.__index = SyncStatus

local CLOSE_AFTER = 3

function SyncStatus.new(anchor)
    return setmetatable({ anchor = anchor }, SyncStatus)
end

function SyncStatus:show(text, detail, finished)
    local lines = { { text = text, bold = true } }
    if detail then table.insert(lines, { text = detail, gray = true }) end
    local popover = self.popover
    if popover and popover.closed then return end
    if popover then
        popover:setLines(lines)
    else
        popover = require("lingering.ui.popover"):new{ anchor = self.anchor(), lines = lines, stay = true }
        popover:show()
        self.popover = popover
    end
    if finished then popover:closeIn(CLOSE_AFTER) end
end

--- Kader dicht (bijv. als het scherm sluit).
function SyncStatus:close()
    if self.popover then self.popover:dismiss() end
end

function SyncStatus:isOpen()
    return self.popover ~= nil and not self.popover.closed
end

return SyncStatus
