--[[
    client/garage.lua — garage presence (so parked cars materialise while you're there) and the
    "[E] Garer ici" prompt when you drive YOUR car onto a free marked spot.
]]

local function myCharId()
    local c = LocalPlayer.state['sl:char']; return c and c.charId or nil
end

local function isOwner(veh)
    local vd = Entity(veh).state['sl:veh']
    return type(vd) == 'table' and tonumber(vd.owner) == tonumber(myCharId())
end

-- ── presence points (enter/exit -> server spawns/despawns parked cars) ───────────────
CreateThread(function()
    while GetResourceState('sl_core') ~= 'started' do Wait(200) end
    for _, g in ipairs(Config.Garages) do
        local gid = g.id
        lib.points.new({
            coords = g.blip and g.blip.coords or g.spots[1],
            distance = g.spawnReach or 80.0,
            onEnter = function() TriggerServerEvent('sl_vehicles:garageEnter', gid) end,
            onExit  = function() TriggerServerEvent('sl_vehicles:garageExit', gid) end,
        })
    end
end)

-- ── park prompt ──────────────────────────────────────────────────────────────────────
-- find the nearest garage spot within 4m of `veh` that accepts the vehicle's class
local function nearestSpot(veh)
    local vd = Entity(veh).state['sl:veh']
    local cat = type(vd) == 'table' and vd.category or 'car'
    local vc = GetEntityCoords(veh)
    local bestG, bestD
    for _, g in ipairs(Config.Garages) do
        local accepts = false
        for _, c in ipairs(g.classes or {}) do if c == cat then accepts = true break end end
        if accepts then
            for _, s in ipairs(g.spots) do
                local d = #(vc - vector3(s.x, s.y, s.z))
                if d <= 4.0 and (not bestD or d < bestD) then bestG, bestD = g, d end
            end
        end
    end
    return bestG
end

local parking = false
local function doPark(veh, garage)
    if parking then return end
    parking = true
    local props = lib.getVehicleProperties(veh)
    local fuel = Entity(veh).state.fuel or 100
    local body = GetVehicleBodyHealth(veh)
    local engine = GetVehicleEngineHealth(veh)
    local vd = Entity(veh).state['sl:veh']
    SetVehicleDoorsLocked(veh, 2)
    local res = VehClient.rpc('garage:park', {
        netId = VehToNet(veh), garageId = garage.id, props = props,
        fuel = math.floor(fuel + 0.5), body = math.floor(body), engine = math.floor(engine),
    })
    if res and res.ok then
        VehClient.notify('success', ('%s rangé.'):format(res.label or 'Véhicule'))
    else
        VehClient.notify('error', VehClient.reason(res and res.reason))
    end
    parking = false
end

CreateThread(function()
    while true do
        local wait = 600
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and isOwner(veh) then
            local garage = nearestSpot(veh)
            if garage then
                wait = 0
                lib.showTextUI('[E] Garer ici', { position = 'bottom-center' })
                if IsControlJustReleased(0, 38) then  -- E
                    lib.hideTextUI()
                    doPark(veh, garage)
                    Wait(800)
                end
            else
                lib.hideTextUI()
            end
        end
        Wait(wait)
    end
end)

Config.Log('info', 'client garage ready')
