--[[
    client/main.lua — sl_shops NUI bridge + open/close. Own NUI surface (web/ -> html/).
    24/7 stores open a buy screen; player LTDs open a POS (register) or a management terminal
    for staff; customers receive a bill prompt when an employee charges them.
]]

ShopClient = { myShop = nil, open = false }  -- myShop = the shop you own/work at (read by world.lua)

local REASONS = {
    NO_CHAR = 'Personnage introuvable', BAD_SHOP = 'Boutique inconnue', TOO_FAR = 'Trop loin',
    CLOSED = 'Boutique fermée', NOT_STAFF = 'Vous ne travaillez pas ici', NO_PERM = 'Permission refusée',
    NO_SHOP = 'Aucune boutique', FUNDS = 'Fonds insuffisants', OVERWEIGHT = 'Inventaire plein',
    STOCK = 'Stock insuffisant', EMPTY = 'Panier vide', AMOUNT = 'Montant invalide', PRICE = 'Prix invalide',
    TILL = 'Caisse insuffisante', RATE = 'Trop rapide', QTY = 'Quantité trop élevée',
    NO_CUSTOMER = 'Aucun client à proximité', NO_TARGET = 'Aucun joueur à proximité',
    NO_BILL = 'Facture introuvable', EXPIRED = 'Facture expirée', ALREADY = 'Déjà dans une société',
    NAME = 'Nom invalide', LIMIT = 'Limite atteinte', NO_GRADE = 'Grade introuvable', ERROR = 'Erreur serveur',
}
local function reasonMsg(r) return REASONS[r or ''] or 'Action impossible' end

local function notify(kind, msg)
    if GetResourceState('sl_ui') == 'started' then exports.sl_ui:notify(kind, msg)
    else lib.notify({ type = (kind == 'error') and 'error' or 'inform', description = msg }) end
end

local function openWith(method, params, action)
    if ShopClient.open then return end
    -- Run in a fresh thread: an ox_target sphere-zone onSelect is not a reliable coroutine context
    -- for lib.callback.await, so this guarantees the request actually runs.
    CreateThread(function()
        local res = lib.callback.await('sl_shops:rpc', false, { method = method, params = params })
        if not res or not res.ok then notify('error', res and reasonMsg(res.reason) or 'Erreur serveur'); return end
        ShopClient.open = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = action, data = res })
    end)
end

-- entry points called from client/world.lua ox_target options
function OpenShopUI(shopId)   openWith('open', { shopId = shopId }, 'shop:open') end             -- 24/7 buy
function OpenCaisse(shopId)   openWith('caisse:open', { shopId = shopId }, 'shop:caisse') end    -- LTD caisse (vendre + argent)
function OpenStock(shopId)    openWith('stock:open', { shopId = shopId }, 'shop:stock') end      -- LTD stock (items in/out)
function OpenGestion(shopId)  openWith('gestion:open', { shopId = shopId }, 'shop:gestion') end  -- LTD prix/employés/grades
function OpenWholesaleUI()    openWith('wholesale:open', {}, 'shop:wholesale') end               -- grossiste

local function closeUI()
    if not ShopClient.open then return end
    ShopClient.open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'shop:close' })
end

-- React -> server relay (buy/pos:bill/bill:pay/manage/grades/employees/wholesale:buy/...)
RegisterNUICallback('rpc', function(body, cb)
    local res = lib.callback.await('sl_shops:rpc', false, { method = body.method, params = body.params })
    cb(res or { ok = false })
end)

RegisterNUICallback('close', function(_, cb)
    closeUI()
    cb({ ok = true })
end)

-- a POS bill was sent to this player (the customer): open the confirm/pay prompt
RegisterNetEvent('sl_shops:bill', function(data)
    if ShopClient.open then
        -- busy in another shop screen: auto-refuse so the cashier isn't left hanging
        lib.callback.await('sl_shops:rpc', false, { method = 'bill:decline', params = { billId = data.billId } })
        notify('info', 'Facture reçue mais vous êtes occupé.')
        return
    end
    ShopClient.open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'shop:bill', data = data })
end)

-- a pending bill was abandoned server-side (expiry / superseded): close the customer prompt
RegisterNetEvent('sl_shops:billClosed', function()
    closeUI()
end)

-- result of a bill, echoed to the EMPLOYEE who issued it (clears the POS "billing" state)
RegisterNetEvent('sl_shops:posResult', function(data)
    if data and data.ok then notify('success', ('Vente encaissée — $%s'):format(tostring(data.total or 0)))
    else notify('warn', (data and data.reason == 'DECLINED') and 'Le client a refusé.' or 'Vente annulée.') end
    SendNUIMessage({ action = 'shop:posResult', data = data or {} })
end)

RegisterNetEvent('sl_shops:notify', function(kind, msg) notify(kind, msg) end)

-- learn which shop (if any) this player is affiliated with (owner/employee). Retried after the
-- character loads (the resource may start before we have a char), and refreshed on ownership change.
local function refreshMyShop()
    ShopClient.myShop = lib.callback.await('sl_shops:myShop', false)
end

CreateThread(function()
    while GlobalState.slCoreReady ~= true do Wait(250) end
    for _ = 1, 12 do
        Wait(1500)
        refreshMyShop()
        if ShopClient.myShop then return end   -- stop once affiliated; non-staff just rely on refresh
    end
end)

AddEventHandler('playerSpawned', refreshMyShop)
RegisterNetEvent('sl_shops:refreshOwner', refreshMyShop)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and ShopClient.open then SetNuiFocus(false, false) end
end)
