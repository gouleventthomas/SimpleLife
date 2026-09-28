--[[
    server/bus.lua — the framework event bus over a VALIDATED topic catalogue.

    Decouples producers from consumers without the typo-prone string events that
    plagued the old build. Topics live in a fixed catalogue; emitting/subscribing
    to an unknown topic logs a warning so mistakes surface immediately.

    emit(topic, payload) — synchronously invokes every subscriber (each wrapped in
                           pcall so one bad listener cannot break the chain).
    on(topic, fn)        — subscribe; returns an unsubscribe function.

    ── CROSS-RESOURCE SAFETY (exports-surface) ──────────────────────────────────
    A raw callback passed across the FiveM export boundary arrives as a
    __cfx_functionReference proxy: (a) it will NOT compare equal by identity to what
    a caller stored, so an identity-based unsubscribe could silently fail; and (b) if
    the owning feature restarts, the proxy dangles and every emit() would pcall-fail
    against it forever, leaking the handler.

    Fixes:
      * Each subscription is stored as a RECORD { fn, owner, id } keyed by a unique
        id, and unsubscribe closes over that id (no function-identity comparison).
      * bus.on records the OWNING resource; an onResourceStop handler purges every
        subscription owned by a stopped resource, so dangling references cannot
        accumulate.
      * Preferred cross-resource pattern: features bridge via the netevent
        'sl_core:bus' (server->client) or call exports.sl_core.on with a STABLE
        top-level function (not an anonymous per-tick closure) so the core can track
        and purge it cleanly on restart.
]]

local bus = {}

-- The authoritative topic catalogue. Unknown topics warn (not error) so a feature
-- mid-development still runs, but the typo is visible.
local TOPICS = {
    ['char:loaded']      = true,
    ['char:logout']      = true,
    ['money:changed']    = true,
    ['job:changed']      = true,
    ['item:used']        = true,
    ['player:downed']    = true,
    ['player:wanted']    = true,
    ['interaction:used'] = true,
}

local handlers = {} -- topic -> array of { fn, owner, id }
local nextId = 0

--- Subscribe to a topic. Returns an unsubscribe function (closes over a unique id,
--- NOT function identity, so a cross-resource function reference unsubscribes fine).
---@param topic string
---@param fn fun(payload: any)
---@param ownerResource? string  the resource that subscribed (for purge-on-stop)
---@return fun() unsubscribe
function bus.on(topic, fn, ownerResource)
    if not TOPICS[topic] then
        Config.Log('warn', ('bus.on: unknown topic "%s" (not in catalogue)'):format(topic))
    end
    assert(type(fn) == 'function' or (type(fn) == 'table' and fn.__cfx_functionReference),
        'bus.on: fn must be a function (or a cross-resource function reference)')
    local list = handlers[topic]
    if not list then
        list = {}
        handlers[topic] = list
    end
    nextId = nextId + 1
    local id = nextId
    list[#list + 1] = { fn = fn, owner = ownerResource or GetCurrentResourceName(), id = id }

    return function()
        local arr = handlers[topic]
        if not arr then return end
        for i = #arr, 1, -1 do
            if arr[i].id == id then table.remove(arr, i); return end
        end
    end
end

--- Remove every subscription owned by a (stopped) resource.
---@param ownerResource string
function bus.purgeOwner(ownerResource)
    for topic, arr in pairs(handlers) do
        for i = #arr, 1, -1 do
            if arr[i].owner == ownerResource then table.remove(arr, i) end
        end
    end
end

--- Emit a topic with a payload to all subscribers. Safe: each handler is pcall'd.
---@param topic string
---@param payload any
function bus.emit(topic, payload)
    if not TOPICS[topic] then
        Config.Log('warn', ('bus.emit: unknown topic "%s" (not in catalogue)'):format(topic))
    end
    local list = handlers[topic]
    if not list then return end
    -- Snapshot length: handlers added during emit are not invoked this round.
    for i = 1, #list do
        local rec = list[i]
        if rec then
            local ok, err = pcall(rec.fn, payload)
            if not ok then
                Config.Log('error', ('bus handler for "%s" (owner %s) raised: %s')
                    :format(topic, tostring(rec.owner), tostring(err)))
            end
        end
    end
end

--- True if a topic exists in the catalogue.
---@param topic string
---@return boolean
function bus.isTopic(topic)
    return TOPICS[topic] == true
end

--- The catalogue (sorted) for diagnostics.
---@return string[]
function bus.topics()
    local t = {}
    for k in pairs(TOPICS) do t[#t + 1] = k end
    table.sort(t)
    return t
end

SLCore.module('bus', bus)

-- Purge subscriptions owned by a feature resource when it stops (prevents dangling
-- __cfx_functionReference handlers leaking across feature restarts).
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    bus.purgeOwner(resourceName)
end)

-- Cross-resource exports. Call with COLON syntax: exports.sl_core:on('money:changed', fn).
-- on() records the invoking resource as owner so it is purged on that resource's stop.
exports('emit', function(topic, payload)
    return bus.emit(topic, payload)
end)
exports('on', function(topic, fn)
    return bus.on(topic, fn, GetInvokingResource and GetInvokingResource() or nil)
end)
