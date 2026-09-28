--[[
    shared/config.lua — static configuration shared by client + server.

    Resource-global `Config` (no `local`) so every file in this resource reads it.
    Pure data + banner helpers only. No DB, no side effects.
]]

Config = {}

-- 'dev' uses simplelife_dev, 'prod' uses simplelife_prod (connection string lives in server.cfg).
Config.Env = 'dev'

-- Autosave interval in MINUTES for the character registry.
Config.Autosave = 5

-- Verbose logging toggle.
Config.Debug = true

-- Default starting balances (mirrored by migrations 002_characters.sql defaults).
Config.StartCash = 500
Config.StartBank = 5000

-- ── Position persistence (déco / reco au même endroit) ────────────────────────
-- Capture each LIVE player's CURRENT position (read server-side via OneSync) into their
-- character so a disconnect/reconnect resumes at the same spot. Refreshed in-memory on the
-- interval + once more on disconnect; the autosave / unload then persist it. "Live" means the
-- player has fully spawned in the world (sl_identity flips it on releaseToPlayer), so the
-- hold / creation / arrival-cinematic positions are NEVER saved.
Config.SavePosition = true
Config.SavePositionInterval = 60  -- seconds between in-memory position refreshes

-- ── World control (client-enforced) ───────────────────────────────────────────
-- A clean, controlled RP world. All client-side, re-applied continuously.
Config.World = {
    disablePeds     = true,   -- no ambient pedestrians / scenario peds
    disableTraffic  = true,  -- keep ambient vehicles (set true to also clear traffic)
    disableWanted   = true,   -- police stars IMPOSSIBLE (max wanted 0) + auto-clear
    disableDispatch = true,   -- no police / EMS / fire dispatch response
    disableEvents   = true,   -- no random ambient events / random cops
    disableWeaponWheel = true, -- no weapon wheel (select-weapon) at all
    disableCarAirControl = true, -- no mid-air car rotation (anti-stunt; excludes planes/helis)
}

-- ── Needs: hunger & thirst (server-authoritative, persisted in char metadata) ────
-- Decay over time; eating/drinking restores them (consume map). At 0, the player loses
-- health each tick (down to starveFloor). The HUD (sl_hud) reads `Player.state['sl:needs']`.
Config.Needs = {
    enabled      = true,
    tickMs       = 60000,   -- decay/starve tick interval (ms)
    hungerRate   = 2,       -- hunger lost per tick
    thirstRate   = 3,       -- thirst lost per tick (thirst drains faster)
    max          = 100,
    start        = 100,     -- a fresh character starts full
    starveDamage = 6,       -- health lost per tick while hunger OR thirst == 0
    starveFloor  = 100,     -- never starve below this entity health (100 = empty bar, still alive)

    -- effect applied when an item is USED (sl_inventory emits 'item:used'). hunger/thirst are
    -- restored server-side; heal/armor are applied on the client.
    consume = {
        water       = { thirst = 30 },
        cola        = { thirst = 20, hunger = 4 },
        coffee      = { thirst = 15 },
        beer        = { thirst = 12 },
        sandwich    = { hunger = 40 },
        burger      = { hunger = 55 },
        bandage     = { heal = 25 },
        medkit      = { heal = 200 },
        painkillers = { heal = 20 },
    },
}

-- Persisted claim-lock id used to serialise migrations across server instances (B1c).
-- (NOT a MariaDB GET_LOCK — that is session-scoped and dies with oxmysql's pooled
--  connection. See server/db.lua acquireClaim / server/migrate.lua.)
Config.MigrateLock = 'sl_migrate'
Config.MigrateLockTimeout = 30 -- seconds to keep retrying to acquire the claim lock
Config.MigrateLockTTL = 60     -- claim lifetime; auto-expires if the holder crashes

--- Prefixed log helper. Honours Config.Debug for the debug channel.
---@param channel 'info' | 'warn' | 'error' | 'debug'
---@param msg string
function Config.Log(channel, msg)
    if channel == 'debug' and not Config.Debug then return end
    local tag = ('^5[sl_core]^7')
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('%s %s%s^7'):format(tag, colour, msg))
end

--- Build the ready banner string used by boot.lua.
---@param applied integer
---@param present integer
---@return string
function Config.Banner(applied, present)
    return ('migrations: %d applied / %d present | ready (env=%s)'):format(applied, present, Config.Env)
end
