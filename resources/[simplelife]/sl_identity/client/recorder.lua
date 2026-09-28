--[[
    client/recorder.lua — DEV path recorder for the arrival (jet) AND the bus shuttle.

    You drive/fly the route ONCE; we sample the vehicle's full transform at 20 Hz; the
    server writes it to a file; arrival.lua REPLAYS it frame-by-frame (organic + exact).

      /startrecarrivage + /stoprecarrivage  -> recordings/arrival_last.json  (the plane)
      /startrecbus      + /stoprecbus        -> recordings/bus_last.json      (the bus)

    Dev-only (env=dev).
]]

local recording = false
local recVeh = nil
local recSpawned = false
local recKind = 'arrival'
local samples = {}
local t0 = 0

local function isDev() return GlobalState.slCoreEnv == 'dev' end

-- Spawn a model + seat the player (driver). Returns the vehicle or 0.
local function spawnAndSeat(model, altitude)
    local ped = PlayerPedId()
    local hash = GetHashKey(model)
    RequestModel(hash)
    local w = 0
    while not HasModelLoaded(hash) and w < 10000 do Wait(50); w = w + 50 end
    if not HasModelLoaded(hash) then return 0 end
    local c = GetEntityCoords(ped)
    local veh = CreateVehicle(hash, c.x, c.y, c.z + (altitude or 0.0), GetEntityHeading(ped), true, false)
    SetModelAsNoLongerNeeded(hash)
    local ew = 0
    while not DoesEntityExist(veh) and ew < 2000 do Wait(50); ew = ew + 50 end
    SetPedIntoVehicle(ped, veh, -1)  -- driver seat
    SetVehicleEngineOn(veh, true, true, false)
    return veh
end

local function beginSampling()
    samples = {}
    t0 = GetGameTimer()
    recording = true
    CreateThread(function()
        while recording do
            if recVeh and DoesEntityExist(recVeh) then
                local co = GetEntityCoords(recVeh)
                local ro = GetEntityRotation(recVeh, 2)  -- (pitch=x, roll=y, yaw=z), order 2
                samples[#samples + 1] = {
                    t     = GetGameTimer() - t0,
                    x     = co.x, y = co.y, z = co.z,
                    pitch = ro.x, roll = ro.y, yaw = ro.z,
                    speed = GetEntitySpeed(recVeh),
                }
            end
            Wait(50)  -- 20 Hz
        end
    end)
end

local function stopAndSave(label)
    if not recording then print('^3[rec]^7 aucun enregistrement en cours'); return end
    recording = false
    Wait(120)
    local n = #samples
    print(('^2[rec]^7 STOP (%s) — %d frames, %.1fs'):format(label, n, (n > 0 and samples[n].t or 0) / 1000))
    if n > 0 then
        local a, b = samples[1], samples[n]
        print(('^2[rec]^7 start (%.1f, %.1f, %.1f) -> end (%.1f, %.1f, %.1f)'):format(a.x, a.y, a.z, b.x, b.y, b.z))
    end
    TriggerServerEvent('sl_identity:saveRecording', samples, recKind)
    print(('^2[rec]^7 envoyé -> recordings/%s_last.json'):format(recKind == 'bus' and 'bus' or 'arrival'))

    if recSpawned and recVeh and DoesEntityExist(recVeh) then
        local ped = PlayerPedId()
        if IsPedInVehicle(ped, recVeh, false) then TaskLeaveVehicle(ped, recVeh, 0) end
        local v = recVeh
        CreateThread(function() Wait(6000); if DoesEntityExist(v) then DeleteEntity(v) end end)
    end
    recVeh = nil
end

-- ── /startrecarrivage — fly the jet ───────────────────────────────────────────
RegisterCommand('startrecarrivage', function()
    if not isDev() then return end
    if recording then print('^3[rec]^7 enregistrement déjà en cours'); return end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    recSpawned = false
    if veh == 0 then
        veh = spawnAndSeat('jet', 300.0)
        if veh == 0 then print('^1[rec]^7 jet KO'); return end
        SetVehicleForwardSpeed(veh, 90.0)
        SetVehicleLandingGear(veh, 0)
        recSpawned = true
        print('^2[rec]^7 jet spawné — pilote la descente + l\'atterrissage')
    else
        print('^2[rec]^7 enregistrement de l\'avion courant')
    end
    recVeh = veh; recKind = 'arrival'
    beginSampling()
    print('^2[rec]^7 REC arrivage DÉMARRÉ — /stoprecarrivage à l\'arrêt complet')
end, false)

RegisterCommand('stoprecarrivage', function()
    if not isDev() then return end
    stopAndSave('arrivage')
end, false)

-- ── /startrecbus — drive the bus shuttle route (airbus) ────────────────────────
RegisterCommand('startrecbus', function()
    if not isDev() then return end
    if recording then print('^3[rec]^7 enregistrement déjà en cours'); return end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    recSpawned = false
    if veh == 0 then
        veh = spawnAndSeat('airbus', 0.0)
        if veh == 0 then print('^1[rec]^7 airbus KO'); return end
        recSpawned = true
        print('^2[rec]^7 airbus spawné — CONDUIS du tarmac jusqu\'au drop-off, puis /stoprecbus')
    else
        print('^2[rec]^7 enregistrement du véhicule courant')
    end
    recVeh = veh; recKind = 'bus'
    beginSampling()
    print('^2[rec]^7 REC bus DÉMARRÉ — /stoprecbus à l\'arrêt complet au drop-off')
end, false)

RegisterCommand('stoprecbus', function()
    if not isDev() then return end
    stopAndSave('bus')
end, false)

-- ── on-screen REC indicator ───────────────────────────────────────────────────
CreateThread(function()
    while true do
        if recording then
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(('~r~* REC~s~ %s  ~b~%d frames'):format(recKind, #samples))
            SetTextScale(0.5, 0.5)
            SetTextFont(4)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            EndTextCommandDisplayText(0.46, 0.04)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ── chat suggestions ──────────────────────────────────────────────────────────
CreateThread(function()
    Wait(800)
    local sug = {
        { '/startrecarrivage', 'DEV — enregistre un vol d\'arrivée (jet)' },
        { '/stoprecarrivage',  'DEV — stoppe + sauve le vol' },
        { '/startrecbus',      'DEV — enregistre le trajet du bus (airbus)' },
        { '/stoprecbus',       'DEV — stoppe + sauve le trajet bus' },
        { '/arrival',          'DEV — rejoue l\'arrivée (avion + bus). /arrival N simule un batch de N' },
        { '/queuejoin',        'DEV — rejoins la file d\'arrivée (test du batch/départ)' },
        { '/queuestatus',      'DEV — affiche la file d\'arrivée en attente' },
        { '/charcreate',       'DEV — ré-ouvre la création de perso' },
        { '/charselect',       'DEV — ré-ouvre la sélection de perso' },
        { '/resume',           'DEV — rejoue la reprise au dernier point' },
        { '/customize',        'DEV — ré-ouvre le créateur d\'apparence' },
        { '/deletechar',       'DEV — supprime ton/tes perso(s) et repart de zéro' },
        { '/here',             'DEV — affiche tes coords + heading' },
    }
    for _, s in ipairs(sug) do
        TriggerEvent('chat:addSuggestion', s[1], s[2])
    end
end)
