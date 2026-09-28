--[[
    server/convoy.lua — the import / convoy restock loop.

    1) An employee with 'import' orders models+quantities at the GESTION terminal. The till pays
       the IMPORT cost (catalog price). The order becomes READY after Config.Import.normalDelay
       (or priorityDelay for a flat priority fee).
    2) When ready, the ordered cars spawn (locked, neutral) on marked PORT spots; the whole
       dealership is notified.
    3) The employee takes a flatbed (single) / hauler+carrier (multi) and LOADS each car by
       interaction (server assigns a free trailer slot; the client attaches it).
    4) At the dealership DELIVERY bay the employee UNLOADS each car by interaction → it's added to
       the dealership stock and the order's remaining count drops.
]]

SLV.methods = SLV.methods or {}
local M = SLV.methods

local portUnits = {}   -- netId -> { orderId, dealerId, model, category, state='port'|'loaded'|'delivered', by, slot }

-- ── orders view (for gestion) ───────────────────────────────────────────────────────
function SLV.ordersFor(dealerId)
    local now = os.time()
    local out = {}
    for _, r in ipairs(SLV.query([[SELECT id, model, qty, remaining, ready_at, priority, status
                                   FROM dealership_orders WHERE dealer_id = ? AND status IN ('pending','ready')
                                   ORDER BY id]], { dealerId }) or {}) do
        local spec = Config.CatalogModel(r.model)
        out[#out + 1] = {
            id = r.id, model = r.model, label = spec and spec.label or r.model,
            qty = r.qty, remaining = r.remaining, status = r.status, priority = r.priority == 1,
            eta = math.max(0, (tonumber(r.ready_at) or 0) - now),
        }
    end
    return out
end

-- count READY port units of a dealer not yet loaded
local function readyUnits(dealerId)
    local n = 0
    for _, u in pairs(portUnits) do
        if u.dealerId == dealerId and u.state == 'port' then n = n + 1 end
    end
    return n
end

local function freePortSpot()
    local taken = {}
    for net, u in pairs(portUnits) do
        if u.state == 'port' then
            local veh = SLV.entityFromNet(net)
            if veh then
                local c = GetEntityCoords(veh)
                taken[#taken + 1] = c
            end
        end
    end
    for _, s in ipairs(Config.Import.portSpots) do
        local free = true
        for _, c in ipairs(taken) do
            if #(vector3(s.x, s.y, s.z) - c) < 3.0 then free = false break end
        end
        if free then return s end
    end
    return nil
end

local function spawnReadyUnits(order)
    local spec = Config.CatalogModel(order.model); if not spec then return 0 end
    local spawned = 0
    for _ = 1, order.remaining do
        local spot = freePortSpot()
        if not spot then break end   -- no room; remaining stay queued, spawn after some are loaded
        local net = SLV.spawnNeutral(order.model, spec.category, spot, { dealer = order.dealer_id, model = order.model, orderId = order.id })
        if net then
            portUnits[net] = { orderId = order.id, dealerId = order.dealer_id, model = order.model, category = spec.category, state = 'port' }
            spawned = spawned + 1
        end
    end
    return spawned
end

local function notifyDealerStaff(dealerId, kind, msg)
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local aff = SLV.dealAffiliationOf(SLV.charId(pid))
        if aff and aff.dealerId == dealerId then SLV.notify(pid, kind, msg) end
    end
end

-- ── order ───────────────────────────────────────────────────────────────────────────
M['import:order'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not SLV.near(src, dealer.points.gestion, 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = SLV.dealAffiliationOf(SLV.charId(src))
    if not aff or aff.dealerId ~= dealer.id then return { ok = false, reason = 'NOT_STAFF' } end
    -- perm check
    local me = SLV.char(src)
    if aff.role ~= 'owner' then
        local g = aff.gradeId and SLV.single('SELECT perms FROM dealership_grades WHERE id = ?', { aff.gradeId })
        local set = {}; for _, k in ipairs((g and SLV.decode(g.perms)) or {}) do set[k] = true end
        if not set['import'] then return { ok = false, reason = 'NO_PERM' } end
    end
    if not (SLV.single('SELECT owner_charid FROM dealerships WHERE id = ?', { dealer.id }) or {}).owner_charid then
        return { ok = false, reason = 'CLOSED' }
    end

    -- parse lines
    local cat = {}; for _, c in ipairs(dealer.categories) do cat[c] = true end
    local lines, total, units = {}, 0, 0
    for _, l in ipairs(p and p.orders or {}) do
        local model = type(l) == 'table' and tostring(l.model) or nil
        local qty = math.floor(tonumber(l and l.qty) or 0)
        local spec = model and Config.CatalogModel(model)
        if spec and cat[spec.category] and qty > 0 and qty <= 10 then
            lines[#lines + 1] = { model = model, qty = qty, price = spec.price }
            total = total + spec.price * qty
            units = units + qty
        end
    end
    if #lines == 0 then return { ok = false, reason = 'EMPTY' } end
    if units > 12 then return { ok = false, reason = 'TOO_MANY' } end
    local priority = p and p.priority and true or false
    if priority then total = total + Config.Import.priorityFee end

    -- pay from the till (race-safe)
    local a = SLV.update('UPDATE dealerships SET till = till - ? WHERE id = ? AND till >= ?', { total, dealer.id, total })
    if a ~= 1 then return { ok = false, reason = 'TILL' } end

    local delay = priority and Config.Import.priorityDelay or Config.Import.normalDelay
    local readyAt = os.time() + delay
    -- if any insert fails after the till was debited, refund the till (no money lost without an order)
    local okIns = pcall(function()
        for _, l in ipairs(lines) do
            SLV.insert([[INSERT INTO dealership_orders (dealer_id, model, qty, remaining, ready_at, priority, status)
                         VALUES (?,?,?,?,?,?, 'pending')]],
                { dealer.id, l.model, l.qty, l.qty, readyAt, priority and 1 or 0 })
        end
    end)
    if not okIns then
        SLV.update('UPDATE dealerships SET till = till + ? WHERE id = ?', { total, dealer.id })
        return { ok = false, reason = 'ERROR' }
    end
    notifyDealerStaff(dealer.id, 'inform', ('Commande d\'import passée (%d véhicule(s)). Prête dans %d min au port.'):format(units, math.ceil(delay / 60)))
    return { ok = true, orders = SLV.ordersFor(dealer.id), till = SLV.dealTill(dealer.id), total = total }
end

-- ── ready poller ──────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        local due = SLV.query([[SELECT id, dealer_id, model, qty, remaining, ready_at FROM dealership_orders
                                WHERE status = 'pending' AND ready_at <= ?]], { now }) or {}
        for _, order in ipairs(due) do
            SLV.update("UPDATE dealership_orders SET status = 'ready' WHERE id = ?", { order.id })
            spawnReadyUnits(order)
            notifyDealerStaff(order.dealer_id, 'success',
                ('Import prêt au port : %s ×%d. Allez le récupérer.'):format((Config.CatalogModel(order.model) or {}).label or order.model, order.remaining))
        end
        -- top-up: spawn queued units of 'ready' orders if port spots freed
        local ready = SLV.query([[SELECT id, dealer_id, model, remaining FROM dealership_orders WHERE status = 'ready' AND remaining > 0]], {}) or {}
        for _, order in ipairs(ready) do
            local present = 0
            for _, u in pairs(portUnits) do if u.orderId == order.id and u.state ~= 'delivered' then present = present + 1 end end
            if present < order.remaining then spawnReadyUnits({ id = order.id, dealer_id = order.dealer_id, model = order.model, remaining = order.remaining - present }) end
        end
    end
end)

-- ── transport ──────────────────────────────────────────────────────────────────────
M['convoy:transport'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    local aff = SLV.dealAffiliationOf(SLV.charId(src)); if not aff or aff.dealerId ~= dealer.id then return { ok = false, reason = 'NOT_STAFF' } end
    -- the truck appears AT THE DEALERSHIP; the employee drives it to the port, loads, comes back.
    local spawn = dealer.transportSpawn or Config.Import.transport.spawn
    if not SLV.near(src, spawn, 30.0) then return { ok = false, reason = 'TOO_FAR' } end
    local ready = readyUnits(dealer.id)
    if ready < 1 then return { ok = false, reason = 'NOTHING' } end
    -- the employee CHOOSES: flatbed (1 véhicule/trajet, défaut) or the hauler+carrier (plusieurs).
    local kind = (p and p.kind == 'carrier') and 'carrier' or 'flatbed'
    if kind == 'flatbed' then
        local net = SLV.spawnNeutral(Config.Import.transport.single.model, 'utility', spawn, { transport = true })
        return { ok = true, kind = 'flatbed', transport = net, slots = 1 }
    else
        local haulerNet = SLV.spawnNeutral(Config.Import.transport.hauler, 'utility', spawn, { transport = true })
        local trailerNet = SLV.spawnNeutral(Config.Import.transport.multi.model, 'trailer', { x = spawn.x, y = spawn.y - 8.0, z = spawn.z, w = spawn.w }, { transport = true })
        return { ok = true, kind = 'carrier', hauler = haulerNet, trailer = trailerNet, slots = Config.Import.transport.multi.slots }
    end
end

-- ── load (claim a port unit onto the trailer) ───────────────────────────────────────
M['convoy:load'] = function(src, p)
    local vehNet = p and p.vehNet
    local trailerNet = p and p.trailerNet
    local unit = vehNet and portUnits[vehNet]
    if not unit or unit.state ~= 'port' then return { ok = false, reason = 'NOT_LOADABLE' } end
    local aff = SLV.dealAffiliationOf(SLV.charId(src)); if not aff or aff.dealerId ~= unit.dealerId then return { ok = false, reason = 'NOT_STAFF' } end
    local veh = SLV.entityFromNet(vehNet); if not veh then return { ok = false, reason = 'GONE' } end
    if not SLV.near(src, GetEntityCoords(veh), Config.Import.loadReach) then return { ok = false, reason = 'TOO_FAR' } end
    -- assign a free slot index on this trailer
    local used = {}
    for _, u in pairs(portUnits) do if u.state == 'loaded' and u.trailer == trailerNet then used[u.slot] = true end end
    local slots = (trailerNet == p.flatbedNet) and 1 or #Config.Import.carrierOffsets
    local maxSlots = p.kind == 'flatbed' and 1 or #Config.Import.carrierOffsets
    local slot
    for i = 1, maxSlots do if not used[i] then slot = i break end end
    if not slot then return { ok = false, reason = 'TRAILER_FULL' } end
    unit.state = 'loaded'; unit.by = src; unit.trailer = trailerNet; unit.slot = slot
    local offset = (p.kind == 'flatbed') and Config.Import.flatbedOffset or Config.Import.carrierOffsets[slot]
    return { ok = true, slot = slot, offset = { x = offset.x, y = offset.y, z = offset.z } }
end

-- ── unload (commit a loaded unit into dealership stock at the delivery bay) ──────────
M['convoy:unload'] = function(src, p)
    local vehNet = p and p.vehNet
    local unit = vehNet and portUnits[vehNet]
    if not unit or unit.state ~= 'loaded' or unit.by ~= src then return { ok = false, reason = 'NOT_UNLOADABLE' } end
    local dealer = Config.Dealership(unit.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not SLV.near(src, dealer.delivery, dealer.deliveryReach or 6.0) then return { ok = false, reason = 'NOT_AT_BAY' } end
    -- add one unit to stock (keep existing price/display)
    SLV.update([[INSERT INTO dealership_stock (dealer_id, model, qty, price) VALUES (?,?,1,?)
                 ON DUPLICATE KEY UPDATE qty = qty + 1]], { unit.dealerId, unit.model, Config.DefaultRetail(unit.model) })
    -- decrement the order's remaining; close it when done
    SLV.update('UPDATE dealership_orders SET remaining = GREATEST(0, remaining - 1) WHERE id = ?', { unit.orderId })
    local rem = tonumber(SLV.scalar('SELECT remaining FROM dealership_orders WHERE id = ?', { unit.orderId })) or 0
    if rem <= 0 then SLV.update("UPDATE dealership_orders SET status = 'delivered' WHERE id = ?", { unit.orderId }) end
    -- remove the physical unit
    local veh = SLV.entityFromNet(vehNet)
    if veh then DeleteEntity(veh) end
    unit.state = 'delivered'
    portUnits[vehNet] = nil
    return { ok = true, model = unit.model, label = (Config.CatalogModel(unit.model) or {}).label or unit.model }
end

-- a client can ask which nearby entities are loadable port units (for target filtering)
function SLV.isPortUnit(netId) local u = portUnits[netId]; return u and u.state == 'port' end
function SLV.isLoadedUnit(netId, src) local u = portUnits[netId]; return u and u.state == 'loaded' and u.by == src end

Config.Log('info', 'convoy ready')
