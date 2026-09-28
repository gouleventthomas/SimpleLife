--[[
    client/arrival.lua — the ARRIVAL CINEMATIC (the signature moment).

    REPLAY of a human-flown landing. We load a flight path recorded with
    /startrecarrivage (recordings/arrival_last.json) and play it back frame-by-frame
    on a frozen plane: the exact approach + descent + flare + rollout YOU flew, smooth
    and 100% reproducible. The player rides as a passenger, then disembarks by climbing
    out the door (visible) onto the tarmac and gets control.

    ████ RELIABILITY IS #1 ████
    Every wait is bounded. If the recording is missing/invalid or anything fails, we
    fall back to a safe disembark teleport. finish() ALWAYS ends with the player
    CONTROLLABLE, VISIBLE, faded-in.

    1a: solo replay. 1b: a shared networked plane + a queued batch (TODO).
]]

SLIdentity = SLIdentity or {}

-- ── small bounded helpers ─────────────────────────────────────────────────────

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < Config.Timeouts.model do
        Wait(50); waited = waited + 50
    end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

-- Shortest signed angle (degrees) from `from` to `to`, so yaw interpolation never
-- spins the long way around the -180/180 seam.
local function angDiff(to, from)
    local d = (to - from) % 360.0
    if d > 180.0 then d = d - 360.0 end
    return d
end

-- Load + decode the recorded flight path from a client-streamed file (fallback path;
-- only works if recordings/*.json is in the manifest files{} and was streamed).
local function loadRecording()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'recordings/arrival_last.json')
    if not raw or raw == '' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' or #decoded < 2 then return nil end
    return decoded
end

-- Normalize frames to { t, x, y, z, pitch, roll, yaw } objects. The server sends
-- COMPACT arrays [t,x,y,z,pitch,roll,yaw] (small network payload); the client-file
-- fallback already returns objects. Returns nil if unusable.
local function normalizeFrames(frames)
    if type(frames) ~= 'table' or #frames < 2 then return nil end
    local first = frames[1]
    if type(first) ~= 'table' then return nil end
    if first.x ~= nil then return frames end  -- already object form
    local out = {}
    for i = 1, #frames do
        local f = frames[i]
        out[i] = { t = f[1], x = f[2], y = f[3], z = f[4], pitch = f[5], roll = f[6], yaw = f[7] }
    end
    return out
end

-- ── post-plane BUS SHUTTLE (REPLAY) ────────────────────────────────────────────
-- Same idea as the plane: REPLAY a route recorded with /startrecbus (bus_last.json).
-- A frozen bus is spawned at the recording's first frame, the player rides as a
-- passenger (a visual driver sits up front), the exact route you drove is played back
-- frame-by-frame, then the player is FORCED off at the final spot. The recording's last
-- frame IS the drop-off (wherever you stopped + did /stoprecbus) — no AI, no watchdog.
-- Returns true if it ran; false (no recording / error) so the caller falls back to a
-- direct disembark teleport. busStartMs/seatIdx carry the 1b shared timing + seat (nil/0 = solo).
local function runBusShuttle(ped, busFramesRaw, busStartMs, seatIdx)
    local B = Config.Bus
    if not B or not B.enabled then return false end

    local frames = normalizeFrames(busFramesRaw)
    if not frames or #frames < 2 then
        Config.Log('warn', 'bus: pas d\'enregistrement (recordings/bus_last.json) — navette ignorée (fais /startrecbus)')
        return false
    end
    local nF = #frames

    local busHash = loadModel(B.model) or loadModel('airbus') or loadModel('bus') or loadModel('coach')
    if not busHash then
        Config.Log('warn', 'bus: aucun modèle chargé — navette ignorée')
        return false
    end

    -- spawn the bus at the recording's FIRST frame, frozen (we script its motion).
    local f0 = frames[1]
    local bus = CreateVehicle(busHash, f0.x, f0.y, f0.z, f0.yaw or 0.0, true, false)
    SetModelAsNoLongerNeeded(busHash)
    local ew = 0
    while (not bus or not DoesEntityExist(bus)) and ew < 2000 do Wait(50); ew = ew + 50 end
    if not bus or not DoesEntityExist(bus) then return false end
    SetEntityInvincible(bus, true)
    SetVehicleStrong(bus, true)
    SetVehicleEngineOn(bus, true, true, false)
    FreezeEntityPosition(bus, true)  -- scripted playback: physics must not interfere
    SetEntityCoordsNoOffset(bus, f0.x, f0.y, f0.z, false, false, false)
    SetEntityRotation(bus, f0.pitch or 0.0, f0.roll or 0.0, f0.yaw or 0.0, 2, true)

    -- visual driver up front
    local driver
    local driverHash = loadModel('s_m_m_ccrew_01') or loadModel('s_m_m_trucker_01')
    if driverHash then
        driver = CreatePedInsideVehicle(bus, 4, driverHash, -1, true, false)
        SetModelAsNoLongerNeeded(driverHash)
        if driver and DoesEntityExist(driver) then
            SetEntityInvincible(driver, true)
            SetBlockingOfNonTemporaryEvents(driver, true)
        end
    end

    -- auto-board the player as a passenger (teleports them into the bus; record the bus
    -- starting from the plane's park spot so this handoff is seamless). Use the player's seat
    -- index, stacked (modulo) onto the bus seats so a batch spreads out rather than overlapping.
    local busSeats = GetVehicleModelNumberOfSeats(busHash)
    local busPax = busSeats - 1
    if busPax < 1 then busPax = 1 end
    local effBusSeat = ((tonumber(seatIdx) or 0) % busPax)
    if effBusSeat < 0 then effBusSeat = 0 end
    SetPedIntoVehicle(ped, bus, effBusSeat)
    if not IsPedInVehicle(ped, bus, false) then SetPedIntoVehicle(ped, bus, 0) end
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), false, 0)
    Wait(600)

    -- REPLAY the recorded route (interpolated each render frame, like the plane).
    local speed = (Config.Replay and Config.Replay.speed) or 1.0
    if speed <= 0 then speed = 1.0 end

    -- 1b: bounded-wait for the SHARED bus start so a batch rides in lockstep (solo: nil -> none).
    local startMs = GetGameTimer()
    if busStartMs then
        local guard = GetGameTimer() + 8000
        while GetGameTimer() < busStartMs and GetGameTimer() < guard do Wait(0) end
        startMs = busStartMs
    end
    local cursor = 1
    while true do
        if not DoesEntityExist(bus) then break end
        local elapsed = (GetGameTimer() - startMs) * speed
        while cursor < nF and frames[cursor + 1].t <= elapsed do cursor = cursor + 1 end
        if cursor >= nF then break end
        local a, b = frames[cursor], frames[cursor + 1]
        local seg = (b.t - a.t)
        local al = (seg > 0) and ((elapsed - a.t) / seg) or 0.0
        if al < 0 then al = 0 elseif al > 1 then al = 1 end
        SetEntityCoordsNoOffset(bus,
            a.x + (b.x - a.x) * al,
            a.y + (b.y - a.y) * al,
            a.z + (b.z - a.z) * al,
            false, false, false)
        SetEntityRotation(bus,
            (a.pitch or 0) + ((b.pitch or 0) - (a.pitch or 0)) * al,
            (a.roll or 0) + ((b.roll or 0) - (a.roll or 0)) * al,
            (a.yaw or 0) + angDiff(b.yaw or 0, a.yaw or 0) * al,
            2, true)
        Wait(0)
    end
    -- snap to the exact final frame (the drop-off where you stopped recording).
    local fl = frames[nF]
    SetEntityCoordsNoOffset(bus, fl.x, fl.y, fl.z, false, false, false)
    SetEntityRotation(bus, fl.pitch or 0, fl.roll or 0, fl.yaw or 0, 2, true)
    Wait(400)

    -- FORCE the player off at the final spot, with the VISIBLE climb-down animation (mirrors
    -- the plane disembark). The bus stays FROZEN so the get-out anim plays against a stable
    -- vehicle, and we do NOT ClearPedTasksImmediately — that would eject the ped instantly and
    -- SKIP the animation (the bug). TaskLeaveVehicle flag 0 = the full open-door + step-down.
    SetVehicleDoorsLocked(bus, 0)
    SetVehicleDoorOpen(bus, 1, false, false)   -- crack the passenger door for the look
    TaskLeaveVehicle(ped, bus, 0)              -- normal exit: climb down (NOT a warp)
    local w = 0
    while IsPedInVehicle(ped, bus, false) and w < (Config.Timeouts.disembark or 7000) do Wait(50); w = w + 50 end
    Wait(400)  -- let the feet plant before control returns
    -- anti-stuck hard-place ONLY if the animation never completed (timed out still seated).
    if IsPedInVehicle(ped, bus, false) then
        local bc = GetEntityCoords(bus)
        RequestCollisionAtCoord(bc.x, bc.y, bc.z)
        SetEntityCoordsNoOffset(ped, bc.x + 3.0, bc.y, bc.z, false, false, false)
        SetEntityHeading(ped, fl.yaw or 0.0)
    end

    -- cleanup
    CreateThread(function()
        Wait(8000)
        if driver and DoesEntityExist(driver) then DeleteEntity(driver) end
        if bus and DoesEntityExist(bus) then DeleteEntity(bus) end
    end)

    return true
end

-- ── the cinematic ─────────────────────────────────────────────────────────────

--- Run the full arrival for the local player. ALWAYS ends controllable.
---@param payload { model: string, seat: integer, batch: integer }
function SLIdentity.runArrival(payload)
    payload = payload or {}
    local seat = tonumber(payload.seat) or 0
    -- 1b shared-start: begin the deterministic replay `startInMs` after RECEIVING the event
    -- (captured now ≈ receipt) so a whole batch departs in lockstep on its own clock — no
    -- cross-machine clock needed. Solo = 0 (immediate, identical to 1a). Clamp defensively.
    local arriveStamp = GetGameTimer()
    local startInMs = tonumber(payload.startInMs) or 0
    if startInMs < 0 then startInMs = 0 elseif startInMs > 10000 then startInMs = 10000 end
    local busStartMs = nil  -- set once the plane frames are known; read by finish() (upvalue)

    if SLIdentity.setArrivalActive then SLIdentity.setArrivalActive(true) end

    local plane, pilot, cam
    local camActive = false

    -- The one true exit: VISIBLE disembark + cleanup + hand back control.
    local function finish(forcePlaceOnFoot)
        local ped = PlayerPedId()

        -- VISIBLE DISEMBARK: real get-out animation so the player climbs down out of
        -- the plane (in 1b, everyone does). Cam stays on the plane during the exit,
        -- THEN we cut to gameplay cam once they're on the tarmac.
        if plane and DoesEntityExist(plane) and IsPedInVehicle(ped, plane, false) and not forcePlaceOnFoot then
            SetVehicleDoorOpen(plane, 1, false, false)  -- crack a passenger door for the look
            TaskLeaveVehicle(ped, plane, 0)             -- normal exit (climb down)
            local waited = 0
            while IsPedInVehicle(ped, plane, false) and waited < (Config.Timeouts.disembark or 7000) do
                Wait(50); waited = waited + 50
            end
            Wait(400)  -- plant feet before cutting the cam
        end

        if camActive then
            RenderScriptCams(false, false, 0, true, true)
            camActive = false
        end
        if cam then DestroyCam(cam, false); cam = nil end

        -- BUS SHUTTLE (success path): a bus picks the player up on the tarmac and REPLAYS
        -- the recorded route to the city drop-off, then FORCES them off there. busStartMs +
        -- seat carry the 1b shared timing/seat so a batch rides one (coincident) bus together.
        local placed = false
        if not forcePlaceOnFoot then
            placed = runBusShuttle(PlayerPedId(), payload.busFrames, busStartMs, seat)
        end

        -- Fallback ONLY: no bus / error path / still stuck -> place at the disembark point.
        if not placed and (forcePlaceOnFoot or (plane and DoesEntityExist(plane) and IsPedInVehicle(ped, plane, false))) then
            local dp = Config.DisembarkPoint
            RequestCollisionAtCoord(dp.coord.x, dp.coord.y, dp.coord.z)
            SetEntityCoordsNoOffset(ped, dp.coord.x, dp.coord.y, dp.coord.z, false, false, false)
            SetEntityHeading(ped, dp.heading)
            local cwait = 0
            while not HasCollisionLoadedAroundEntity(ped) and cwait < Config.Timeouts.collision do
                RequestCollisionAtCoord(dp.coord.x, dp.coord.y, dp.coord.z)
                Wait(50); cwait = cwait + 50
            end
        end

        if SLIdentity.releaseToPlayer then
            SLIdentity.releaseToPlayer()
        else
            if SLIdentity.setArrivalActive then SLIdentity.setArrivalActive(false) end
            if SLIdentity.markSpawned then SLIdentity.markSpawned() end
            FreezeEntityPosition(ped, false)
            SetEntityVisible(ped, true, false)
            SetPlayerControl(PlayerId(), true, 0)
            DoScreenFadeIn(800)
        end
        exports.sl_ui:notify('info', 'Bienvenue à Los Santos.')

        CreateThread(function()
            Wait(12000)
            if pilot and DoesEntityExist(pilot) then DeleteEntity(pilot) end
            if plane and DoesEntityExist(plane) then DeleteEntity(plane) end
        end)

        Config.Log('info', 'arrival finished — player controllable on tarmac')
    end

    -- 1) Apply the saved appearance (it INCLUDES the model). Fall back to just the model
    --    for never-customized characters. applyModel alone would reset the custom look.
    if payload.appearance and GetResourceState('fivem-appearance') == 'started' then
        exports['fivem-appearance']:setPlayerAppearance(payload.appearance)
    elseif SLIdentity.applyModel then
        SLIdentity.applyModel(payload.model)
    end

    -- Hide/freeze the ped while we set up.
    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)

    Config.Log('info', ('arrival: runArrival START (playerModel=%s)'):format(tostring(payload.model)))

    -- 2) Get the recorded flight path. PRIMARY: the server read the file and sent it in
    --    the payload (the client can't read arbitrary resource files). FALLBACK: a
    --    client-streamed file. None -> safe disembark (never strand the player).
    local frames = normalizeFrames(payload.frames) or loadRecording()
    if not frames or #frames < 2 then
        Config.Log('error', 'arrival: no recording (server sent none, no client file) — direct disembark')
        finish(true)
        return
    end
    local nF = #frames
    Config.Log('info', ('arrival: recording loaded (%d frames, %.1fs)'):format(nF, (frames[nF].t or 0) / 1000))

    -- 3) Plane model (recording was flown with Config.PlaneModel; fallbacks just in case).
    local candidates = { Config.PlaneModel, 'jet', 'nimbus', 'luxor2' }
    local planeHash, planeName
    for _, name in ipairs(candidates) do
        local h = loadModel(name)
        if h then planeHash, planeName = h, name; break end
    end
    if not planeHash then
        Config.Log('error', 'arrival: no plane model loaded — direct disembark')
        finish(true)
        return
    end
    Config.Log('info', ('arrival: plane model = "%s"'):format(planeName))

    -- 4) Spawn the plane at the recording's FIRST frame, frozen (we script its motion).
    local f0 = frames[1]
    plane = CreateVehicle(planeHash, f0.x, f0.y, f0.z, f0.yaw or 0.0, true, false)
    SetModelAsNoLongerNeeded(planeHash)
    local exWait = 0
    while (not plane or not DoesEntityExist(plane)) and exWait < 2000 do Wait(50); exWait = exWait + 50 end
    if not plane or not DoesEntityExist(plane) then
        Config.Log('error', 'arrival: plane creation failed — direct disembark')
        finish(true)
        return
    end
    SetEntityInvincible(plane, true)
    SetVehicleStrong(plane, true)
    SetVehicleEngineOn(plane, true, true, false)
    SetVehicleLandingGear(plane, 0)
    FreezeEntityPosition(plane, true)  -- scripted playback: physics must not interfere
    SetEntityCoordsNoOffset(plane, f0.x, f0.y, f0.z, false, false, false)
    SetEntityRotation(plane, f0.pitch or 0.0, f0.roll or 0.0, f0.yaw or 0.0, 2, true)

    -- 5) Cockpit pilot (visual) + seat the player.
    local pilotHash = loadModel(Config.PilotModel)
    if pilotHash then
        pilot = CreatePedInsideVehicle(plane, 4, pilotHash, -1, true, false)
        SetModelAsNoLongerNeeded(pilotHash)
        if pilot and DoesEntityExist(pilot) then
            SetEntityInvincible(pilot, true)
            SetBlockingOfNonTemporaryEvents(pilot, true)
        end
    end
    ped = PlayerPedId()
    -- Seat the player at its assigned index; OVERFLOW beyond capacity STACKS (modulo) onto an
    -- existing seat (accepted by design — keeps `jet`, never rejects a batch). `seat` itself is
    -- left untouched so finish() can hand the original index to the bus.
    local maxSeats = GetVehicleModelNumberOfSeats(planeHash)
    local passengerSeats = maxSeats - 1   -- seat -1 is the pilot; 0..maxSeats-2 are passengers
    if passengerSeats < 1 then passengerSeats = 1 end
    local effSeat = (seat >= 0 and seat or 0) % passengerSeats
    SetPedIntoVehicle(ped, plane, effSeat)
    if not IsPedInVehicle(ped, plane, false) then SetPedIntoVehicle(ped, plane, 0) end
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), false, 0)

    -- 6) Chase cam on the plane.
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Config.Camera.fov, false, 0)
    if cam then
        AttachCamToEntity(cam, plane, 0.0, Config.Camera.behind, Config.Camera.up, true)
        PointCamAtEntity(cam, plane, 0.0, 0.0, 0.0, true)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        camActive = true
    end

    DoScreenFadeIn(1200)

    -- 7) REPLAY: walk the recorded frames by elapsed time, interpolating position +
    --    rotation each render frame for smooth 60fps playback of the 20Hz capture.
    local speed = (Config.Replay and Config.Replay.speed) or 1.0
    if speed <= 0 then speed = 1.0 end

    -- 1b shared-start: this client begins at arriveStamp + lead so a whole batch's (coincident,
    -- local) planes move in lockstep. The bus's shared start is derived here too — after the
    -- flight duration + a board grace — so the batch boards one bus together. Solo (lead 0):
    -- planeStartMs ≈ now and busStartMs stays nil, i.e. no behavioural change from 1a.
    local planeStartMs = arriveStamp + startInMs
    if startInMs > 0 then
        local planeDurMs = (frames[nF].t or 0) / speed
        busStartMs = arriveStamp + startInMs + planeDurMs + ((Config.Bus and Config.Bus.boardLeadMs) or 5000)
    end
    -- bounded spin-wait until the shared departure tick (lead is clamped <=10s). A client that
    -- loaded slower than the lead is already PAST it -> no wait; the cursor math below starts
    -- with elapsed>0 and JUMPS onto the in-progress frame, converging instead of lagging.
    while GetGameTimer() < planeStartMs do Wait(0) end

    local startMs = planeStartMs
    local cursor = 1
    while true do
        if not DoesEntityExist(plane) then break end
        local elapsed = (GetGameTimer() - startMs) * speed
        while cursor < nF and frames[cursor + 1].t <= elapsed do cursor = cursor + 1 end
        if cursor >= nF then break end
        local a, b = frames[cursor], frames[cursor + 1]
        local seg = (b.t - a.t)
        local al = (seg > 0) and ((elapsed - a.t) / seg) or 0.0
        if al < 0 then al = 0 elseif al > 1 then al = 1 end
        SetEntityCoordsNoOffset(plane,
            a.x + (b.x - a.x) * al,
            a.y + (b.y - a.y) * al,
            a.z + (b.z - a.z) * al,
            false, false, false)
        SetEntityRotation(plane,
            (a.pitch or 0) + ((b.pitch or 0) - (a.pitch or 0)) * al,
            (a.roll or 0) + ((b.roll or 0) - (a.roll or 0)) * al,
            (a.yaw or 0) + angDiff(b.yaw or 0, a.yaw or 0) * al,
            2, true)
        Wait(0)
    end
    -- snap to the exact final frame
    local fl = frames[nF]
    SetEntityCoordsNoOffset(plane, fl.x, fl.y, fl.z, false, false, false)
    SetEntityRotation(plane, fl.pitch or 0, fl.roll or 0, fl.yaw or 0, 2, true)
    Config.Log('info', 'arrival: replay finished — parked')
    Wait(600)  -- a beat before the doors open

    -- 8) Visible disembark + hand off.
    finish(false)
end

-- Defensive backstop.
RegisterNetEvent('sl_identity:arrivalSafetyPing', function()
    if SLIdentity.isSpawned and not SLIdentity.isSpawned() then
        if SLIdentity.releaseToPlayer then SLIdentity.releaseToPlayer() end
    end
end)
