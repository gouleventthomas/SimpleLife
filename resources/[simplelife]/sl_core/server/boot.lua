--[[
    server/boot.lua — the guarded boot sequence. LOADS LAST among server scripts.

    This is the EXACTLY-ONE place migrations are ever invoked (bug class B1). The
    runner is triggered only from sl_core's own onResourceStart, gated to THIS
    resource name. No feature resource can reach it.

    Sequence:
      1. Wait for oxmysql: GetResourceState('oxmysql') == 'started' AND a live
         SELECT 1 succeeds (MySQL.ready also calls awaitConnection()).
      2. migrate.ApplyAll() ONCE (itself triple-guarded: latch + ledger + GET_LOCK).
      3. Flip SLCore.ready = true and GlobalState.slCoreReady = true.
      4. Wire the cross-resource :use / :call / :provide surface via exports.
      5. Print the ready banner.
      6. Start the autosave loop (Config.Autosave minutes).

    Anything that gates on core readiness reads SLCore.ready (same resource) or
    GlobalState.slCoreReady (other resources / client).
]]

-- ── CROSS-RESOURCE SURFACE (read this — B3 at the export boundary) ────────────
-- Feature resources call sl_core via FLAT exported FUNCTIONS resolved live at each
-- call site (never cache `local X = exports.sl_core` hoping it crosses files):
--
--   local Core = exports.sl_core
--   Core:isReady()                          -> boolean
--   Core:getChar(src)                       -> char view (server)   [players.lua]
--   Core:addMoney(src, account, n, why)     -> ok, detail           [players.lua]
--   Core:call('economy.credit', src, ...)   -> { ok=…, data=… }     [registry.lua]
--   Core:provide('svc', fn)                 -> register a service    [registry.lua]
--
-- CALLING CONVENTION: use COLON syntax (Core:addMoney(...)). VERIFIED against the
-- CFX runtime (citizen/scripting/lua/scheduler.lua): the exports proxy wraps every
-- handler as `function(self, ...) return handler(...) end`, i.e. it ALWAYS consumes
-- the first positional value as `self` and forwards only the rest. So the colon form
-- (which passes the proxy as self) delivers your real args intact; the DOT form would
-- DROP the first argument. Zero-arg exports (Core:isReady()) work either way.
--
-- DO NOT use Core:use('players') across resources to then call a METHOD on the
-- returned table: a function-bearing module table does not reliably deliver
-- callable methods across the export boundary (functions are marshalled, not
-- shared). `use` exists for IN-RESOURCE wiring only (SLCore.use). Cross-resource
-- callers use the FLAT exports above.
-- ─────────────────────────────────────────────────────────────────────────────

exports('isReady', function() return SLCore.ready == true end)
exports('status', function()
    local mig = SLCore.use('migrate')
    return {
        ready = SLCore.ready,
        env = Config.Env,
        migrations = mig and mig.Status() or nil,
        bootError = SLCore.bootError,
    }
end)

-- IN-RESOURCE convenience export (returns the module table). Kept for diagnostics /
-- same-state tooling; cross-resource callers should prefer the flat exports above.
-- Colon syntax: exports.sl_core:use('players').
exports('use', function(name) return SLCore.use(name) end)

-- Wait until oxmysql is started AND answers a trivial query.
local function waitForDatabase()
    -- MySQL.ready.await blocks until GetResourceState('oxmysql')=='started'
    -- and awaitConnection() resolves (see oxmysql/lib/MySQL.lua).
    MySQL.ready.await()

    local db = SLCore.require('db')
    -- Belt-and-braces: confirm an actual round-trip before migrating.
    local tries = 0
    while not db.ping() do
        tries = tries + 1
        if tries > 100 then -- ~10s
            error('boot: database did not become reachable (SELECT 1 kept failing)')
        end
        Wait(100)
    end
end

local function boot()
    -- New boot epoch: any prior autosave loop in this Lua state will see the change
    -- and exit. (On a full resource restart the state is torn down anyway; this also
    -- covers a re-entrant onResourceStart in the same state.)
    SLCore.bootEpoch = (SLCore.bootEpoch or 0) + 1
    local epoch = SLCore.bootEpoch

    Config.Log('info', ('booting (env=%s, build mp2025_02 / 3751)'):format(Config.Env))

    local ok, err = pcall(function()
        waitForDatabase()

        local migrate = SLCore.require('migrate')
        local result = migrate.ApplyAll()

        SLCore.ready = true
        GlobalState.slCoreReady = true
        GlobalState.slCoreEnv = Config.Env

        Config.Log('info', Config.Banner(result.applied, result.present))
    end)

    if not ok then
        SLCore.bootError = tostring(err)
        GlobalState.slCoreReady = false
        Config.Log('error', ('BOOT FAILED: %s'):format(tostring(err)))
        Config.Log('error', 'sl_core is NOT ready — features depending on it must not start.')
        return
    end

    -- Autosave loop (only after a successful boot). Gated on the boot epoch AND the
    -- resource still running, so a restart cleanly stops the old loop.
    if Config.Autosave and Config.Autosave > 0 then
        local intervalMs = Config.Autosave * 60 * 1000
        CreateThread(function()
            while SLCore.bootEpoch == epoch and not SLCore.stopping do
                Wait(intervalMs)
                -- Re-check after the wait: epoch may have changed / resource stopping.
                if SLCore.bootEpoch ~= epoch or SLCore.stopping then break end
                local players = SLCore.use('players')
                if players then
                    players.refreshPositions()  -- capture live positions before persisting
                    local n = players.saveAll()
                    if n > 0 then Config.Log('debug', ('autosave: %d character(s) saved'):format(n)) end
                end
            end
            Config.Log('debug', ('autosave loop (epoch %d) exited'):format(epoch))
        end)
        Config.Log('debug', ('autosave armed every %d minute(s)'):format(Config.Autosave))
    end

    -- Faster in-memory position refresh: keeps each live player's coords current so a
    -- disconnect/reconnect lands at the same spot even between the (slower) autosaves.
    -- unload() also does a final capture on disconnect, so persistence is up to date.
    if Config.SavePosition then
        local everyMs = (Config.SavePositionInterval or 60) * 1000
        CreateThread(function()
            while SLCore.bootEpoch == epoch and not SLCore.stopping do
                Wait(everyMs)
                if SLCore.bootEpoch ~= epoch or SLCore.stopping then break end
                local players = SLCore.use('players')
                if players then players.refreshPositions() end
            end
        end)
        Config.Log('debug', ('position refresh armed every %ds'):format(Config.SavePositionInterval or 60))
    end
end

-- The SINGLE invocation site for migrations. Gated to THIS resource.
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CreateThread(boot)
end)

-- Save everyone on a clean shutdown / restart, and signal loops to stop.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SLCore.stopping = true -- make the autosave loop exit promptly
    local players = SLCore.use('players')
    if players and SLCore.ready then
        players.refreshPositions()  -- capture live positions before the final save
        local n = players.saveAll()
        Config.Log('info', ('shutdown: saved %d character(s)'):format(n))
    end
end)
