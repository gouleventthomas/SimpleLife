--[[
    client/keys.lua — engine GATE (no key = can't start), the U lock shortcut, hotwire (H), remote
    engine application (sl:engine statebag), and the lock chirp. Owned vehicles carry 'sl:veh' with
    owner + key-set; a vehicle with no 'sl:veh' (random traffic) is freely drivable.
]]

local localHot = {}   -- netId -> true: locally hotwired until the engine stops

local function inDriverSeat()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return nil
end

-- a gated vehicle = owned ('sl:veh') AND I don't have a key
local function isGated(veh)
    local vd = Entity(veh).state['sl:veh']
    if type(vd) ~= 'table' then return false end
    return not VehClient.hasKey(veh)
end

-- ── engine gate + remote engine application ─────────────────────────────────────────
CreateThread(function()
    while true do
        local veh = inDriverSeat()
        if veh then
            local netId = VehToNet(veh)
            local commanded = Entity(veh).state['sl:engine']     -- remote start/stop
            if isGated(veh) and not localHot[netId] and commanded ~= true then
                -- kill the engine every frame until they hotwire or get a remote start
                SetVehicleEngineOn(veh, false, true, true)
                if GetIsVehicleEngineRunning(veh) then SetVehicleEngineOn(veh, false, true, true) end
                lib.showTextUI('[H] Crocheter le démarrage', { position = 'bottom-center' })
                Wait(0)
            else
                -- remote start/stop application (taxi/chauffeur or owner remote)
                if commanded == true and not GetIsVehicleEngineRunning(veh) then SetVehicleEngineOn(veh, true, true, false) end
                if commanded == false and not isGated(veh) and not localHot[netId] then
                    -- only force-off if explicitly commanded off and I'm not a key holder driving normally
                end
                -- if a hotwired car's engine stops, it must be re-hotwired
                if localHot[netId] and not GetIsVehicleEngineRunning(veh) then localHot[netId] = nil end
                lib.hideTextUI()
                Wait(300)
            end
        else
            lib.hideTextUI()
            Wait(500)
        end
    end
end)

-- ── hotwire (H while seated in a gated car) ─────────────────────────────────────────
local hotBusy = false
RegisterCommand('sl_veh_hotwire', function()
    if hotBusy then return end
    local veh = inDriverSeat(); if not veh or not isGated(veh) then return end
    if GetIsVehicleEngineRunning(veh) then return end   -- moteur éteint requis
    hotBusy = true
    if Config.Hotwire.alarm then SetVehicleAlarm(veh, true); StartVehicleAlarm(veh) end
    local picked = lib.progressCircle({
        duration = Config.Hotwire.pickDuration or 6000,
        label = 'Crochetage…', position = 'bottom',
        canCancel = true, disable = { move = true, car = true, combat = true },
    })
    if not picked then hotBusy = false; return end
    local cracked = lib.skillCheck(Config.Hotwire.skillDifficulty or 'medium')
    if not cracked then VehClient.notify('error', 'Crochetage échoué.'); hotBusy = false; return end
    local res = VehClient.rpc('hotwire', { netId = VehToNet(veh) })
    if res and res.ok then
        localHot[VehToNet(veh)] = true
        SetVehicleEngineOn(veh, true, true, false)
        VehClient.notify('success', 'Démarrage forcé.')
    else
        VehClient.notify('error', VehClient.reason(res and res.reason))
    end
    hotBusy = false
end, false)
RegisterKeyMapping('sl_veh_hotwire', 'Véhicule : crocheter le démarrage', 'keyboard', 'H')

-- ── U: (un)lock the nearest vehicle you have a key for ──────────────────────────────
RegisterCommand('sl_veh_lock', function()
    local ped = PlayerPedId()
    local pc = GetEntityCoords(ped)
    local best, bestD, bestVd
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local vd = Entity(veh).state['sl:veh']
        if type(vd) == 'table' and vd.id and VehClient.hasKey(veh) then
            local d = #(GetEntityCoords(veh) - pc)
            if d <= (Config.Limits.lockKeyReach or 12.0) and (not bestD or d < bestD) then
                best, bestD, bestVd = veh, d, vd
            end
        end
    end
    if not best then return end
    local locked = Entity(best).state['sl:locked']
    if locked == nil then locked = GetVehicleDoorLockStatus(best) == 2 end
    local res = VehClient.rpc('key:lock', { dbId = bestVd.id, locked = not locked })
    if res and res.ok then
        VehClient.notify('inform', res.locked and '🔒 Verrouillé' or '🔓 Déverrouillé')
    end
end, false)
RegisterKeyMapping('sl_veh_lock', 'Véhicule : verrouiller / déverrouiller', 'keyboard', Config.Keys.lockToggle or 'U')

-- ── lock chirp (server tells us to flash on remote lock) ────────────────────────────
RegisterNetEvent('sl_vehicles:keyChirp', function(netId, locked)
    local veh = NetToVeh(netId)
    if veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleLights(veh, 2); Wait(120); SetVehicleLights(veh, 0); Wait(120); SetVehicleLights(veh, 2); Wait(120); SetVehicleLights(veh, 0)
end)

Config.Log('info', 'client keys ready')
