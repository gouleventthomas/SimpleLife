--[[
    server/_bootstrap.lua — loads FIRST among server scripts.

    Declares the resource-global module registry `SLCore` (NO `local`). Because
    FiveM runs every server_script of this resource in ONE shared Lua state, this
    single table is visible to every other server file — this is the sanctioned
    fix for bug class B3 (cross-file scope). Files attach their module via
    SLCore.module('name', tbl) and consume others via SLCore.use('name').

    The cross-RESOURCE surface (exports) is wired in boot.lua once everything has
    registered, but the module table itself lives here.
]]

SLCore = {
    modules = {},
    ready = false,
    bootError = nil,
    -- Incremented each boot. Long-lived loops (autosave) capture the current epoch
    -- and exit when it changes, so a `restart sl_core` cleanly stops the old loop
    -- instead of leaving two running until GC (boot-logic fix).
    bootEpoch = 0,
}

--- Register a module table under a name. Idempotent-safe: re-registering replaces.
---@param name string
---@param tbl table
---@return table
function SLCore.module(name, tbl)
    assert(type(name) == 'string' and name ~= '', 'SLCore.module: name must be a non-empty string')
    assert(type(tbl) == 'table', 'SLCore.module: tbl must be a table')
    SLCore.modules[name] = tbl
    if Config and Config.Log then
        Config.Log('debug', ('module registered: %s'):format(name))
    end
    return tbl
end

--- Resolve a registered module by name (live, resolved at call time).
---@param name string
---@return table?
function SLCore.use(name)
    return SLCore.modules[name]
end

--- Same as use() but raises if the module is missing — for internal hard deps.
---@param name string
---@return table
function SLCore.require(name)
    local m = SLCore.modules[name]
    if not m then
        error(('SLCore.require: module "%s" is not registered (check server_script order)'):format(name), 2)
    end
    return m
end

-- ── Cross-resource export CALLING CONVENTION (verified against the CFX runtime) ─
-- IMPORTANT FACT (verified in citizen/scripting/lua/scheduler.lua): the exports
-- proxy wraps every export as `function(self, ...) return handler(...) end` — it
-- ALWAYS swallows the FIRST positional value as `self` and forwards only the REST
-- to the handler. Consequences feature authors MUST follow:
--
--   * COLON syntax is CORRECT for exports that take arguments:
--         exports.sl_core:addMoney(src, 'cash', 100)
--     The proxy is consumed as `self`; the handler receives (src, 'cash', 100).
--
--   * DOT syntax DROPS the first argument and must only be used for ZERO-ARG
--     exports (e.g. exports.sl_core:isReady() or exports.sl_core.isReady() both
--     work because there are no args to lose). For ANY export with arguments, use
--     COLON.
--
-- Therefore our handlers are plain positional (function(src, account, ...) end) and
-- the documented convention is COLON. No self-stripping shim is needed or correct:
-- the proxy never reaches the handler.
