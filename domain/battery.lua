--[[--
Batterij-icoon bij een percentage: Material Symbols battery_0_bar … battery_6_bar,
battery_full (vanaf 95%) en battery_charging_full tijdens het laden.
]]
local M = {}

local BARS = 6
local FULL_FROM = 95

function M.icon(percent, charging)
    if charging then return "battery_charging_full.svg" end
    percent = math.max(0, math.min(100, tonumber(percent) or 0))
    if percent >= FULL_FROM then return "battery_full.svg" end
    -- 0..94% gelijk verdeeld over 0..6 streepjes.
    local bars = math.min(BARS, math.floor(percent * (BARS + 1) / FULL_FROM))
    return "battery_" .. bars .. "_bar.svg"
end

return M
