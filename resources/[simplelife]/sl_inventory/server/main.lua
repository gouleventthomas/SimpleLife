--[[
    server/main.lua — sl_inventory authority (v2: grid + equipment slots + "Sol" ground).

    state[src] = { charId, items = { [slot]=stack }, equip = { [equipId]=stack } }.
    Sides used by the UI move op: 'player' (numeric grid), 'equip' (named single-item slots),
    'ground' (the drop pile at the player's feet — auto-resolved), 'container' (an explicit bag id).
    Weight (Config.MaxWeight) counts BOTH the grid AND the equipment slots. All mutations are
    server-side + all-or-nothing; container/ground access is gated by server-side proximity.
]]

local state = {}   -- src -> { charId, items, equip }
local drops = {}   -- dropId -> { coords, items }
local nextDrop = 0

-- ── catalogue helpers ─────────────────────────────────────────────────────────
local function spec(name) return Config.Items[name] end
local function itemW(name) local s = spec(name); return s and s.weight or 0 end
local function weightOf(items)
    local w = 0
    for _, it in pairs(items) do w = w + itemW(it.name) * it.count end
    return w
end
local function emptyMeta(m) return m == nil or next(m) == nil end
local function firstEmpty(items, gridSize)
    for i = 1, gridSize do if not items[i] then return i end end
    return nil
end
local function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local out = {}; for k, v in pairs(t) do out[k] = deepcopy(v) end; return out
end
local function takeSlot(items, slot, count)
    local it = items[slot]; if not it then return false end
    it.count = it.count - count
    if it.count <= 0 then items[slot] = nil end
    return true
end

-- equipment slot catalogue
local EQUIP = {}
for _, s in ipairs(Config.EquipSlots or {}) do EQUIP[s.id] = s end
local function equipAccepts(slotId, name)
    if not name then return false end
    local cfg = EQUIP[slotId]
    if not cfg or not cfg.accept then return true end  -- permissive
    local cat = (spec(name) or {}).category
    for _, c in ipairs(cfg.accept) do if c == cat then return true end end
    return false
end
local function equipWeight(equip)
    local w = 0
    for _, it in pairs(equip or {}) do w = w + itemW(it.name) * (it.count or 1) end
    return w
end
local function playerWeight(st) return weightOf(st.items) + equipWeight(st.equip) end

-- ── low-level grid mutators ───────────────────────────────────────────────────

-- Add `count` of `name` into a numeric `items` table (stacking empty-metadata), ALL-OR-NOTHING.
local function addTo(items, name, count, meta, maxWeight, gridSize)
    local s = spec(name)
    if not s then return false, 'BAD_ITEM' end
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false, 'BAD_COUNT' end
    if weightOf(items) + itemW(name) * count > maxWeight then return false, 'OVERWEIGHT' end

    local stackMax = s.stack or 1
    local stackable = emptyMeta(meta) and stackMax > 1

    local free = 0
    for i = 1, gridSize do if not items[i] then free = free + 1 end end
    local capacity
    if stackable then
        capacity = free * stackMax
        for _, it in pairs(items) do
            if it.name == name and emptyMeta(it.metadata) and it.count < stackMax then
                capacity = capacity + (stackMax - it.count)
            end
        end
    else
        capacity = free
    end
    if capacity < count then return false, 'NO_SLOT' end

    if stackable then
        for _, it in pairs(items) do
            if it.name == name and emptyMeta(it.metadata) and it.count < stackMax then
                local put = math.min(stackMax - it.count, count)
                it.count = it.count + put; count = count - put
                if count <= 0 then return true end
            end
        end
    end
    while count > 0 do
        local slot = firstEmpty(items, gridSize)
        local put = stackable and math.min(stackMax, count) or 1
        items[slot] = { name = name, count = put, metadata = (not emptyMeta(meta)) and deepcopy(meta) or nil }
        count = count - put
    end
    return true
end

local function removeName(items, name, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false, 'BAD_COUNT' end
    local have = 0
    for _, it in pairs(items) do if it.name == name then have = have + it.count end end
    if have < count then return false, 'NOT_ENOUGH' end
    for slot, it in pairs(items) do
        if count <= 0 then break end
        if it.name == name then
            local take = math.min(it.count, count); it.count = it.count - take; count = count - take
            if it.count <= 0 then items[slot] = nil end
        end
    end
    return true
end

-- Move/merge/swap/split between two numeric item tables. Respects BOTH weight caps on a swap.
local function moveBetween(fromItems, toItems, fromSlot, toSlot, count, fromMax, toMax, gridSize)
    local src = fromItems[fromSlot]
    if not src then return false, 'EMPTY' end
    count = math.floor(tonumber(count) or src.count)
    if count <= 0 or count > src.count then count = src.count end
    if toSlot < 1 or toSlot > gridSize then return false, 'BAD_SLOT' end

    local crossing = fromItems ~= toItems
    local dst = toItems[toSlot]
    if not dst then
        if crossing and weightOf(toItems) + itemW(src.name) * count > toMax then return false, 'OVERWEIGHT' end
        toItems[toSlot] = { name = src.name, count = count, metadata = src.metadata }
        if count >= src.count then fromItems[fromSlot] = nil else src.count = src.count - count end
        return true
    elseif dst.name == src.name and emptyMeta(dst.metadata) and emptyMeta(src.metadata) then
        local stackMax = (spec(src.name).stack or 1)
        local put = math.min(stackMax - dst.count, count)
        if put <= 0 then return false, 'FULL' end
        if crossing and weightOf(toItems) + itemW(src.name) * put > toMax then return false, 'OVERWEIGHT' end
        dst.count = dst.count + put; src.count = src.count - put
        if src.count <= 0 then fromItems[fromSlot] = nil end
        return true
    else
        if count ~= src.count then return false, 'NO_PARTIAL_SWAP' end
        if crossing then
            local toAfter = weightOf(toItems) - itemW(dst.name) * dst.count + itemW(src.name) * src.count
            if toAfter > toMax then return false, 'OVERWEIGHT' end
            local fromAfter = weightOf(fromItems) - itemW(src.name) * src.count + itemW(dst.name) * dst.count
            if fromAfter > fromMax then return false, 'OVERWEIGHT' end
        end
        fromItems[fromSlot], toItems[toSlot] = dst, src
        return true
    end
end

-- ── persistence ───────────────────────────────────────────────────────────────
local function decodeInventory(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) == 'string' and raw ~= '' then
        local ok, d = pcall(json.decode, raw); if ok and type(d) == 'table' then return d end
    end
    return {}
end

local function loadInventory(src, charId)
    local decoded = decodeInventory(exports.sl_core:dbScalar('SELECT inventory FROM characters WHERE id = ?', { charId }))
    local arr = decoded.items or decoded  -- old data is a bare array; new is { items=[], equip={} }
    local items, equip = {}, {}
    for _, e in ipairs(arr or {}) do
        if e.name and e.slot and spec(e.name) then
            items[e.slot] = { name = e.name, count = e.count or 1, metadata = e.metadata }
        end
    end
    if type(decoded.equip) == 'table' then
        for id, e in pairs(decoded.equip) do
            if EQUIP[id] and e and e.name and spec(e.name) then
                equip[id] = { name = e.name, count = e.count or 1, metadata = e.metadata }
            end
        end
    end
    state[src] = { charId = charId, items = items, equip = equip }
    Config.Log('debug', ('loaded inventory src=%d charId=%s (%dg)'):format(src, tostring(charId), playerWeight(state[src])))
end

local function saveInventory(src)
    local st = state[src]; if not st then return end
    local arr = {}
    for slot, it in pairs(st.items) do arr[#arr + 1] = { slot = slot, name = it.name, count = it.count, metadata = it.metadata } end
    local equip = {}
    for id, it in pairs(st.equip or {}) do equip[id] = { name = it.name, count = it.count, metadata = it.metadata } end
    exports.sl_core:dbUpdate('UPDATE characters SET inventory = ? WHERE id = ?',
        { json.encode({ items = arr, equip = equip }), st.charId })
end

-- ── lifecycle ─────────────────────────────────────────────────────────────────
local function onCharLoaded(payload)
    if not payload or not payload.source or not payload.charId then return end
    if state[payload.source] then saveInventory(payload.source) end  -- flush before re-bind
    loadInventory(payload.source, payload.charId)
end
local function onCharLogout(payload)
    if payload and payload.source then saveInventory(payload.source); state[payload.source] = nil end
end
CreateThread(function()
    while GetResourceState('sl_core') ~= 'started' do Wait(100) end
    exports.sl_core:on('char:loaded', onCharLoaded)
    exports.sl_core:on('char:logout', onCharLogout)
    local loaded = {}
    pcall(function() loaded = exports.sl_core:loadedChars() or {} end)  -- tolerate an older sl_core
    for _, e in ipairs(loaded) do
        if e.source and e.charId and not state[e.source] then loadInventory(e.source, e.charId) end
    end
    Config.Log('info', 'ready — hooked sl_core char lifecycle')
end)
CreateThread(function() while true do Wait(120000); for src in pairs(state) do saveInventory(src) end end end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(state) do saveInventory(src) end
end)

-- ── views (client-facing) ─────────────────────────────────────────────────────
local function viewItems(items)
    local list = {}
    for slot, it in pairs(items) do
        local s = spec(it.name) or {}
        list[#list + 1] = {
            slot = slot, name = it.name, count = it.count, label = s.label or it.name,
            weight = s.weight or 0, category = s.category or 'misc', usable = s.usable == true,
            stack = s.stack or 1, desc = s.desc, metadata = it.metadata,
        }
    end
    return list
end
local function equipView(equip)
    local out = {}
    for id, it in pairs(equip or {}) do
        local s = spec(it.name) or {}
        out[id] = { slot = id, name = it.name, count = it.count, label = s.label or it.name,
            weight = s.weight or 0, category = s.category or 'misc', usable = s.usable == true,
            stack = s.stack or 1, desc = s.desc, metadata = it.metadata }
    end
    return out
end
local function playerView(src)
    local st = state[src]; if not st then return nil end
    return { items = viewItems(st.items), equip = equipView(st.equip), weight = playerWeight(st),
        maxWeight = Config.MaxWeight, slots = Config.GridSize }
end
local function dropView(id)
    local d = drops[id]; if not d then return nil end
    return { id = id, items = viewItems(d.items), weight = weightOf(d.items),
        maxWeight = Config.DropMaxWeight, slots = Config.GridSize }
end

-- ── ground drops ──────────────────────────────────────────────────────────────
local function spawnDrop(coords)
    nextDrop = nextDrop + 1
    local id = nextDrop
    drops[id] = { coords = coords, items = {} }
    TriggerClientEvent('sl_inventory:dropCreated', -1, id, coords)
    return id
end
local function cleanupDrop(id)
    local d = drops[id]
    if d and not next(d.items) then drops[id] = nil; TriggerClientEvent('sl_inventory:dropRemoved', -1, id) end
end
local function nearDrop(src, id)
    local d = id and drops[id]; if not d then return false end
    local ped = GetPlayerPed(src); if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(d.coords.x, d.coords.y, d.coords.z)) <= (Config.DropReach or 3.0)
end
-- the ground pile at the player's feet (nearest drop within reach; created on first deposit)
local function groundDrop(src, create)
    local ped = GetPlayerPed(src); if not ped or ped == 0 then return nil end
    local p = GetEntityCoords(ped)
    local best, bestD
    for id, d in pairs(drops) do
        local dd = #(p - vector3(d.coords.x, d.coords.y, d.coords.z))
        if dd <= (Config.DropReach or 3.0) and (not bestD or dd < bestD) then best, bestD = id, dd end
    end
    if best then return best end
    if create then return spawnDrop({ x = p.x, y = p.y, z = p.z - 0.9 }) end
    return nil
end

local function emptyGround()
    return { kind = 'ground', items = {}, weight = 0, maxWeight = Config.DropMaxWeight, slots = Config.GridSize, label = 'Sol' }
end
local function groundView(src)
    local gid = groundDrop(src, false)
    local v = gid and dropView(gid)
    if not v then return emptyGround() end
    v.kind = 'ground'; v.label = 'Sol'; return v
end
-- the right panel = an explicit bag (if near) else the ground at the player's feet
local function rightPanel(src, cid)
    if cid and nearDrop(src, cid) and drops[cid] then
        local v = dropView(cid); v.kind = 'container'; v.label = 'Sac'; return v
    end
    return groundView(src)
end

-- ── equipment move ────────────────────────────────────────────────────────────
local function moveEquip(st, src, from, to, cid, groundId)
    st.equip = st.equip or {}
    local function numeric(side)
        if side == 'container' then return cid and drops[cid] and drops[cid].items end
        if side == 'ground' then return groundId and drops[groundId] and drops[groundId].items end
        return st.items
    end

    if from.inv == 'equip' and to.inv == 'equip' then
        local a, b = tostring(from.slot), tostring(to.slot)
        if not EQUIP[a] or not EQUIP[b] then return false end
        local ea, eb = st.equip[a], st.equip[b]
        if ea and not equipAccepts(b, ea.name) then return false end
        if eb and not equipAccepts(a, eb.name) then return false end
        st.equip[a], st.equip[b] = eb, ea
        return true

    elseif to.inv == 'equip' then
        local slot = tostring(to.slot)
        if not EQUIP[slot] then return false end
        local fromItems = numeric(from.inv); if not fromItems then return false end
        local srcIt = fromItems[tonumber(from.slot)]; if not srcIt then return false end
        if not equipAccepts(slot, srcIt.name) then return false, 'WRONG_SLOT' end
        if from.inv ~= 'player' then
            if playerWeight(st) + itemW(srcIt.name) * srcIt.count > Config.MaxWeight then return false, 'OVERWEIGHT' end
        end
        local occupant = st.equip[slot]
        fromItems[tonumber(from.slot)] = occupant or nil  -- swap occupant back / clear slot
        st.equip[slot] = srcIt
        return true

    else -- from equip -> numeric
        local slot = tostring(from.slot)
        local eqIt = st.equip[slot]; if not eqIt then return false end
        local toItems = numeric(to.inv); if not toItems then return false end
        local toSlot = tonumber(to.slot)
        if toSlot == -1 then toSlot = firstEmpty(toItems, Config.GridSize) end
        if not toSlot then return false end
        local dst = toItems[toSlot]
        if not dst then
            toItems[toSlot] = eqIt; st.equip[slot] = nil; return true
        elseif dst.name == eqIt.name and emptyMeta(dst.metadata) and emptyMeta(eqIt.metadata) then
            local put = math.min((spec(eqIt.name).stack or 1) - dst.count, eqIt.count)
            if put <= 0 then return false end
            dst.count = dst.count + put; eqIt.count = eqIt.count - put
            if eqIt.count <= 0 then st.equip[slot] = nil end
            return true
        else
            if not equipAccepts(slot, dst.name) then return false, 'WRONG_SLOT' end
            toItems[toSlot] = eqIt; st.equip[slot] = dst; return true
        end
    end
end

-- ── callbacks ─────────────────────────────────────────────────────────────────
lib.callback.register('sl_inventory:getState', function(src, containerId)
    return { player = playerView(src), container = rightPanel(src, containerId) }
end)

lib.callback.register('sl_inventory:move', function(src, data)
    local st = state[src]
    if not st or type(data) ~= 'table' then return { ok = false } end
    local from, to, count, cid = data.from, data.to, data.count, data.containerId
    if type(from) ~= 'table' or type(to) ~= 'table' then return { ok = false } end

    local groundId
    if from.inv == 'ground' or to.inv == 'ground' then
        groundId = groundDrop(src, to.inv == 'ground')
        if not groundId then return { ok = false, player = playerView(src), container = rightPanel(src, cid) } end
    end
    if (from.inv == 'container' or to.inv == 'container') and not nearDrop(src, cid) then
        return { ok = false, player = playerView(src), container = rightPanel(src, cid) }
    end

    local ok
    if from.inv == 'equip' or to.inv == 'equip' then
        ok = moveEquip(st, src, from, to, cid, groundId)
    else
        local function refItems(side)
            if side == 'container' then return cid and drops[cid] and drops[cid].items end
            if side == 'ground' then return groundId and drops[groundId] and drops[groundId].items end
            return st.items
        end
        local function refMax(side)
            if side == 'container' or side == 'ground' then return Config.DropMaxWeight end
            return Config.MaxWeight - equipWeight(st.equip)  -- remaining grid capacity given equip weight
        end
        local fromItems, toItems = refItems(from.inv), refItems(to.inv)
        if fromItems and toItems then
            local toSlot = tonumber(to.slot)
            if toSlot == -1 then toSlot = firstEmpty(toItems, Config.GridSize) end
            if toSlot then ok = moveBetween(fromItems, toItems, tonumber(from.slot), toSlot, count, refMax(from.inv), refMax(to.inv), Config.GridSize) end
        end
    end

    if groundId then cleanupDrop(groundId) end
    if cid then cleanupDrop(cid) end
    return { ok = ok == true, player = playerView(src), container = rightPanel(src, cid) }
end)

lib.callback.register('sl_inventory:use', function(src, slot)
    local st = state[src]; if not st then return { ok = false } end
    local it = st.items[tonumber(slot)]; if not it then return { ok = false } end
    local s = spec(it.name)
    if not s or not s.usable then return { ok = false, reason = 'NOT_USABLE' } end
    exports.sl_core:emit('item:used', { source = src, item = it.name, slot = tonumber(slot) })
    TriggerClientEvent('sl_inventory:onUse', src, it.name)
    if s.removeOnUse then takeSlot(st.items, tonumber(slot), 1) end
    return { ok = true, player = playerView(src) }
end)

-- right-click "Jeter" -> drop the slot's stack onto the ground pile at your feet
lib.callback.register('sl_inventory:drop', function(src, data)
    local st = state[src]; if not st then return { ok = false } end
    local slot, count = tonumber(data and data.slot), tonumber(data and data.count)
    local it = st.items[slot]; if not it then return { ok = false } end
    count = math.floor(count or it.count); if count <= 0 or count > it.count then count = it.count end
    local gid = groundDrop(src, true); if not gid then return { ok = false } end
    local ok = addTo(drops[gid].items, it.name, count, it.metadata, Config.DropMaxWeight, Config.GridSize)
    if not ok then cleanupDrop(gid); return { ok = false, player = playerView(src) } end
    takeSlot(st.items, slot, count)
    return { ok = true, player = playerView(src), container = rightPanel(src, nil) }
end)

lib.callback.register('sl_inventory:give', function(src, data)
    local st = state[src]; if not st then return { ok = false } end
    local slot, count, targetId = tonumber(data and data.slot), tonumber(data and data.count), tonumber(data and data.target)
    local it = st.items[slot]; if not it then return { ok = false } end
    count = math.floor(count or 1); if count <= 0 or count > it.count then count = it.count end
    if not targetId or targetId == src or not state[targetId] then return { ok = false, reason = 'NO_TARGET' } end
    local sp, tp = GetPlayerPed(src), GetPlayerPed(targetId)
    if sp == 0 or tp == 0 or #(GetEntityCoords(sp) - GetEntityCoords(tp)) > 4.0 then return { ok = false, reason = 'TOO_FAR' } end
    local okAdd = addTo(state[targetId].items, it.name, count, it.metadata, Config.MaxWeight - equipWeight(state[targetId].equip), Config.GridSize)
    if not okAdd then return { ok = false, reason = 'TARGET_FULL' } end
    takeSlot(st.items, slot, count)
    TriggerClientEvent('sl_inventory:notify', targetId, 'success', ('Reçu : %dx %s'):format(count, (spec(it.name) or {}).label or it.name))
    return { ok = true, player = playerView(src) }
end)

lib.callback.register('sl_inventory:nearbyPlayers', function(src)
    local out = {}
    local ped = GetPlayerPed(src); local me = ped ~= 0 and GetEntityCoords(ped) or nil
    if not me then return out end
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if pid ~= src and state[pid] then
            local tp = GetPlayerPed(pid)
            if tp ~= 0 and #(GetEntityCoords(tp) - me) <= 4.0 then
                local char = exports.sl_core:getChar(pid)
                out[#out + 1] = { id = pid, name = char and (char.firstname .. ' ' .. char.lastname) or ('Joueur ' .. pid) }
            end
        end
    end
    return out
end)

-- ── cross-resource exports ────────────────────────────────────────────────────
exports('addItem', function(src, name, count, meta)
    local st = state[src]; if not st then return false end
    local ok = addTo(st.items, name, count, meta, Config.MaxWeight - equipWeight(st.equip), Config.GridSize)
    if ok then TriggerClientEvent('sl_inventory:refresh', src) end
    return ok
end)
exports('removeItem', function(src, name, count)
    local st = state[src]; if not st then return false end
    local ok = removeName(st.items, name, count)
    if ok then TriggerClientEvent('sl_inventory:refresh', src) end
    return ok
end)
exports('getItemCount', function(src, name)
    local st = state[src]; if not st then return 0 end
    local n = 0
    for _, it in pairs(st.items) do if it.name == name then n = n + it.count end end
    for _, it in pairs(st.equip or {}) do if it.name == name then n = n + it.count end end
    return n
end)
exports('hasItem', function(src, name, count)
    return exports.sl_inventory:getItemCount(src, name) >= (tonumber(count) or 1)
end)

-- Count an item in the GRID only (excludes equipment slots). `removeItem` only removes from the
-- grid, so shops/crafting should gate deposits on this so a count never promises more than can
-- actually be removed.
exports('getGridItemCount', function(src, name)
    local st = state[src]; if not st then return 0 end
    local n = 0
    for _, it in pairs(st.items) do if it.name == name then n = n + it.count end end
    return n
end)
exports('canCarry', function(src, name, count)
    local st = state[src]; if not st then return false end
    return playerWeight(st) + itemW(name) * (tonumber(count) or 1) <= Config.MaxWeight
end)

-- True if the player can take `grams` MORE weight. Lets multi-item carts (shops) pre-check
-- the whole basket's weight in one call before charging money.
exports('canCarryWeight', function(src, grams)
    local st = state[src]; if not st then return false end
    return playerWeight(st) + (tonumber(grams) or 0) <= Config.MaxWeight
end)

-- Item catalogue access for other resources (shops, crafting). Returns a flat copy of the spec.
exports('getItem', function(name)
    local s = spec(name); if not s then return nil end
    return { name = name, label = s.label, weight = s.weight, stack = s.stack,
             category = s.category, usable = s.usable, desc = s.desc }
end)
exports('getItems', function()
    local out = {}
    for name, s in pairs(Config.Items) do
        out[#out + 1] = { name = name, label = s.label, weight = s.weight, stack = s.stack,
                          category = s.category, usable = s.usable, desc = s.desc }
    end
    return out
end)

-- Wipe a player's whole inventory (grid + equipment). For admin/dev tooling (F10 menu).
exports('clearInventory', function(src)
    local st = state[src]; if not st then return false end
    st.items, st.equip = {}, {}
    saveInventory(src)
    TriggerClientEvent('sl_inventory:refresh', src)
    return true
end)

-- ── item metadata (device-centric items: phone uuid, sim number, …) ─────────────
-- Find the first slot (grid first, then equipment) holding `name`. Returns the live
-- item ref so callers can read/patch its metadata.
local function findItemRef(st, name)
    for _, it in pairs(st.items) do if it.name == name then return it end end
    for _, it in pairs(st.equip or {}) do if it.name == name then return it end end
    return nil
end

-- Read the metadata of the first `name` item the player carries.
--   returns a COPY of the metadata table (possibly empty {}) if they have one,
--   or nil if they don't have the item at all (lets callers distinguish the two).
exports('getItemMeta', function(src, name)
    local st = state[src]; if not st then return nil end
    local it = findItemRef(st, name)
    if not it then return nil end
    return deepcopy(it.metadata or {})
end)

-- List the metadata of EVERY `name` item the player carries (grid + equip). Used for
-- reverse lookups (e.g. "which online player holds the phone with this uuid?") — handles
-- a player carrying more than one of the item, unlike getItemMeta (first only).
exports('getItemMetaList', function(src, name)
    local st = state[src]; if not st then return {} end
    local out = {}
    for _, it in pairs(st.items) do if it.name == name then out[#out + 1] = deepcopy(it.metadata or {}) end end
    for _, it in pairs(st.equip or {}) do if it.name == name then out[#out + 1] = deepcopy(it.metadata or {}) end end
    return out
end)

-- Merge `patch` into the metadata of the first `name` item the player carries, persist
-- and refresh. Used to brand a phone with its uuid on first boot (device-centric).
-- Returns false if the player isn't carrying the item.
exports('setItemMeta', function(src, name, patch)
    local st = state[src]; if not st then return false end
    local it = findItemRef(st, name)
    if not it then return false end
    it.metadata = it.metadata or {}
    if type(patch) == 'table' then
        for k, v in pairs(patch) do it.metadata[k] = v end
    end
    saveInventory(src)
    TriggerClientEvent('sl_inventory:refresh', src)
    return true
end)

-- ── dev commands (env=dev) ────────────────────────────────────────────────────
RegisterCommand('giveitem', function(src, args)
    if src == 0 or GlobalState.slCoreEnv ~= 'dev' then return end
    local st = state[src]; if not st then return end
    local name, count = args[1], math.floor(tonumber(args[2]) or 1)
    if not name or not spec(name) then TriggerClientEvent('sl_inventory:notify', src, 'error', 'Item inconnu: ' .. tostring(name)); return end
    local ok = addTo(st.items, name, count, nil, Config.MaxWeight - equipWeight(st.equip), Config.GridSize)
    TriggerClientEvent('sl_inventory:notify', src, ok and 'success' or 'error',
        ok and ('Reçu %dx %s'):format(count, spec(name).label) or 'Trop lourd / plein')
    if ok then TriggerClientEvent('sl_inventory:refresh', src) end
end, false)
RegisterCommand('clearinv', function(src)
    if src == 0 or GlobalState.slCoreEnv ~= 'dev' then return end
    local st = state[src]; if not st then return end
    st.items = {}; st.equip = {}
    TriggerClientEvent('sl_inventory:notify', src, 'info', 'Inventaire vidé.')
    TriggerClientEvent('sl_inventory:refresh', src)
end, false)
