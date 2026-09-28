--[[
    client/main.lua — drives the HUD NUI.
      • Reads health (native), armour (native), hunger/thirst (Player.state['sl:needs'] from sl_core).
      • Hides the native HEALTH (3) + ARMOUR (4) HUD components.
      • Applies item heal/armour (sl_needs:apply) and starvation health loss (sl_needs:starve).
    The HUD is a passive overlay — it never takes NUI focus.
]]

local last = { health = -1, armor = -1, hunger = -1, thirst = -1, visible = nil }

local function pushHud()
    local ped = PlayerPedId()
    local hasChar = LocalPlayer.state['sl:char'] ~= nil
    local h, mh = GetEntityHealth(ped), GetEntityMaxHealth(ped)
    local health
    if mh > 100 then
        health = math.floor(math.max(0.0, (h - 100) / (mh - 100)) * 100 + 0.5)   -- GTA: 100 = empty bar
    else
        health = math.floor((h / math.max(1, mh)) * 100 + 0.5)
    end
    local armor = math.floor(GetPedArmour(ped) + 0.5)
    local n = LocalPlayer.state['sl:needs'] or {}
    local hunger = math.floor(tonumber(n.hunger) or 100)
    local thirst = math.floor(tonumber(n.thirst) or 100)

    if health ~= last.health or armor ~= last.armor or hunger ~= last.hunger or thirst ~= last.thirst or hasChar ~= last.visible then
        last.health, last.armor, last.hunger, last.thirst, last.visible = health, armor, hunger, thirst, hasChar
        SendNUIMessage({ action = 'hud', data = { visible = hasChar, health = health, armor = armor, hunger = hunger, thirst = thirst } })
    end
end

CreateThread(function()
    while true do
        pushHud()
        Wait(500)
    end
end)

-- The native health/armour bars under the minimap are baked into this build's MINIMAP scaleform
-- (confirmed: HideHudComponent / DisplayHud(false) don't remove them, only DisplayRadar(false)
-- would — which also kills the map). Removing just those bars requires a custom minimap (streamed
-- asset) → handled by the optional sl_minimap resource. The gauges above replace them visually.

-- medical item heal / armour gain (server forwards from item:used)
RegisterNetEvent('sl_needs:apply', function(eff)
    if type(eff) ~= 'table' then return end
    local ped = PlayerPedId()
    if eff.heal then SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + math.floor(eff.heal))) end
    if eff.armor then SetPedArmour(ped, math.min(100, math.floor(GetPedArmour(ped) + eff.armor))) end
end)

-- starvation tick: lose health while hunger/thirst is empty (never below the floor)
RegisterNetEvent('sl_needs:starve', function(dmg, floor)
    local ped = PlayerPedId()
    SetEntityHealth(ped, math.max(tonumber(floor) or 100, GetEntityHealth(ped) - (tonumber(dmg) or 5)))
end)
