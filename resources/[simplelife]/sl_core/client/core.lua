--[[
    client/core.lua — the client mirror. NOTHING authoritative lives here.

    - Reads GlobalState.slCoreReady to know when the framework is up.
    - Exposes a read-only getChar() sourced from the LOCAL player's state bag
      (LocalPlayer.state['sl:char']), which the server publishes in players.lua.
    - A thin client-side bus receive (server -> client topic forwarding) so HUDs
      can react to money:changed etc. without owning any state.

    The server is the single source of truth; this file only reflects it.
]]

-- Resource-global client mirror (single Lua state on the client too).
SLClient = {
    ready = false,
}

--- Is the core framework ready (per the replicated global state bag)?
---@return boolean
function SLClient.isReady()
    return GlobalState.slCoreReady == true
end

--- Read-only LOCAL character view (or nil if not loaded). Sourced from the
--- replicated player state bag set by the server. Takes NO argument (this is the
--- client; there is only the local player). The server-side getChar takes a `src`.
---@return table?
function SLClient.getChar()
    return LocalPlayer.state['sl:char']
end

-- Explicit, unambiguous alias preferred in client feature code.
SLClient.getLocalChar = SLClient.getChar

--- Current environment string ('dev'/'prod') as published by the server.
---@return string?
function SLClient.getEnv()
    return GlobalState.slCoreEnv
end

-- Track readiness via the state bag change handler.
AddStateBagChangeHandler('slCoreReady', 'global', function(_, _, value)
    SLClient.ready = value == true
    if value then
        TriggerEvent('sl_core:client:ready')
    end
end)

-- Initial sync in case the global was already set before this script loaded.
CreateThread(function()
    -- Wait briefly for the global state bag to replicate after join.
    local tries = 0
    while GlobalState.slCoreReady == nil and tries < 100 do
        Wait(100)
        tries = tries + 1
    end
    SLClient.ready = GlobalState.slCoreReady == true
    if SLClient.ready then
        TriggerEvent('sl_core:client:ready')
    end
end)

-- Thin client bus: the server may forward whitelisted topics to the owning client.
-- Handlers registered here just re-broadcast as a local event for HUD resources.
RegisterNetEvent('sl_core:bus', function(topic, payload)
    if type(topic) ~= 'string' then return end
    TriggerEvent(('sl_core:bus:%s'):format(topic), payload)
end)

-- ── CLIENT-SIDE EXPORT SURFACE (signatures differ from the SERVER!) ───────────
-- These are the ONLY exports sl_core exposes on the CLIENT. Their signatures are
-- intentionally different from the server-side exports of the same name:
--   client  getChar()      -> local char view, NO argument
--   server  getChar(src)   -> char object for a source (players.lua)
--   client  isReady()      -> reads the replicated GlobalState (no DB)
--   server  isReady()      -> reads SLCore.ready (authoritative)
-- To avoid ambiguity, the local view is ALSO exposed as getLocalChar() — prefer
-- that name in client feature code so the no-arg intent is explicit and there is no
-- confusion with the server's getChar(src).
exports('isReady', function() return SLClient.isReady() end)
exports('getChar', function() return SLClient.getChar() end)       -- alias of getLocalChar (no arg)
exports('getLocalChar', function() return SLClient.getChar() end)  -- preferred, unambiguous name
exports('getEnv', function() return SLClient.getEnv() end)
