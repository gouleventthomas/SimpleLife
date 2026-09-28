--[[
    server/main.lua — sl_admin authority.

    SECURITY: every action re-checks the `sl.admin` ace on the SERVER. The client menu only
    OPENS for admins (UX), but that is not the security boundary — a crafted net event from a
    non-admin is rejected + logged here. Money is applied authoritatively through sl_core; the
    client-effect actions (weapons, heal, vehicle spawn, teleports) are admin-gated here and
    then dispatched to the relevant client.
]]

local ACE = 'sl.admin'

local function isAdmin(src) return src and src ~= 0 and IsPlayerAceAllowed(src, ACE) end

-- Gate + log. Returns true if allowed.
local function guard(src, what)
    if isAdmin(src) then return true end
    Config.Log('warn', ('REJECT non-admin src=%s tried %s'):format(tostring(src), tostring(what)))
    return false
end

local MAX_MONEY = 100000000

-- ── am I admin? (drives whether the client even opens the menu) ────────────────
lib.callback.register('sl_admin:amIAdmin', function(src)
    return isAdmin(src) and true or false
end)

-- ── online players (id + name), admin only ────────────────────────────────────
lib.callback.register('sl_admin:getPlayers', function(src)
    if not isAdmin(src) then return {} end
    local out = {}
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local char = exports.sl_core:getChar(pid)
        local name = char and (char.firstname .. ' ' .. char.lastname) or GetPlayerName(pid) or ('Joueur ' .. pid)
        out[#out + 1] = { id = pid, name = name, self = (pid == src) }
    end
    return out
end)

-- ── money (AUTHORITATIVE via sl_core) ─────────────────────────────────────────
RegisterNetEvent('sl_admin:money', function(account, amount)
    local src = source
    if not guard(src, 'money') then return end
    account = (account == 'bank') and 'bank' or 'cash'
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 or math.abs(amount) > MAX_MONEY then return end
    local ok
    if amount > 0 then
        ok = exports.sl_core:addMoney(src, account, amount, 'admin:give')
    else
        ok = exports.sl_core:removeMoney(src, account, -amount, 'admin:remove')
    end
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and (('%s %s$%d'):format(amount > 0 and 'Reçu' or 'Retiré', '', math.abs(amount))) or 'Échec (fonds ?)')
end)

-- ── weapons (admin-gated, applied client-side) ────────────────────────────────
RegisterNetEvent('sl_admin:weapon', function(weapon)
    local src = source
    if not guard(src, 'weapon') then return end
    if type(weapon) ~= 'string' then return end
    TriggerClientEvent('sl_admin:client:giveWeapon', src, weapon)
end)

RegisterNetEvent('sl_admin:removeWeapons', function()
    local src = source
    if not guard(src, 'removeWeapons') then return end
    TriggerClientEvent('sl_admin:client:removeWeapons', src)
end)

-- ── items (admin-gated, via sl_inventory exports) ─────────────────────────────
local function invReady() return GetResourceState('sl_inventory') == 'started' end

RegisterNetEvent('sl_admin:giveItem', function(name, count)
    local src = source
    if not guard(src, 'giveItem') then return end
    if type(name) ~= 'string' or not invReady() then return end
    count = math.floor(tonumber(count) or 1); if count <= 0 then count = 1 end
    local ok = exports.sl_inventory:addItem(src, name, count)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and ('Reçu %dx %s'):format(count, name) or 'Échec (item inconnu / trop lourd)')
end)

RegisterNetEvent('sl_admin:giveItemTo', function(targetId, name, count)
    local src = source
    if not guard(src, 'giveItemTo') then return end
    targetId = tonumber(targetId)
    if not targetId or type(name) ~= 'string' or not invReady() then return end
    count = math.floor(tonumber(count) or 1); if count <= 0 then count = 1 end
    local ok = exports.sl_inventory:addItem(targetId, name, count)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and ('Donné %dx %s à #%d'):format(count, name, targetId) or 'Échec (joueur ? trop lourd ?)')
    if ok then TriggerClientEvent('sl_admin:notify', targetId, 'success', ('Reçu %dx %s (staff)'):format(count, name)) end
end)

-- ── vehicle spawn / actions (admin-gated, client-side) ────────────────────────
RegisterNetEvent('sl_admin:vehicle', function(model)
    local src = source
    if not guard(src, 'vehicle') then return end
    if type(model) ~= 'string' then return end
    TriggerClientEvent('sl_admin:client:spawnVehicle', src, model)
end)

RegisterNetEvent('sl_admin:vehAction', function(act)
    local src = source
    if not guard(src, 'vehAction') then return end
    TriggerClientEvent('sl_admin:client:vehAction', src, act)
end)

-- ── self actions: heal / armor / godmode (client-side) ────────────────────────
RegisterNetEvent('sl_admin:self', function(act)
    local src = source
    if not guard(src, 'self') then return end
    TriggerClientEvent('sl_admin:client:self', src, act)
end)

-- ── teleports (server reads the authoritative coords, then dispatches) ─────────
RegisterNetEvent('sl_admin:goto', function(targetId)
    local src = source
    if not guard(src, 'goto') then return end
    targetId = tonumber(targetId)
    local tped = targetId and GetPlayerPed(targetId)
    if not tped or tped == 0 then return end
    local c = GetEntityCoords(tped)
    TriggerClientEvent('sl_admin:client:teleport', src, { x = c.x, y = c.y, z = c.z })
end)

RegisterNetEvent('sl_admin:bring', function(targetId)
    local src = source
    if not guard(src, 'bring') then return end
    targetId = tonumber(targetId)
    if not targetId or targetId == src then return end
    local mc = GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('sl_admin:client:teleport', targetId, { x = mc.x, y = mc.y, z = mc.z })
    TriggerClientEvent('sl_admin:notify', src, 'success', 'Joueur ramené.')
end)

-- ── dev / test tools (admin-gated) ────────────────────────────────────────────
RegisterNetEvent('sl_admin:giveCrypto', function(coin, amount)
    local src = source
    if not guard(src, 'giveCrypto') then return end
    if type(coin) ~= 'string' or GetResourceState('sl_phone') ~= 'started' then return end
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    local ok = exports.sl_phone:addCrypto(src, coin, amount)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and ('Reçu %s %s'):format(tostring(amount), coin) or 'Échec (coin inconnu / pas de téléphone)')
end)

RegisterNetEvent('sl_admin:clearInv', function()
    local src = source
    if not guard(src, 'clearInv') then return end
    if GetResourceState('sl_inventory') ~= 'started' then return end
    local ok = exports.sl_inventory:clearInventory(src)
    TriggerClientEvent('sl_admin:notify', src, ok and 'info' or 'error', ok and 'Inventaire vidé.' or 'Échec.')
end)

-- ── shops admin (via sl_shops exports; all admin-gated) ───────────────────────
local function shopsReady() return GetResourceState('sl_shops') == 'started' end

RegisterNetEvent('sl_admin:shopAssign', function(targetId, shopId)
    local src = source
    if not guard(src, 'shopAssign') then return end
    targetId = tonumber(targetId)
    if not targetId or type(shopId) ~= 'string' or not shopsReady() then return end
    local ok = exports.sl_shops:setShopOwner(targetId, shopId)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and ('Boutique %s → joueur #%d'):format(shopId, targetId) or 'Échec (LTD / joueur invalide)')
    if ok then TriggerClientEvent('sl_admin:notify', targetId, 'success', 'Vous gérez désormais une boutique (staff).') end
end)

RegisterNetEvent('sl_admin:shopClearOwner', function(shopId)
    local src = source
    if not guard(src, 'shopClearOwner') then return end
    if type(shopId) ~= 'string' or not shopsReady() then return end
    local ok = exports.sl_shops:clearShopOwner(shopId)
    TriggerClientEvent('sl_admin:notify', src, ok and 'info' or 'error', ok and 'Propriétaire retiré.' or 'Échec.')
end)

RegisterNetEvent('sl_admin:shopCash', function(shopId, amount)
    local src = source
    if not guard(src, 'shopCash') then return end
    amount = math.floor(tonumber(amount) or 0)
    if type(shopId) ~= 'string' or amount == 0 or math.abs(amount) > MAX_MONEY or not shopsReady() then return end
    local ok = exports.sl_shops:addShopCash(shopId, amount)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and ('Caisse %s %+d$'):format(shopId, amount) or 'Échec.')
end)

RegisterNetEvent('sl_admin:shopStock', function(shopId, qty)
    local src = source
    if not guard(src, 'shopStock') then return end
    qty = math.floor(tonumber(qty) or 0)
    if type(shopId) ~= 'string' or qty <= 0 or qty > 100000 or not shopsReady() then return end
    local ok = exports.sl_shops:addShopStock(shopId, qty)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and ('Stock +%d sur %s'):format(qty, shopId) or 'Échec.')
end)

-- ── dealerships admin (via sl_vehicles exports; all admin-gated) ───────────────
local function vehReady() return GetResourceState('sl_vehicles') == 'started' end

RegisterNetEvent('sl_admin:dealerAssign', function(targetId, dealerId)
    local src = source
    if not guard(src, 'dealerAssign') then return end
    targetId = tonumber(targetId)
    if not targetId or type(dealerId) ~= 'string' or not vehReady() then return end
    local ok = exports.sl_vehicles:setDealerOwner(targetId, dealerId)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error',
        ok and ('Concession %s → joueur #%d'):format(dealerId, targetId) or 'Échec (concession / joueur invalide)')
    if ok then TriggerClientEvent('sl_admin:notify', targetId, 'success', 'Vous gérez désormais une concession (staff).') end
end)

RegisterNetEvent('sl_admin:dealerClear', function(dealerId)
    local src = source
    if not guard(src, 'dealerClear') then return end
    if type(dealerId) ~= 'string' or not vehReady() then return end
    local ok = exports.sl_vehicles:clearDealerOwner(dealerId)
    TriggerClientEvent('sl_admin:notify', src, ok and 'info' or 'error', ok and 'Propriétaire retiré.' or 'Échec.')
end)

RegisterNetEvent('sl_admin:dealerCash', function(dealerId, amount)
    local src = source
    if not guard(src, 'dealerCash') then return end
    amount = math.floor(tonumber(amount) or 0)
    if type(dealerId) ~= 'string' or amount == 0 or math.abs(amount) > MAX_MONEY or not vehReady() then return end
    local ok = exports.sl_vehicles:addDealerCash(dealerId, amount)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error', ok and ('Caisse %s %+d$'):format(dealerId, amount) or 'Échec.')
end)

RegisterNetEvent('sl_admin:dealerStock', function(dealerId, model, qty)
    local src = source
    if not guard(src, 'dealerStock') then return end
    qty = math.floor(tonumber(qty) or 0)
    if type(dealerId) ~= 'string' or type(model) ~= 'string' or qty <= 0 or qty > 100 or not vehReady() then return end
    local ok = exports.sl_vehicles:addDealerStock(dealerId, model, qty)
    TriggerClientEvent('sl_admin:notify', src, ok and 'success' or 'error', ok and ('Stock +%d %s sur %s'):format(qty, model, dealerId) or 'Échec.')
end)

RegisterNetEvent('sl_admin:giveVehicle', function(model)
    local src = source
    if not guard(src, 'giveVehicle') then return end
    if type(model) ~= 'string' or not vehReady() then return end
    local plate = exports.sl_vehicles:giveVehicle(src, model)
    TriggerClientEvent('sl_admin:notify', src, plate and 'success' or 'error',
        plate and ('Véhicule reçu (%s).'):format(plate) or 'Échec (modèle / plafond).')
end)

RegisterNetEvent('sl_admin:vehImpound', function()
    local src = source
    if not guard(src, 'vehImpound') then return end
    if not vehReady() then return end
    exports.sl_vehicles:sendPlayerImpound(src)
    TriggerClientEvent('sl_admin:notify', src, 'info', 'Véhicules dehors envoyés à la fourrière.')
end)

Config.Log('info', ('ready — admin ace "%s" enforced on every action'):format(ACE))
