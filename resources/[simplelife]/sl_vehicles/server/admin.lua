--[[
    server/admin.lua — exports called by the sl_admin F10 menu (admin-gated there) plus an
    ace-gated callback so the client menu can list dealerships/catalog. Dev tooling: assign a
    dealership owner, top up its till/stock, give a test vehicle, send a player's cars to impound.
]]

-- Exports are not ACE-gated by FiveM. These dev tools must only be reachable from the admin menu
-- (sl_admin, which re-checks the ace on every action) or from within this resource — never from an
-- arbitrary third-party resource. GetInvokingResource() is nil for internal calls.
local function adminCaller()
    local inv = GetInvokingResource()
    return inv == nil or inv == GetCurrentResourceName() or inv == 'sl_admin'
end

local function ownableDealers()
    local out = {}
    for _, d in ipairs(Config.Dealerships) do
        local owner = SLV.scalar('SELECT owner_charid FROM dealerships WHERE id = ?', { d.id })
        out[#out + 1] = { id = d.id, label = d.label, owner = owner }
    end
    return out
end

exports('getOwnableDealers', function() return ownableDealers() end)

lib.callback.register('sl_vehicles:adminListDealers', function(src)
    if not IsPlayerAceAllowed(src, 'sl.admin') then return {} end
    return ownableDealers()
end)

lib.callback.register('sl_vehicles:adminCatalog', function(src)
    if not IsPlayerAceAllowed(src, 'sl.admin') then return {} end
    local out = {}
    for model, s in pairs(Config.Catalog) do
        out[#out + 1] = { model = model, label = s.label, category = s.category, price = s.price }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

exports('setDealerOwner', function(targetSrc, dealerId)
    if not adminCaller() then return false end
    local dealer = Config.Dealership(dealerId); if not dealer then return false end
    local char = SLV.char(targetSrc); if not char then return false end
    SLV.ensureDealRow(dealerId)
    SLV.seedDealerGrades(dealerId)
    -- one dealership affiliation per player: release any owned + remove as employee anywhere
    SLV.update('UPDATE dealerships SET owner_charid = NULL WHERE owner_charid = ?', { char.charId })
    SLV.update('DELETE FROM dealership_employees WHERE charid = ?', { char.charId })
    SLV.update('UPDATE dealerships SET owner_charid = ? WHERE id = ?', { char.charId, dealerId })
    local check = SLV.scalar('SELECT owner_charid FROM dealerships WHERE id = ?', { dealerId })
    if tonumber(check) ~= tonumber(char.charId) then
        Config.Log('error', ('assignation concession NON enregistrée (%s) — la table `dealerships` existe-t-elle ? redémarre sl_core (migration 013).'):format(dealerId))
        return false
    end
    TriggerClientEvent('sl_vehicles:refreshAff', targetSrc)
    Config.Log('info', ('dealership %s -> charId %s (src %s)'):format(dealerId, tostring(char.charId), tostring(targetSrc)))
    return true
end)

exports('clearDealerOwner', function(dealerId)
    if not adminCaller() then return false end
    if not Config.Dealership(dealerId) then return false end
    local owner = SLV.scalar('SELECT owner_charid FROM dealerships WHERE id = ?', { dealerId })
    SLV.update('UPDATE dealerships SET owner_charid = NULL WHERE id = ?', { dealerId })
    if owner then local s = SLV.sourceOfChar(owner); if s then TriggerClientEvent('sl_vehicles:refreshAff', s) end end
    return true
end)

exports('addDealerCash', function(dealerId, amount)
    if not adminCaller() then return false end
    if not Config.Dealership(dealerId) then return false end
    amount = math.floor(tonumber(amount) or 0)
    SLV.ensureDealRow(dealerId)
    SLV.update('UPDATE dealerships SET till = GREATEST(0, till + ?) WHERE id = ?', { amount, dealerId })
    return true
end)

exports('addDealerStock', function(dealerId, model, qty)
    if not adminCaller() then return false end
    local dealer = Config.Dealership(dealerId); if not dealer then return false end
    if not Config.CatalogModel(model) then return false end
    qty = math.floor(tonumber(qty) or 0); if qty <= 0 then return false end
    SLV.ensureDealRow(dealerId)
    SLV.update([[INSERT INTO dealership_stock (dealer_id, model, qty, price) VALUES (?,?,?,?)
                 ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)]], { dealerId, model, qty, Config.DefaultRetail(model) })
    return true
end)

exports('getPlayerDealers', function(targetSrc)
    local char = SLV.char(targetSrc); if not char then return {} end
    local out = {}
    for _, r in ipairs(SLV.query('SELECT id, till FROM dealerships WHERE owner_charid = ?', { char.charId }) or {}) do
        local d = Config.Dealership(r.id)
        out[#out + 1] = { id = r.id, label = (d and d.label) or r.id, cash = r.till or 0 }
    end
    return out
end)

-- Give a test vehicle to a player (spawns next to them). Returns plate or false.
exports('giveVehicle', function(targetSrc, model)
    if not adminCaller() then return false end
    local char = SLV.char(targetSrc); if not char then return false end
    local spec = Config.CatalogModel(model); if not spec then return false end
    if SLV.countOwned(char.charId) >= Config.Limits.maxOwned then return false end
    local ped = GetPlayerPed(targetSrc); if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local fwd = math.rad(h)
    local pose = { x = c.x + math.sin(-fwd) * 3.0, y = c.y + math.cos(-fwd) * 3.0, z = c.z, w = h }
    local veh = SLV.createVehicle(char.charId, model, { category = spec.category, status = 'out', fuel = 100 })
    SLV.spawnOwned(veh.id, pose)
    SLV.notify(targetSrc, 'success', ('Véhicule reçu : %s (%s)'):format(spec.label, veh.plate))
    TriggerClientEvent('sl_vehicles:refreshAff', targetSrc)
    return veh.plate
end)

exports('sendPlayerImpound', function(targetSrc)
    if not adminCaller() then return false end
    local char = SLV.char(targetSrc); if not char then return false end
    local outs = SLV.query("SELECT id FROM vehicles WHERE charid = ? AND status = 'out'", { char.charId }) or {}
    for _, r in ipairs(outs) do SLV.impound(r.id) end
    SLV.notify(targetSrc, 'inform', 'Vos véhicules dehors ont été envoyés à la fourrière.')
    return true
end)

-- ── startup sanity: the vehicle tables come from sl_core migrations 012/013/014 ──────
CreateThread(function()
    Wait(3000)
    local ok, n = pcall(function() return SLV.scalar('SELECT COUNT(*) FROM vehicles') end)
    if not ok or n == nil then
        Config.Log('error', 'Table `vehicles` INTROUVABLE — redémarre sl_core pour appliquer les migrations 012/013/014.')
    else
        Config.Log('info', ('base prête — %d véhicule(s) enregistré(s)'):format(tonumber(n) or 0))
    end
end)

Config.Log('info', 'admin ready')
