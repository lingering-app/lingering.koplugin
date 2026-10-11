--[[--
Eigen instellingen van Lingering, in <settings>/lingering.lua.
Alles hier blijft buiten settings.reader.lua.
]]
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Settings = {
    defaults = {
        lingering_allow_hold = true,
        lingering_setup_done = false,
    },
    -- Alleen voor deze sessie: "Lingering UI uitschakelen" geldt tot de volgende herstart.
    session = {
        disabled = false,
    },
}

function Settings:open()
    if not self.store then
        self.store = LuaSettings:open(DataStorage:getSettingsDir() .. "/lingering.lua")
    end
    return self.store
end

function Settings:read(key)
    local value = self:open():readSetting(key)
    if value == nil then
        return self.defaults[key]
    end
    return value
end

function Settings:save(key, value)
    local store = self:open()
    store:saveSetting(key, value)
    store:flush()
end

function Settings:isActive()
    return not self.session.disabled
end

return Settings
