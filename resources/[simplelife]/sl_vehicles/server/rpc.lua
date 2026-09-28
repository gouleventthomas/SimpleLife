--[[
    server/rpc.lua — the single 'sl_vehicles:rpc' callback dispatcher (RATE-limited + single-flight
    LOCK for money/stock methods) PLUS the phone "Véhicules/Clés" methods, garage park, trunk,
    transfer, and the client->server net events (undock / state sync / destroyed / garage presence).
]]

SLV.methods = SLV.methods or {}
local M = SLV.methods

-- ── phone "Véhicules / Clés" app ────────────────────────────────────────────────────
M['phone:vehicles'] = function(src, _)
    local charId = SLV.charId(src); if not charId then return { ok = false, reason = 'NO_CHAR' } end
    return { ok = true, vehicles = SLV.accessibleList(charId) }
end

M['key:lock']   = function(src, p) return SLV.remoteLock(src, tonumber(p and p.dbId), p and p.locked and true or false) end
M['key:engine'] = function(src, p) return SLV.remoteEngine(src, tonumber(p and p.dbId), p and p.on and true or false) end
M['key:locate'] = function(src, p) return SLV.locate(src, tonumber(p and p.dbId)) end

M['key:holders'] = function(src, p)
    local dbId = tonumber(p and p.dbId); if not dbId then return { ok = false, reason = 'BAD' } end
    if tonumber(SLV.ownerOf(dbId)) ~= tonumber(SLV.charId(src)) then return { ok = false, reason = 'NOT_OWNER' } end
    return { ok = true, holders = SLV.keyHolders(dbId) }
end

-- share to the nearest player (owner only)
M['key:share'] = function(src, p)
    local dbId = tonumber(p and p.dbId); if not dbId then return { ok = false, reason = 'BAD' } end
    local sc, target, best = GetEntityCoords(GetPlayerPed(src)), nil, 3.0
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if pid ~= src then
            local d = #(GetEntityCoords(GetPlayerPed(pid)) - sc)
            if d < best then best = d; target = pid end
        end
    end
    if not target then return { ok = false, reason = 'NO_TARGET' } end
    local res = SLV.grantKeyToSource(src, dbId, target)
    if res.ok then res.holders = SLV.keyHolders(dbId) end
    return res
end

M['key:revoke'] = function(src, p)
    local dbId = tonumber(p and p.dbId); local charid = tonumber(p and p.charid)
    if not dbId or not charid then return { ok = false, reason = 'BAD' } end
    local res = SLV.revokeKey(src, dbId, charid)
    if res.ok then res.holders = SLV.keyHolders(dbId) end
    return res
end

-- trunk: validate access, return the stash id + weight cap for the client to open via sl_inventory
M['trunk:open'] = function(src, p)
    local dbId = tonumber(p and p.dbId); if not dbId then return { ok = false, reason = 'BAD' } end
    local netId = SLV.netOfDb(dbId)
    local veh = netId and SLV.entityFromNet(netId)
    if not veh then return { ok = false, reason = 'NOT_OUT' } end
    if not SLV.near(src, GetEntityCoords(veh), 4.0) then return { ok = false, reason = 'TOO_FAR' } end
    -- access: key holder, OR anyone if the car is unlocked
    local locked = Entity(veh).state['sl:locked']
    if locked ~= false and not SLV.hasKey(SLV.charId(src), dbId) then
        if locked == nil then locked = true end
        if locked then return { ok = false, reason = 'LOCKED' } end
    end
    local row = SLV.getVehicleRow(dbId)
    local cap = (Config.CatalogModel(row.model) or {}).trunk or 50000
    local label = (Config.CatalogModel(row.model) or {}).label or row.model
    TriggerClientEvent('sl_vehicles:openTrunk', src, { stash = 'veh:' .. dbId, cap = cap, label = label })
    return { ok = true, stash = 'veh:' .. dbId, cap = cap, label = label }
end

-- ── garage park (client sends a captured snapshot) ─────────────────────────────────
M['garage:park'] = function(src, p) return SLV.parkVehicle(src, p) end

-- ── fuel: refuel at a station (paid) / jerrycan (item) ──────────────────────────────
M['fuel:refuel'] = function(src, p)
    local netId = p and p.netId
    local veh = netId and SLV.entityFromNet(netId)
    if not veh then return { ok = false, reason = 'NOT_OUT' } end
    if not SLV.near(src, GetEntityCoords(veh), Config.Fuel.refuelReach + 3.0) then return { ok = false, reason = 'TOO_FAR' } end
    local cur = math.floor(tonumber(Entity(veh).state.fuel) or 100)
    local target = math.max(cur, math.min(100, math.floor(tonumber(p and p.target) or 100)))
    local add = target - cur
    if add <= 0 then return { ok = false, reason = 'FULL' } end
    local account = (p and p.account == 'bank') and 'bank' or 'cash'
    local cost = add * (Config.Fuel.pricePerUnit or 3)
    if (SLV.balance(src, account) or 0) < cost then return { ok = false, reason = 'FUNDS' } end
    if not SLV.tryDebit(src, account, cost, 'fuel_refuel') then return { ok = false, reason = 'FUNDS' } end
    Entity(veh).state:set('fuel', target, true)
    local dbId = SLV.dbIdOfNet(netId)
    if dbId then SLV.update('UPDATE vehicles SET fuel = ? WHERE id = ?', { target, dbId }) end
    return { ok = true, cost = cost, fuel = target, balances = SLV.balance(src) or { cash = 0, bank = 0 } }
end

M['fuel:jerrycan'] = function(src, p)
    if not exports.sl_inventory:hasItem(src, 'jerrycan') then return { ok = false, reason = 'NO_CAN' } end
    local netId = p and p.netId
    local veh = netId and SLV.entityFromNet(netId)
    if not veh then return { ok = false, reason = 'NOT_OUT' } end
    if not SLV.near(src, GetEntityCoords(veh), Config.Fuel.refuelReach + 2.0) then return { ok = false, reason = 'TOO_FAR' } end
    local cur = math.floor(tonumber(Entity(veh).state.fuel) or 100)
    local target = math.min(100, cur + (Config.Fuel.jerrycanRefill or 30))
    Entity(veh).state:set('fuel', target, true)
    local dbId = SLV.dbIdOfNet(netId)
    if dbId then SLV.update('UPDATE vehicles SET fuel = ? WHERE id = ?', { target, dbId }) end
    return { ok = true, fuel = target }
end

-- ── hotwire authorisation ───────────────────────────────────────────────────────────
M['hotwire'] = function(src, p) return SLV.hotwire(src, p and p.netId) end

-- ── player -> player transfer (gift / sale) ────────────────────────────────────────
local pendingXfer = {}   -- targetSrc -> { dbId, fromSrc, price, at }

M['transfer:offer'] = function(src, p)
    local dbId = tonumber(p and p.dbId); if not dbId then return { ok = false, reason = 'BAD' } end
    local char = SLV.char(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    if tonumber(SLV.ownerOf(dbId)) ~= tonumber(char.charId) then return { ok = false, reason = 'NOT_OWNER' } end
    local price = math.max(0, math.floor(tonumber(p and p.price) or 0))
    local sc, target, best = GetEntityCoords(GetPlayerPed(src)), nil, 4.0
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if pid ~= src then
            local d = #(GetEntityCoords(GetPlayerPed(pid)) - sc)
            if d < best then best = d; target = pid end
        end
    end
    if not target then return { ok = false, reason = 'NO_TARGET' } end
    local tchar = SLV.char(target); if not tchar then return { ok = false, reason = 'NO_TARGET' } end
    if SLV.countOwned(tchar.charId) >= Config.Limits.maxOwned then return { ok = false, reason = 'TARGET_FULL' } end
    local row = SLV.getVehicleRow(dbId)
    pendingXfer[target] = { dbId = dbId, fromSrc = src, price = price, at = GetGameTimer() }
    TriggerClientEvent('sl_vehicles:transferOffer', target, {
        from = char.firstname .. ' ' .. char.lastname, price = price,
        label = (Config.CatalogModel(row.model) or {}).label or row.model, plate = row.plate,
    })
    return { ok = true, name = tchar.firstname .. ' ' .. tchar.lastname }
end

M['transfer:respond'] = function(src, p)
    local x = pendingXfer[src]; if not x then return { ok = false, reason = 'NO_OFFER' } end
    pendingXfer[src] = nil
    if GetGameTimer() - x.at > 30000 then return { ok = false, reason = 'EXPIRED' } end
    if not (p and p.accept) then
        SLV.notify(x.fromSrc, 'inform', 'Transfert refusé.')
        return { ok = true, accepted = false }
    end
    local fromChar = SLV.char(x.fromSrc); local toChar = SLV.char(src)
    if not fromChar or not toChar then return { ok = false, reason = 'GONE' } end
    if tonumber(SLV.ownerOf(x.dbId)) ~= tonumber(fromChar.charId) then return { ok = false, reason = 'GONE' } end
    if SLV.countOwned(toChar.charId) >= Config.Limits.maxOwned then return { ok = false, reason = 'MAX_OWNED' } end
    if x.price > 0 then
        if (SLV.balance(src, 'bank') or 0) < x.price then return { ok = false, reason = 'FUNDS' } end
        if not exports.sl_core:economyTransfer(src, x.fromSrc, 'bank', x.price, 'vehicle_sale') then return { ok = false, reason = 'FUNDS' } end
    end
    SLV.transferOwner(x.dbId, toChar.charId)
    SLV.refreshKeysState(x.dbId)
    -- if the live vehicle's owner tag must update:
    local netId = SLV.netOfDb(x.dbId)
    if netId then
        local veh = SLV.entityFromNet(netId)
        if veh then
            local vd = Entity(veh).state['sl:veh']
            if type(vd) == 'table' then vd.owner = tonumber(toChar.charId); vd.keys = SLV.keysSet(x.dbId); Entity(veh).state:set('sl:veh', vd, true) end
        end
    end
    SLV.notify(x.fromSrc, 'success', 'Véhicule cédé.')
    SLV.notify(src, 'success', 'Véhicule reçu.')
    return { ok = true, accepted = true }
end

-- ── client gating: which dealership am I staff of? ─────────────────────────────────
lib.callback.register('sl_vehicles:myDealer', function(src) return SLV.dealerOf(src) end)

-- ── net events (no reply) ───────────────────────────────────────────────────────────
RegisterNetEvent('sl_vehicles:undock', function(netId) SLV.undock(source, netId) end)

RegisterNetEvent('sl_vehicles:syncState', function(netId, fuel, body, engine)
    local dbId = SLV.dbIdOfNet(netId); if not dbId then return end
    -- only persist for the owner / key holder to avoid bystander spam
    if not SLV.hasKey(SLV.charId(source), dbId) then return end
    SLV.updateHealth(dbId, fuel, body, engine)
end)

RegisterNetEvent('sl_vehicles:garageEnter', function(garageId) SLV.garageEnter(source, garageId) end)
RegisterNetEvent('sl_vehicles:garageExit', function(garageId) SLV.garageExit(source, garageId) end)

AddEventHandler('playerDropped', function() pendingXfer[source] = nil end)

-- ── dispatcher ──────────────────────────────────────────────────────────────────────
local RATE = {
    ['vente:bill'] = true, ['bill:pay'] = true, ['vente:resell'] = true,
    ['manage:setPrice'] = true, ['manage:withdraw'] = true, ['manage:deposit'] = true, ['expo:set'] = true,
    ['grades:create'] = true, ['grades:update'] = true, ['grades:delete'] = true,
    ['employees:recruit'] = true, ['employees:setGrade'] = true, ['employees:fire'] = true,
    ['import:order'] = true, ['convoy:transport'] = true, ['convoy:load'] = true, ['convoy:unload'] = true,
    ['key:share'] = true, ['key:revoke'] = true, ['hotwire'] = true,
    ['impound:retrieve'] = true, ['transfer:offer'] = true, ['transfer:respond'] = true,
    ['phone:contact'] = true, ['leads:call'] = true, ['leads:handle'] = true,
    ['fuel:refuel'] = true, ['fuel:jerrycan'] = true,
}
local LOCK = {
    ['bill:pay'] = true, ['vente:resell'] = true, ['manage:withdraw'] = true, ['manage:deposit'] = true,
    ['import:order'] = true, ['convoy:unload'] = true, ['impound:retrieve'] = true, ['transfer:respond'] = true,
}
local lastCall = {}
local RPC_INTERVAL = 350

lib.callback.register('sl_vehicles:rpc', function(src, payload)
    local method = payload and payload.method
    local fn = method and M[method]
    if not fn then return { ok = false, reason = 'BAD_METHOD' } end
    if RATE[method] then
        local key, now = src .. ':' .. method, GetGameTimer()
        if lastCall[key] and (now - lastCall[key]) < RPC_INTERVAL then return { ok = false, reason = 'RATE' } end
        lastCall[key] = now
    end
    if LOCK[method] then
        return SLV.withLock(src, function() return fn(src, payload.params or {}) end)
    end
    local ok, res = pcall(fn, src, payload.params or {})
    if not ok then Config.Log('error', ('rpc %s error: %s'):format(method, tostring(res))); return { ok = false, reason = 'ERROR' } end
    return res
end)

AddEventHandler('playerDropped', function()
    local src = source
    for k in pairs(lastCall) do if k:sub(1, #tostring(src) + 1) == (src .. ':') then lastCall[k] = nil end end
end)

Config.Log('info', 'rpc ready')
