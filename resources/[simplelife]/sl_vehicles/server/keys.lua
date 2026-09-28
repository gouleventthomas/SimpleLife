--[[
    server/keys.lua — virtual keys (share/revoke), remote actions (lock/engine/locate), and
    server-side hotwire authorisation. The engine GATE itself is enforced on the client
    (client/keys.lua) from the replicated 'sl:veh' key-set; the server is the source of truth for
    who holds a key and validates hotwire item possession.
]]

local hotCooldown = {}   -- src -> gameTimer when hotwire is allowed again

-- ── key holders ──────────────────────────────────────────────────────────────────
function SLV.keyHolders(dbId)
    local row = SLV.getVehicleRow(dbId)
    if not row then return {} end
    local out = { { charid = tonumber(row.charid), name = SLV.charName(row.charid) or ('#' .. row.charid), role = 'owner' } }
    for _, r in ipairs(SLV.query('SELECT charid FROM vehicle_keys WHERE vehicle_id = ? ORDER BY granted', { dbId }) or {}) do
        out[#out + 1] = { charid = tonumber(r.charid), name = SLV.charName(r.charid) or ('#' .. r.charid), role = 'shared' }
    end
    return out
end

-- Grant a key to the nearest player (by source) — returns ok + their name.
function SLV.grantKeyToSource(ownerSrc, dbId, targetSrc)
    local ownerChar = SLV.charId(ownerSrc)
    if tonumber(SLV.ownerOf(dbId)) ~= tonumber(ownerChar) then return { ok = false, reason = 'NOT_OWNER' } end
    local targetChar = SLV.charId(targetSrc)
    if not targetChar then return { ok = false, reason = 'NO_TARGET' } end
    if tonumber(targetChar) == tonumber(ownerChar) then return { ok = false, reason = 'SELF' } end
    SLV.update('INSERT IGNORE INTO vehicle_keys (vehicle_id, charid) VALUES (?, ?)', { dbId, targetChar })
    SLV.refreshKeysState(dbId)
    local row = SLV.getVehicleRow(dbId)
    local label = (Config.CatalogModel(row.model) or {}).label or row.model
    SLV.notify(targetSrc, 'success', ('Clé reçue : %s (%s)'):format(label, row.plate))
    return { ok = true, name = SLV.charName(targetChar) }
end

function SLV.revokeKey(ownerSrc, dbId, targetCharId)
    local ownerChar = SLV.charId(ownerSrc)
    if tonumber(SLV.ownerOf(dbId)) ~= tonumber(ownerChar) then return { ok = false, reason = 'NOT_OWNER' } end
    SLV.update('DELETE FROM vehicle_keys WHERE vehicle_id = ? AND charid = ?', { dbId, targetCharId })
    SLV.refreshKeysState(dbId)
    local tsrc = SLV.sourceOfChar(targetCharId)
    if tsrc then SLV.notify(tsrc, 'inform', 'Une clé de véhicule vous a été retirée.') end
    return { ok = true }
end

-- ── remote actions (phone) ────────────────────────────────────────────────────────
-- All require the requester to hold a key for the vehicle.
local function requireKey(src, dbId)
    return SLV.hasKey(SLV.charId(src), dbId)
end

function SLV.remoteLock(src, dbId, locked)
    if not requireKey(src, dbId) then return { ok = false, reason = 'NO_KEY' } end
    local netId = SLV.netOfDb(dbId)
    if not netId then return { ok = false, reason = 'NOT_OUT' } end   -- only live cars can (un)lock
    local veh = SLV.entityFromNet(netId)
    if veh then
        SetVehicleDoorsLocked(veh, locked and 2 or 1)
        Entity(veh).state:set('sl:locked', locked and true or false, true)
        TriggerClientEvent('sl_vehicles:keyChirp', src, netId, locked)
    end
    return { ok = true, locked = locked }
end

function SLV.remoteEngine(src, dbId, on)
    if not requireKey(src, dbId) then return { ok = false, reason = 'NO_KEY' } end
    local netId = SLV.netOfDb(dbId)
    if not netId then return { ok = false, reason = 'NOT_OUT' } end
    local veh = SLV.entityFromNet(netId)
    if veh then Entity(veh).state:set('sl:engine', on and true or false, true) end
    return { ok = true, engine = on }
end

-- Returns coords for the phone GPS (live position if out, else parked spot) and drops a waypoint.
function SLV.locate(src, dbId)
    if not requireKey(src, dbId) then return { ok = false, reason = 'NO_KEY' } end
    local coords, live
    local netId = SLV.netOfDb(dbId)
    if netId then
        local veh = SLV.entityFromNet(netId)
        if veh then local c = GetEntityCoords(veh); coords = { x = c.x, y = c.y, z = c.z }; live = true end
    end
    if not coords then
        local row = SLV.getVehicleRow(dbId)
        if row and row.status == 'impound' then return { ok = false, reason = 'IMPOUND' } end
        if row and row.park_x then coords = { x = row.park_x, y = row.park_y, z = row.park_z }; live = false end
    end
    if not coords then return { ok = false, reason = 'UNKNOWN' } end
    TriggerClientEvent('sl_vehicles:setWaypoint', src, coords)
    return { ok = true, coords = coords, live = live }
end

-- ── hotwire authorisation ──────────────────────────────────────────────────────────
-- Validates the thief carries the tools + isn't on cooldown, applies engine damage server-side,
-- and returns ok. The client then locally permits ignition for this car until the engine stops.
function SLV.hotwire(src, netId)
    if not Config.Hotwire.enabled then return { ok = false, reason = 'DISABLED' } end
    local dbId = SLV.dbIdOfNet(netId)
    if not dbId then return { ok = false, reason = 'NOT_OWNED' } end  -- random cars need no hotwire
    if SLV.hasKey(SLV.charId(src), dbId) then return { ok = false, reason = 'HAS_KEY' } end
    local veh = SLV.entityFromNet(netId)
    if not veh then return { ok = false, reason = 'GONE' } end
    if not SLV.near(src, GetEntityCoords(veh), 4.5) then return { ok = false, reason = 'TOO_FAR' } end
    local now = GetGameTimer()
    if hotCooldown[src] and now < hotCooldown[src] then return { ok = false, reason = 'COOLDOWN' } end
    if Config.Hotwire.needLockpick and not exports.sl_inventory:hasItem(src, 'lockpick') then
        return { ok = false, reason = 'NO_LOCKPICK' }
    end
    if Config.Hotwire.needStartkit and not exports.sl_inventory:hasItem(src, 'startkit') then
        return { ok = false, reason = 'NO_STARTKIT' }
    end
    hotCooldown[src] = now + (Config.Hotwire.cooldownMs or 20000)
    -- consume the startkit on a successful bypass (the lockpick stays — it just picks the door)
    if Config.Hotwire.needStartkit then exports.sl_inventory:removeItem(src, 'startkit', 1) end
    local eh = GetVehicleEngineHealth(veh)
    SetVehicleEngineHealth(veh, math.max(100.0, (eh or 1000.0) - (Config.Hotwire.engineDamage or 250.0)))
    SetVehicleDoorsLocked(veh, 1)  -- the door is now picked open
    -- alert the owner (phone) — handled by leads/phone notify
    local owner = SLV.ownerOf(dbId)
    local osrc = SLV.sourceOfChar(owner)
    if osrc then
        local c = veh and GetEntityCoords(veh) or nil
        TriggerClientEvent('sl_vehicles:theftAlert', osrc, {
            plate = (SLV.getVehicleRow(dbId) or {}).plate,
            coords = c and { x = c.x, y = c.y, z = c.z } or nil,
        })
    end
    return { ok = true }
end

-- Cooldown check (client asks before showing the pick prompt, optional QoL).
function SLV.hotReady(src)
    return not (hotCooldown[src] and GetGameTimer() < hotCooldown[src])
end

Config.Log('info', 'keys ready')
