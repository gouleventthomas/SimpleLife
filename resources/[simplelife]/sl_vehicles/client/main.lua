--[[
    client/main.lua — NUI bridge (catalogue/gestion/bill) + blips + server events + the owned-vehicle
    monitor (undock parked->out, periodic state sync, destroyed -> impound). In-world actions that
    don't need the React surface (garage park, fuel, impound, transfer, keys) use ox_lib dialogs.
]]

VehClient = { open = false, myDealer = nil }

local function notify(kind, msg, title)
    lib.notify({ title = title or 'Véhicules', description = msg, type = kind or 'inform' })
end
VehClient.notify = notify

function VehClient.rpc(method, params)
    return lib.callback.await('sl_vehicles:rpc', false, { method = method, params = params or {} })
end

-- open a NUI screen from a server result
local function openWith(method, params, action)
    if VehClient.open then return end
    local res = VehClient.rpc(method, params)
    if not res or not res.ok then notify('error', VehClient.reason(res and res.reason)); return end
    VehClient.open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = action, data = res })
end
VehClient.openWith = openWith

function VehClient.close()
    VehClient.open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- human-readable RPC failure reasons
local REASONS = {
    TOO_FAR = 'Trop loin.', NOT_STAFF = "Vous n'êtes pas employé ici.", NO_PERM = 'Permission insuffisante.',
    STOCK = 'Plus de stock.', FUNDS = 'Fonds insuffisants.', TILL = 'Caisse insuffisante.',
    MAX_OWNED = 'Vous avez atteint votre nombre maximum de véhicules.', NO_CUSTOMER = 'Aucun client à proximité.',
    NO_TARGET = 'Personne à proximité.', CLOSED = 'Concession sans propriétaire.', MARGIN = 'Prix hors de la marge autorisée.',
    EXPO_FULL = "Plus de place d'exposition.", NOTHING = 'Aucun véhicule prêt au port.', TRAILER_FULL = 'Remorque pleine.',
    NOT_AT_BAY = 'Allez à la zone de livraison.', LOCKED = 'Véhicule verrouillé.', NO_KEY = "Vous n'avez pas la clé.",
    NOT_OUT = "Le véhicule n'est pas sorti.", ALREADY = 'Déjà affilié à une société.', RATE = 'Trop rapide.',
    MAX = 'Limite atteinte.', EMPTY = 'Vide.', AMOUNT = 'Montant invalide.', NO_NUMBER = 'Pas de numéro.',
}
function VehClient.reason(r) return REASONS[r] or 'Action impossible.' end

-- ── NUI callbacks (React -> client -> server) ───────────────────────────────────────
RegisterNUICallback('rpc', function(data, cb)
    local res = VehClient.rpc(data.method, data.params or {})
    cb(res or { ok = false })
end)
RegisterNUICallback('close', function(_, cb) VehClient.close(); cb(1) end)

-- ── affiliation cache (which dealership am I staff of) ───────────────────────────────
local function refreshDealer()
    VehClient.myDealer = lib.callback.await('sl_vehicles:myDealer', false)
end
RegisterNetEvent('sl_vehicles:refreshAff', function() refreshDealer() end)

-- ── customer bill (employee billed me) ──────────────────────────────────────────────
RegisterNetEvent('sl_vehicles:bill', function(data)
    VehClient.open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'bill', data = data })
end)
RegisterNetEvent('sl_vehicles:billClosed', function()
    if VehClient.open then VehClient.close() end
end)
RegisterNetEvent('sl_vehicles:posResult', function(res)
    SendNUIMessage({ action = 'posResult', data = res })
    if res.ok then notify('success', ('Vente conclue (+$%d commission).'):format(res.commission or 0))
    elseif res.reason == 'SUPERSEDED' then -- silent
    elseif res.reason == 'DECLINED' then notify('warning', 'Le client a refusé.')
    elseif res.reason == 'EXPIRED' then notify('warning', 'Facture expirée.') end
end)

-- ── transfer offer ──────────────────────────────────────────────────────────────────
RegisterNetEvent('sl_vehicles:transferOffer', function(data)
    local priceTxt = (data.price and data.price > 0) and (' pour $' .. data.price) or ' (gratuit)'
    local accepted = lib.alertDialog({
        header = 'Cession de véhicule',
        content = ('%s vous propose **%s** (%s)%s.\n\nAccepter ?'):format(data.from, data.label, data.plate, priceTxt),
        centered = true, cancel = true,
    })
    local res = VehClient.rpc('transfer:respond', { accept = accepted == 'confirm' })
    if accepted == 'confirm' then
        if res and res.ok and res.accepted then notify('success', 'Véhicule reçu.')
        else notify('error', VehClient.reason(res and res.reason)) end
    end
end)

-- ── theft alert (your car is being hotwired) ────────────────────────────────────────
RegisterNetEvent('sl_vehicles:theftAlert', function(data)
    notify('error', ('⚠ Tentative de vol sur votre véhicule (%s) !'):format(data.plate or '?'))
    if data.coords then
        SetNewWaypoint(data.coords.x, data.coords.y)
    end
end)

-- ── phone-driven helpers (waypoint / trunk) ─────────────────────────────────────────
RegisterNetEvent('sl_vehicles:setWaypoint', function(c)
    if c and c.x then SetNewWaypoint(c.x + 0.0, c.y + 0.0); notify('inform', 'Position du véhicule marquée sur le GPS.') end
end)

-- Open the vehicle trunk via the sl_inventory stash API (graceful if not yet available).
RegisterNetEvent('sl_vehicles:openTrunk', function(data)
    if not data or not data.stash then return end
    local ok = pcall(function()
        if exports.sl_inventory and exports.sl_inventory.openStash then
            exports.sl_inventory:openStash(data.stash, data.label or 'Coffre', data.cap or 50000)
            return true
        end
        error('no stash api')
    end)
    if not ok then notify('warning', 'Coffre indisponible (module à venir).') end
end)

-- ── blips ───────────────────────────────────────────────────────────────────────────
local function makeBlip(b, name)
    if not b or not b.coords then return end
    local blip = AddBlipForCoord(b.coords.x, b.coords.y, b.coords.z)
    SetBlipSprite(blip, b.sprite or 326)
    SetBlipColour(blip, b.color or 0)
    SetBlipScale(blip, b.scale or 0.8)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(name); EndTextCommandSetBlipName(blip)
end

CreateThread(function()
    while GetResourceState('sl_core') ~= 'started' do Wait(200) end
    while not exports.sl_core:isReady() do Wait(200) end
    for _, d in ipairs(Config.Dealerships) do makeBlip(d.blip, d.label) end
    for _, g in ipairs(Config.Garages) do makeBlip(g.blip, g.label) end
    for _, l in ipairs(Config.Impound.lots) do makeBlip(l.blip, l.label) end
    refreshDealer()
end)
RegisterNetEvent('sl_core:client:charLoaded', function() refreshDealer() end)  -- if sl_core emits one; harmless otherwise

-- ── owned-vehicle monitor (undock / sync / destroyed) ───────────────────────────────
local syncedAt = {}     -- netId -> last sync gameTimer
local undocked = {}     -- netId -> true (sent undock this session)
local deadSent = {}     -- netId -> true

local function myCharId()
    local c = LocalPlayer.state['sl:char']
    return c and c.charId or nil
end

function VehClient.hasKey(veh)
    local vd = Entity(veh).state['sl:veh']
    if type(vd) ~= 'table' then return true end   -- not an owned vehicle => free to drive
    local me = myCharId()
    if not me then return false end
    if tonumber(vd.owner) == tonumber(me) then return true end
    return vd.keys and (vd.keys[tostring(me)] == true) or false
end

CreateThread(function()
    while true do
        Wait(2000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local vd = Entity(veh).state['sl:veh']
            if type(vd) == 'table' and vd.id then
                local netId = VehToNet(veh)
                -- undock (parked -> out) once, when I have a key and start driving it
                if not undocked[netId] and VehClient.hasKey(veh) then
                    undocked[netId] = true
                    TriggerServerEvent('sl_vehicles:undock', netId)
                end
                -- periodic state sync (fuel/body/engine) — owner/key holder only
                local now = GetGameTimer()
                if VehClient.hasKey(veh) and (not syncedAt[netId] or now - syncedAt[netId] > 20000) then
                    syncedAt[netId] = now
                    local fuel = Entity(veh).state.fuel or 100
                    TriggerServerEvent('sl_vehicles:syncState', netId,
                        math.floor(fuel + 0.5), math.floor(GetVehicleBodyHealth(veh)), math.floor(GetVehicleEngineHealth(veh)))
                end
            end
        end
        -- wreck detection (any owned vehicle I'm near that just died)
        if veh ~= 0 then
            local vd = Entity(veh).state['sl:veh']
            if type(vd) == 'table' and vd.id and not deadSent[VehToNet(veh)] then
                if IsEntityDead(veh) or GetVehicleEngineHealth(veh) <= -3000.0 then
                    deadSent[VehToNet(veh)] = true
                    TriggerServerEvent('sl_vehicles:destroyed', VehToNet(veh))
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and VehClient.open then SetNuiFocus(false, false) end
end)

Config.Log('info', 'client main ready')
