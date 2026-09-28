--[[
    server/interact.lua — the authoritative world-interaction registry.

    Features register interactions (targets, prompts, menu options). The SERVER is
    the source of truth: when a client triggers an interaction, the server
    RE-CHECKS the `requires(src)` predicate before running `onSelect(src)`. A
    client cannot fire an interaction it is not allowed to, even with a crafted
    net event.

    Spec:
      {
        id        = 'unique_string',
        type      = 'target' | 'zone' | 'command' | ...,   -- advisory, for the client
        label     = 'Open Stash',
        distance  = 2.0,                                    -- advisory, client-side cull
        requires  = function(src) return boolean end,        -- server-side gate (optional)
        onSelect  = function(src) ... end,                  -- server-side action
      }
]]

local interact = {}
local interactions = {} -- id -> spec

--- Register (or replace) an interaction by id.
---@param spec table
---@return boolean ok, string? err
function interact.registerInteraction(spec)
    if type(spec) ~= 'table' then return false, 'BAD_SPEC' end
    if type(spec.id) ~= 'string' or spec.id == '' then return false, 'BAD_ID' end
    if type(spec.onSelect) ~= 'function' then return false, 'NO_ONSELECT' end
    if spec.requires ~= nil and type(spec.requires) ~= 'function' then return false, 'BAD_REQUIRES' end

    interactions[spec.id] = {
        id = spec.id,
        type = spec.type or 'target',
        label = spec.label or spec.id,
        distance = tonumber(spec.distance) or 2.0,
        requires = spec.requires,
        onSelect = spec.onSelect,
        owner = spec.owner, -- owning resource (set by the export wrapper) for purge-on-stop
    }
    Config.Log('debug', ('interaction registered: %s'):format(spec.id))
    return true
end

--- Remove every interaction owned by a (stopped) resource, so dangling onSelect /
--- requires function references cannot accumulate across feature restarts.
---@param ownerResource string
function interact.purgeOwner(ownerResource)
    for id, spec in pairs(interactions) do
        if spec.owner == ownerResource then interactions[id] = nil end
    end
end

--- Remove an interaction.
---@param id string
function interact.unregisterInteraction(id)
    interactions[id] = nil
end

--- A client-safe view of all interactions (no functions) for replication.
---@return table[]
function interact.getInteractions()
    local list = {}
    for _, spec in pairs(interactions) do
        list[#list + 1] = {
            id = spec.id,
            type = spec.type,
            label = spec.label,
            distance = spec.distance,
        }
    end
    return list
end

--- Server-side trigger with re-check. Returns ok + reason.
---@param src integer
---@param id string
---@return boolean ok, string? err
function interact.trigger(src, id)
    local spec = interactions[id]
    if not spec then return false, 'NO_INTERACTION' end

    -- AUTHORITATIVE re-check: never trust the client's claim of eligibility.
    if spec.requires then
        local ok, allowed = pcall(spec.requires, src)
        if not ok then
            Config.Log('error', ('interaction "%s" requires() raised: %s'):format(id, tostring(allowed)))
            return false, 'REQUIRES_ERROR'
        end
        if not allowed then
            return false, 'NOT_ALLOWED'
        end
    end

    local ok, err = pcall(spec.onSelect, src)
    if not ok then
        Config.Log('error', ('interaction "%s" onSelect raised: %s'):format(id, tostring(err)))
        return false, 'ONSELECT_ERROR'
    end

    local bus = SLCore.use('bus')
    if bus then bus.emit('interaction:used', { source = src, id = id }) end
    return true
end

SLCore.module('interact', interact)

-- Net entry point. The server re-checks before doing anything.
RegisterNetEvent('sl_core:interact:trigger', function(id)
    local src = source
    if type(id) ~= 'string' then return end
    interact.trigger(src, id)
end)

-- Purge interactions owned by a feature resource when it stops.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    interact.purgeOwner(resourceName)
end)

-- Cross-resource exports. Call with COLON syntax: exports.sl_core:registerInteraction(spec).
-- registerInteraction stamps the invoking resource as owner so it can be purged on stop.
exports('registerInteraction', function(spec)
    if type(spec) == 'table' and GetInvokingResource then
        spec.owner = GetInvokingResource() or spec.owner
    end
    return interact.registerInteraction(spec)
end)
exports('unregisterInteraction', function(id) return interact.unregisterInteraction(id) end)
exports('getInteractions', function() return interact.getInteractions() end)
