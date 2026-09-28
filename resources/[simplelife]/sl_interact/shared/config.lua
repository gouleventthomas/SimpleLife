--[[
    shared/config.lua — sl_interact defaults.

    Resource-global `Config` (no `local`) so client/main.lua sees it. Private to this
    resource; does not collide with other resources' Config (separate Lua states).
]]

Config = {}

-- Applied to any option that doesn't specify its own.
Config.Defaults = {
    icon     = 'fa-solid fa-hand-pointer',
    distance = 2.0,
}

-- Draw ox_target zone debug volumes (dev only). Leave false in normal play.
Config.Debug = false

-- Prefixed logger (mirrors the sl_* house style).
---@param channel 'info'|'warn'|'error'|'debug'
---@param msg string
function Config.Log(channel, msg)
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('^5[sl_interact]^7 %s%s^7'):format(colour, tostring(msg)))
end
