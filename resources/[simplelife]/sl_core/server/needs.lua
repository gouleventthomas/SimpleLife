--[[
    server/needs.lua — hunger & thirst (server-authoritative).

    Stored inside char.metadata.needs = { hunger, thirst } so it PERSISTS with the character
    (players.saveChar writes the metadata JSON). A read-only copy is mirrored to the owning client
    via the player state bag (Player(src).state['sl:needs']) so the HUD (sl_hud) can read it.

    - Decays every Config.Needs.tickMs.
    - Restored when an item is USED (sl_inventory emits 'item:used') per Config.Needs.consume;
      heal/armor effects are forwarded to the client.
    - At 0 hunger OR thirst, the player loses health each tick (client applies, down to starveFloor).
]]

local function players() return SLCore.require('players') end
local function bus() return SLCore.require('bus') end

local N = Config.Needs or {}
local function clamp(v) return math.max(0, math.min(N.max or 100, v)) end

local function mirror(src, n)
    local p = Player(src)
    if p and p.state then p.state:set('sl:needs', { hunger = n.hunger, thirst = n.thirst }, true) end
end

-- Resolve (and lazily initialise) the needs table living inside the char's metadata.
local function getNeeds(src)
    local char = players().getChar(src)
    if not char then return nil end
    char.metadata = char.metadata or {}
    local n = char.metadata.needs
    if type(n) ~= 'table' then
        n = { hunger = N.start or 100, thirst = N.start or 100 }
        char.metadata.needs = n
    end
    if type(n.hunger) ~= 'number' then n.hunger = N.start or 100 end
    if type(n.thirst) ~= 'number' then n.thirst = N.start or 100 end
    return n
end

local function setNeed(src, key, value)
    if key ~= 'hunger' and key ~= 'thirst' then return false end
    local n = getNeeds(src); if not n then return false end
    n[key] = clamp(tonumber(value) or 0)
    mirror(src, n)
    return true
end

local function addNeed(src, key, amount)
    if key ~= 'hunger' and key ~= 'thirst' then return false end
    local n = getNeeds(src); if not n then return false end
    n[key] = clamp(n[key] + (tonumber(amount) or 0))
    mirror(src, n)
    return true
end

-- item used → restore hunger/thirst, forward heal/armor to the client
local function onItemUsed(payload)
    if not payload or not payload.source then return end
    local eff = (N.consume or {})[payload.item]
    if not eff then return end
    local src = payload.source
    local n = getNeeds(src)
    if n then
        if eff.hunger then n.hunger = clamp(n.hunger + eff.hunger) end
        if eff.thirst then n.thirst = clamp(n.thirst + eff.thirst) end
        if eff.hunger or eff.thirst then mirror(src, n) end
    end
    if eff.heal or eff.armor then
        TriggerClientEvent('sl_needs:apply', src, { heal = eff.heal, armor = eff.armor })
    end
end

-- subscribe once the bus/players modules are registered (next tick)
CreateThread(function()
    bus().on('char:loaded', function(p)
        if p and p.source then local n = getNeeds(p.source); if n then mirror(p.source, n) end end
    end)
    bus().on('item:used', onItemUsed)
end)

-- decay + starve loop
CreateThread(function()
    if not N.enabled then return end
    while true do
        Wait(N.tickMs or 60000)
        for _, char in ipairs(players().all()) do
            local src = char.source
            if src then
                local n = getNeeds(src)
                if n then
                    n.hunger = clamp(n.hunger - (N.hungerRate or 0))
                    n.thirst = clamp(n.thirst - (N.thirstRate or 0))
                    mirror(src, n)
                    if (n.hunger <= 0 or n.thirst <= 0) and (N.starveDamage or 0) > 0 then
                        TriggerClientEvent('sl_needs:starve', src, N.starveDamage, N.starveFloor or 100)
                    end
                end
            end
        end
    end
end)

SLCore.module('needs', { getNeeds = getNeeds, addNeed = addNeed, setNeed = setNeed })

-- Cross-resource exports (COLON syntax). e.g. F10 admin dev tools can top up needs.
exports('getNeeds', function(src) return getNeeds(src) end)
exports('addNeed', function(src, key, amount) return addNeed(src, key, amount) end)
exports('setNeed', function(src, key, value) return setNeed(src, key, value) end)
