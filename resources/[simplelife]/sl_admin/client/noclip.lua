--[[
    client/noclip.lua — a smooth, txAdmin-style free-flight noclip.

    Moves the ped directly along the gameplay camera's facing (pitch included), so it feels
    like a free camera. Collision off, gravity neutralised, controllable speed. Toggle via
    Noclip.toggle() (the admin menu) — also exposes Noclip.isActive().

    Controls while active:
      W / S        forward / back (along where you look)
      A / D        strafe left / right
      Space / Ctrl up / down
      Shift        x4 speed     Alt  x0.25 speed
]]

-- `godmode` is the SHARED invincibility intent (the Self-menu godmode toggle writes it). Noclip
-- forces invincibility ON while flying, but on exit it RESTORES to this flag instead of clearing
-- it — otherwise toggling noclip would silently wipe a godmode the admin had enabled.
Noclip = { active = false, godmode = false }

function Noclip.isActive() return Noclip.active end

-- Unit forward vector from the gameplay cam (x=pitch, z=yaw), pitch included.
local function camForward()
    local r = GetGameplayCamRot(2)
    local p, y = math.rad(r.x), math.rad(r.z)
    local cp = math.cos(p)
    return vector3(-math.sin(y) * cp, math.cos(y) * cp, math.sin(p)), y
end

-- Controls we suppress each frame (movement / combat / enter), reading them as "disabled".
local SUPPRESS = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 47, 58, 140, 141, 142, 257, 263, 264, 75 }

local function loop()
    while Noclip.active do
        local ped = PlayerPedId()
        for _, c in ipairs(SUPPRESS) do DisableControlAction(0, c, true) end

        local fwd, yaw = camForward()
        local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)

        local dx, dy, dz = 0.0, 0.0, 0.0
        if IsDisabledControlPressed(0, 32) then dx, dy, dz = dx + fwd.x, dy + fwd.y, dz + fwd.z end
        if IsDisabledControlPressed(0, 33) then dx, dy, dz = dx - fwd.x, dy - fwd.y, dz - fwd.z end
        if IsDisabledControlPressed(0, 34) then dx, dy = dx - right.x, dy - right.y end
        if IsDisabledControlPressed(0, 35) then dx, dy = dx + right.x, dy + right.y end
        if IsDisabledControlPressed(0, 22) then dz = dz + 1.0 end   -- Space up
        if IsDisabledControlPressed(0, 36) then dz = dz - 1.0 end   -- Ctrl down

        local mult = (Config.Noclip.speed or 1.0)
        if IsDisabledControlPressed(0, 21) then mult = mult * (Config.Noclip.fast or 4.0) end
        if IsDisabledControlPressed(0, 19) then mult = mult * (Config.Noclip.slow or 0.25) end

        local step = (Config.Noclip.base or 0.7) * mult * (GetFrameTime() * 60.0)
        local pos = GetEntityCoords(ped)
        SetEntityCoordsNoOffset(ped, pos.x + dx * step, pos.y + dy * step, pos.z + dz * step, true, true, true)
        SetEntityHeading(ped, GetGameplayCamRot(2).z)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        Wait(0)
    end
end

function Noclip.toggle()
    Noclip.active = not Noclip.active
    local ped = PlayerPedId()
    if Noclip.active then
        SetEntityInvincible(ped, true)
        SetEntityCollision(ped, false, false)
        FreezeEntityPosition(ped, false)
        SetPlayerInvincible(PlayerId(), true)
        CreateThread(loop)
    else
        -- restore invincibility to the godmode intent (NOT a blind clear), so noclip never
        -- wipes a godmode the admin set via the Self menu.
        SetEntityInvincible(ped, Noclip.godmode)
        SetPlayerInvincible(PlayerId(), Noclip.godmode)
        SetEntityCollision(ped, true, true)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        -- drop the ped onto the ground beneath where it stopped
        local p = GetEntityCoords(ped)
        local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z, false)
        if ok then SetEntityCoordsNoOffset(ped, p.x, p.y, z + 1.0, false, false, false) end
    end
    return Noclip.active
end

-- Safety: never leave a player stuck noclipping if the resource stops.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Noclip.active then return end
    Noclip.active = false
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityCollision(ped, true, true)
end)
