--[[
    client/fuel.lua — fuel consumption (statebag, written by the driver), out-of-fuel cutoff,
    station refuel (pump ox_target), jerrycan item, and a small fuel indicator while driving.
]]

if not Config.Fuel.enabled then return end

local lastCoords = {}   -- netId -> last coords (for distance-based drain)

local function setFuel(veh, v)
    pcall(function() Entity(veh).state:set('fuel', v, true) end)
end

-- ── consumption ──────────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(3000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and GetIsVehicleEngineRunning(veh) then
            local netId = VehToNet(veh)
            local cur = tonumber(Entity(veh).state.fuel) or 100.0
            local coords = GetEntityCoords(veh)
            local dist = lastCoords[netId] and #(coords - lastCoords[netId]) or 0.0
            lastCoords[netId] = coords
            local drain = (Config.Fuel.idleDrainPerMin / 20.0) + (Config.Fuel.drivePerKm * dist / 1000.0)
            local newFuel = math.max(0.0, cur - drain)
            setFuel(veh, newFuel)
            if newFuel <= 0.0 then
                SetVehicleEngineOn(veh, false, true, true)
                SetVehicleUndriveable(veh, true)
                VehClient.notify('warning', "Panne sèche : réservoir vide.")
            elseif GetVehicleUndriveable then
                SetVehicleUndriveable(veh, false)
            end
        end
    end
end)

-- ── station pumps ─────────────────────────────────────────────────────────────────────
local function nearestVehicle(maxD)
    local pc = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(GetEntityCoords(veh) - pc)
        if d <= (maxD or 5.0) and (not bestD or d < bestD) then best, bestD = veh, d end
    end
    return best
end

local function refuelMenu()
    local veh = nearestVehicle(5.0)
    if not veh then VehClient.notify('error', 'Aucun véhicule à proximité de la pompe.'); return end
    local cur = math.floor(tonumber(Entity(veh).state.fuel) or 100)
    if cur >= 100 then VehClient.notify('inform', 'Réservoir déjà plein.'); return end
    local input = lib.inputDialog('Station-service', {
        { type = 'slider', label = 'Niveau cible (%)', default = 100, min = cur, max = 100 },
        { type = 'select', label = 'Paiement', default = 'cash', options = {
            { label = 'Espèces', value = 'cash' }, { label = 'Banque', value = 'bank' } } },
    })
    if not input then return end
    local target = math.floor(input[1]); local account = input[2]
    local ok = lib.progressCircle({ duration = math.max(1500, (target - cur) * 120), label = 'Ravitaillement…',
        position = 'bottom', canCancel = true, disable = { move = true, combat = true } })
    if not ok then return end
    local res = VehClient.rpc('fuel:refuel', { netId = VehToNet(veh), target = target, account = account })
    if res and res.ok then VehClient.notify('success', ('Plein fait (%d%%) — $%d'):format(res.fuel, res.cost))
    else VehClient.notify('error', VehClient.reason(res and res.reason)) end
end

CreateThread(function()
    while GetResourceState('sl_interact') ~= 'started' do Wait(200) end
    exports.sl_interact:addModel(Config.Fuel.pumpModels, {
        { label = 'Faire le plein', icon = 'fa-solid fa-gas-pump', distance = Config.Fuel.refuelReach or 4.0,
          onSelect = function() refuelMenu() end },
    })
end)

-- ── jerrycan item ────────────────────────────────────────────────────────────────────
RegisterNetEvent('sl_inventory:onUse', function(item)
    if item ~= 'jerrycan' then return end
    local veh = nearestVehicle(5.0)
    if not veh then VehClient.notify('error', 'Aucun véhicule à proximité.'); return end
    local ok = lib.progressCircle({ duration = 5000, label = 'Remplissage au jerrican…', position = 'bottom',
        canCancel = true, disable = { move = true, combat = true } })
    if not ok then return end
    local res = VehClient.rpc('fuel:jerrycan', { netId = VehToNet(veh) })
    if res and res.ok then VehClient.notify('success', ('Carburant ajouté (%d%%).'):format(res.fuel))
    else VehClient.notify('error', VehClient.reason(res and res.reason)) end
end)

-- ── tiny fuel indicator while driving ────────────────────────────────────────────────
CreateThread(function()
    while true do
        local wait = 800
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            wait = 0
            local fuel = math.floor(tonumber(Entity(veh).state.fuel) or 100)
            local col = fuel <= 15 and { 235, 80, 60 } or { 235, 235, 235 }
            SetTextFont(4); SetTextScale(0.42, 0.42); SetTextColour(col[1], col[2], col[3], 220)
            SetTextOutline(); SetTextEntry('STRING')
            AddTextComponentSubstringPlayerName(('⛽ %d%%'):format(fuel))
            DrawText(0.86, 0.93)
        end
        Wait(wait)
    end
end)

Config.Log('info', 'client fuel ready')
