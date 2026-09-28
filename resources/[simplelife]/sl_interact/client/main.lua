--[[
    client/main.lua — the ONE interaction surface (ox_target wrapper).

    API (COLON syntax, e.g. exports.sl_interact:addModel(...)):
      addModel(models, options)           -> wire ox_target on prop model(s)
      addCoords(coords, radius, options)  -> a sphere zone at a world point; returns zoneId
      addEntity(netIds, options)          -> on networked entit(y/ies)
      addLocalEntity(entities, options)   -> on local (script) entit(y/ies)
      removeZone(zoneId)                  -> remove a zone returned by addCoords

    An `option` = {
      label             = 'Ouvrir',                 -- prompt text
      icon              = 'fa-solid fa-...',        -- optional (defaults to Config.Defaults)
      distance          = 2.0,                      -- optional (defaults to Config.Defaults)
      canInteract       = function(entity, distance, coords, name) return bool end,  -- optional
      onSelect          = function(data) ... end,   -- client action (data from ox_target)
      serverInteraction = 'sl_core_id',             -- optional: ALSO fire sl_core's server re-check
    }

    Targets are tracked per INVOKING resource and purged on that resource's onResourceStop,
    because ox_target attributes them to sl_interact and would otherwise never clean them when
    a feature restarts.
]]

local owned = {}  -- resource -> array of remover functions
local seq = 0     -- global option-name counter (ox_target needs unique option names)

local function nextSeq() seq = seq + 1; return seq end

local function track(resource, remover)
    resource = resource or GetCurrentResourceName()
    owned[resource] = owned[resource] or {}
    owned[resource][#owned[resource] + 1] = remover
end

-- Translate SimpleLife option specs -> ox_target option specs (+ defaults + server bridge).
local function build(resource, options)
    local out = {}
    for i, o in ipairs(options or {}) do
        local serverId = o.serverInteraction
        local clientSelect = o.onSelect
        out[i] = {
            name        = o.name or ('sl_%s_%d'):format(resource or 'x', nextSeq()),
            label       = o.label or 'Interagir',
            icon        = o.icon or Config.Defaults.icon,
            distance    = tonumber(o.distance) or Config.Defaults.distance,
            canInteract = o.canInteract,
            onSelect    = function(data)
                if serverId then TriggerServerEvent('sl_core:interact:trigger', serverId) end
                if clientSelect then clientSelect(data) end
            end,
        }
    end
    return out
end

local function optionNames(opts)
    local names = {}
    for _, o in ipairs(opts) do names[#names + 1] = o.name end
    return names
end

-- ── public API (the `res` is captured by the export wrapper for cleanup) ──────

local Interact = {}

function Interact.addModel(res, models, options)
    local opts = build(res, options)
    exports.ox_target:addModel(models, opts)
    local names = optionNames(opts)
    track(res, function() exports.ox_target:removeModel(models, names) end)
end

function Interact.addCoords(res, coords, radius, options)
    local zid = exports.ox_target:addSphereZone({
        coords  = coords,
        radius  = tonumber(radius) or 1.5,
        debug   = Config.Debug,
        options = build(res, options),
    })
    track(res, function() if zid then exports.ox_target:removeZone(zid) end end)
    return zid
end

function Interact.addEntity(res, netIds, options)
    local opts = build(res, options)
    exports.ox_target:addEntity(netIds, opts)
    local names = optionNames(opts)
    track(res, function() exports.ox_target:removeEntity(netIds, names) end)
end

function Interact.addLocalEntity(res, entities, options)
    local opts = build(res, options)
    exports.ox_target:addLocalEntity(entities, opts)
    local names = optionNames(opts)
    track(res, function() exports.ox_target:removeLocalEntity(entities, names) end)
end

-- Purge a feature's targets when IT stops (ox_target only auto-cleans sl_interact's own).
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then return end
    local removers = owned[res]
    if not removers then return end
    for _, r in ipairs(removers) do pcall(r) end
    owned[res] = nil
    Config.Log('debug', ('purged interactions for stopped resource: %s'):format(res))
end)

-- ── exports (COLON syntax; GetInvokingResource() identifies the feature) ──────
exports('addModel', function(models, options) return Interact.addModel(GetInvokingResource(), models, options) end)
exports('addCoords', function(coords, radius, options) return Interact.addCoords(GetInvokingResource(), coords, radius, options) end)
exports('addEntity', function(netIds, options) return Interact.addEntity(GetInvokingResource(), netIds, options) end)
exports('addLocalEntity', function(entities, options) return Interact.addLocalEntity(GetInvokingResource(), entities, options) end)
exports('removeZone', function(zoneId) if zoneId then return exports.ox_target:removeZone(zoneId) end end)

Config.Log('info', 'ready (ox_target wrapper)')
