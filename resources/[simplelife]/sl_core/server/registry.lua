--[[
    server/registry.lua — the service registry.

    A feature provides a named service (a function); anyone calls it by name. The
    binding is resolved at CALL time, so registration order never matters and a
    missing service degrades gracefully instead of nil-deref'ing.

    call(name, ...) ALWAYS returns a result envelope:
        { ok = true,  data = <return value> }
        { ok = false, err = 'NO_SERVICE' }            -- not registered
        { ok = false, err = 'SERVICE_ERROR', detail } -- provider raised
]]

local registry = {}
local services = {}
local owners = {}    -- service name -> owning resource (for purge-on-stop)

--- Register (or replace) a named service implementation.
--- `fn` may be a cross-resource __cfx_functionReference; we accept it but track the
--- owning resource so the binding is purged if that resource stops (avoids calling a
--- dangling reference after a feature restart — see purgeOwner / onResourceStop).
---@param name string
---@param fn fun(...): any
---@param ownerResource? string  the resource that registered this (nil = sl_core itself)
function registry.provide(name, fn, ownerResource)
    assert(type(name) == 'string' and name ~= '', 'registry.provide: name must be a non-empty string')
    assert(type(fn) == 'function' or (type(fn) == 'table' and fn.__cfx_functionReference),
        'registry.provide: fn must be a function (or a cross-resource function reference)')
    services[name] = fn
    owners[name] = ownerResource or GetCurrentResourceName()
    Config.Log('debug', ('service provided: %s (owner=%s)'):format(name, owners[name]))
end

--- Call a named service. Resolved live. Never raises — returns an envelope.
---@param name string
---@param ... any
---@return { ok: boolean, data?: any, err?: string, detail?: string }
function registry.call(name, ...)
    local fn = services[name]
    if not fn then
        return { ok = false, err = 'NO_SERVICE' }
    end
    local ok, res = pcall(fn, ...)
    if not ok then
        Config.Log('error', ('service "%s" raised: %s'):format(name, tostring(res)))
        return { ok = false, err = 'SERVICE_ERROR', detail = tostring(res) }
    end
    return { ok = true, data = res }
end

--- True if a service name is currently registered.
---@param name string
---@return boolean
function registry.has(name)
    return services[name] ~= nil
end

--- List registered service names (sorted) for diagnostics.
---@return string[]
function registry.list()
    local names = {}
    for k in pairs(services) do names[#names + 1] = k end
    table.sort(names)
    return names
end

--- Purge every service whose name was registered by a now-stopped resource, so a
--- feature restart does not leave dangling cross-resource function references.
---@param ownerResource string
function registry.purgeOwner(ownerResource)
    for name, meta in pairs(owners) do
        if meta == ownerResource then
            services[name] = nil
            owners[name] = nil
            Config.Log('debug', ('service purged (owner %s stopped): %s'):format(ownerResource, name))
        end
    end
end

SLCore.module('registry', registry)

-- Drop services owned by a feature resource when it stops (prevents dangling
-- __cfx_functionReference handlers from accumulating across restarts).
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    registry.purgeOwner(resourceName)
end)

-- Cross-resource exports. Call with COLON syntax: exports.sl_core:provide('svc', fn).
-- provide() records the CALLING resource as the owner so it can be purged on stop.
exports('provide', function(name, fn)
    return registry.provide(name, fn, GetInvokingResource and GetInvokingResource() or nil)
end)
exports('call', function(name, ...)
    return registry.call(name, ...)
end)
exports('has', function(name)
    return registry.has(name)
end)
