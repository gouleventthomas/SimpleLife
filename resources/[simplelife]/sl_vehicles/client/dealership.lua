--[[
    client/dealership.lua — dealership interaction zones (VENTE = staff catalogue/POS + a "resell my
    car" option for any owner; GESTION = staff terminal) and the showroom EXPO display vehicles.
]]

local function myCharId() local c = LocalPlayer.state['sl:char']; return c and c.charId or nil end
local function isOwner(veh)
    local vd = Entity(veh).state['sl:veh']
    return type(vd) == 'table' and tonumber(vd.owner) == tonumber(myCharId())
end

-- ── interaction zones ───────────────────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('sl_interact') ~= 'started' do Wait(200) end
    for _, d in ipairs(Config.Dealerships) do
        local id = d.id
        -- VENTE
        exports.sl_interact:addCoords(vector3(d.points.vente.x, d.points.vente.y, d.points.vente.z), 1.6, {
            {
                label = 'Espace vente', icon = 'fa-solid fa-car-side',
                canInteract = function() return VehClient.myDealer == id end,
                onSelect = function() VehClient.openWith('vente:open', { dealerId = id }, 'open:vente') end,
            },
            {
                label = 'Revendre ce véhicule', icon = 'fa-solid fa-hand-holding-dollar',
                canInteract = function()
                    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                    return veh ~= 0 and isOwner(veh)
                end,
                onSelect = function()
                    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
                    if veh == 0 then return end
                    local res = VehClient.rpc('vente:resell', { dealerId = id, netId = VehToNet(veh) })
                    if res and res.ok then VehClient.notify('success', ('Revendu pour $%d.'):format(res.payout))
                    else VehClient.notify('error', VehClient.reason(res and res.reason)) end
                end,
            },
        })
        -- GESTION
        exports.sl_interact:addCoords(vector3(d.points.gestion.x, d.points.gestion.y, d.points.gestion.z), 1.6, {
            {
                label = 'Gestion de la concession', icon = 'fa-solid fa-briefcase',
                canInteract = function() return VehClient.myDealer == id end,
                onSelect = function() VehClient.openWith('gestion:open', { dealerId = id }, 'open:gestion') end,
            },
        })
    end
end)

-- ── showroom expo (local display vehicles) ──────────────────────────────────────────
local expoCars = {}   -- dealerId -> { {handle, price, coords} }

local function clearExpo(dealerId)
    for _, e in ipairs(expoCars[dealerId] or {}) do
        if e.handle and DoesEntityExist(e.handle) then DeleteEntity(e.handle) end
    end
    expoCars[dealerId] = {}
end

local function refreshExpo(dealerId)
    local d = Config.Dealership(dealerId); if not d then return end
    clearExpo(dealerId)
    local res = VehClient.rpc('expo:list', { dealerId = dealerId })
    if not res or not res.ok then return end
    local spots = d.expo or {}
    for i, item in ipairs(res.models or {}) do
        local spot = spots[i]; if not spot then break end
        local hash = joaat(item.model)
        if IsModelInCdimage(hash) then
            lib.requestModel(hash, 8000)
            local veh = CreateVehicle(hash, spot.x, spot.y, spot.z, spot.w or 0.0, false, false)
            SetEntityInvincible(veh, true)
            SetVehicleDoorsLocked(veh, 2)
            SetVehicleNumberPlateText(veh, 'SHOWROOM')
            SetVehicleOnGroundProperly(veh)
            FreezeEntityPosition(veh, true)
            SetEntityAsMissionEntity(veh, true, true)
            SetModelAsNoLongerNeeded(hash)
            expoCars[dealerId][#expoCars[dealerId] + 1] = { handle = veh, price = item.price, label = item.label,
                coords = vector3(spot.x, spot.y, spot.z + 1.2) }
        end
    end
end

CreateThread(function()
    while not (VehClient and exports.sl_core and exports.sl_core:isReady()) do Wait(300) end
    Wait(1500)
    for _, d in ipairs(Config.Dealerships) do refreshExpo(d.id) end
end)
RegisterNetEvent('sl_vehicles:refreshExpo', function(dealerId) refreshExpo(dealerId) end)

-- price label above expo cars
local function drawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.34, 0.34); SetTextFont(4); SetTextProportional(1)
    SetTextColour(255, 255, 255, 215); SetTextCentre(true)
    SetTextDropshadow(0, 0, 0, 0, 255); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        local wait = 800
        local pc = GetEntityCoords(PlayerPedId())
        for _, list in pairs(expoCars) do
            for _, e in ipairs(list) do
                if e.coords and #(pc - e.coords) < 14.0 then
                    wait = 0
                    drawText3D(e.coords, ('%s\n$%d'):format(e.label or '', e.price or 0))
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(expoCars) do clearExpo(id) end
end)

Config.Log('info', 'client dealership ready')
