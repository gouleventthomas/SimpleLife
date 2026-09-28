--[[
    client/world.lua — client-enforced world control, driven by Config.World.

    A clean, controlled RP world:
      - disablePeds     : no ambient pedestrians / scenario peds (density 0 every frame)
      - disableTraffic  : no ambient / parked vehicles (off by default)
      - disableWanted   : police stars are IMPOSSIBLE (max wanted 0) + any stars auto-cleared
      - disableDispatch : no police / EMS / fire dispatch response
      - disableEvents   : no random ambient events / random cops

    Density natives are "this frame" and MUST be re-applied every frame, so they live in a
    Wait(0) loop; the wanted/dispatch/event suppression is cheaper and runs on a 1s loop.
]]

local W = Config.World or {}

-- One-shot: make stars literally impossible.
if W.disableWanted then
    SetMaxWantedLevel(0)
end

-- Per-frame: ambient density + weapon-wheel block (only spins at 0ms when something needs it).
if W.disablePeds or W.disableTraffic or W.disableWeaponWheel then
    CreateThread(function()
        while true do
            if W.disablePeds then
                SetPedDensityMultiplierThisFrame(0.0)
                SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
            end
            if W.disableTraffic then
                SetVehicleDensityMultiplierThisFrame(0.0)
                SetRandomVehicleDensityMultiplierThisFrame(0.0)
                SetParkedVehicleDensityMultiplierThisFrame(0.0)
            end
            if W.disableWeaponWheel then
                BlockWeaponWheelThisFrame()
                DisableControlAction(0, 37, true) -- INPUT_SELECT_WEAPON (weapon wheel key)
            end
            Wait(0)
        end
    end)
end

-- 1s loop: keep wanted at 0, suppress random cops / events / dispatch.
if W.disableWanted or W.disableEvents or W.disableDispatch then
    CreateThread(function()
        while true do
            if W.disableWanted then
                local pid = PlayerId()
                if GetPlayerWantedLevel(pid) > 0 then
                    SetPlayerWantedLevel(pid, 0, false)
                    SetPlayerWantedLevelNow(pid, false)
                end
            end
            if W.disableEvents then
                SetCreateRandomCops(false)
                SetCreateRandomCopsNotOnScenarios(false)
                SetCreateRandomCopsOnScenarios(false)
            end
            if W.disableDispatch then
                for i = 1, 15 do EnableDispatchService(i, false) end
                SetPoliceIgnorePlayer(PlayerId(), true)
            end
            Wait(1000)
        end
    end)
end

-- Kill mid-air car rotation (anti-stunt). Only spins at 0ms while DRIVING a land vehicle;
-- otherwise idles at 500ms. Planes (16) / helicopters (15) keep their flight controls.
if W.disableCarAirControl then
    CreateThread(function()
        while true do
            local wait = 500
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                    local class = GetVehicleClass(veh)
                    if class ~= 15 and class ~= 16 then
                        wait = 0
                        if IsEntityInAir(veh) and GetEntityHeightAboveGround(veh) > 1.5 then
                            DisableControlAction(0, 59, true) -- steer L/R (air yaw + roll)
                            DisableControlAction(0, 60, true) -- pitch up/down
                            DisableControlAction(0, 71, true) -- throttle (forward flip)
                            DisableControlAction(0, 72, true) -- brake (backward flip)
                        end
                    end
                end
            end
            Wait(wait)
        end
    end)
end

Config.Log('info', ('world control: peds=%s traffic=%s wanted=%s dispatch=%s events=%s wheel=%s airctl=%s')
    :format(tostring(W.disablePeds), tostring(W.disableTraffic), tostring(W.disableWanted),
            tostring(W.disableDispatch), tostring(W.disableEvents),
            tostring(W.disableWeaponWheel), tostring(W.disableCarAirControl)))
