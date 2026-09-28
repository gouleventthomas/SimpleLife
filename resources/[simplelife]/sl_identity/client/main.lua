--[[
    client/main.lua — sl_identity client: anti-spawn hold, NUI routing, resume.

    Reliability spine:
      - From the EARLIEST tick we hold the ped frozen + invisible + faded-out so the
        default GTA spawn never shows. We KEEP re-applying it until a spawn is handed
        over (resume or arrival completes).
      - We wait (bounded) for the session + sl_core, then tell the server we're ready.
      - Resume / arrival each END with the player CONTROLLABLE, VISIBLE, faded-in.

    NUI contract (matches sl_ui/client/bridge.lua + the locked protocol):
      Server -> client:  'sl_identity:openSelect' {chars,cap}
                         'sl_identity:openCreate' {canCancel}
                         'sl_identity:resume'     {model,coords}
                         'sl_identity:arrival'    {model,seat,batch}
                         'sl_identity:createError'{reason}
      React  -> bridge -> 'sl_ui:nui' event:
                         'identity:select'      {id}
                         'identity:create'      {firstname,lastname,dob,gender}
                         'identity:newchar'     (open create from select)
                         'identity:cancelCreate'(back to select)
]]

-- Shared client state for this resource (single Lua state on the client).
local spawnHandled = false   -- flips true once resume/arrival has placed the player
local arrivalActive = false  -- true while the arrival cinematic owns the ped (hold thread stands down)
local customizeActive = false -- true while the fivem-appearance creator owns the ped/cam (hold stands down)
local haveChars    = false   -- whether the player has >=1 character (drives create cancel)
local lastSelectPayload = nil -- cached charselect payload so cancelCreate can reopen it

-- 1b queue wait state: while enqueued for a shared flight the player stays in the existing
-- safe hold (frozen/invisible/black); we only draw a countdown on top until the flight departs.
local queued     = false
local queueEtaMs = 0
local queueCount = 1
local queueStamp = 0

-- Exposed to client/arrival.lua (same Lua state, resource-global) so the cinematic
-- can flip the spawn latch when it finishes.
SLIdentity = SLIdentity or {}
function SLIdentity.markSpawned()
    spawnHandled = true
end
function SLIdentity.isSpawned()
    return spawnHandled
end

-- Arrival cinematic latch. While TRUE, the anti-spawn hold thread MUST stand down:
-- the cinematic owns the ped (it seats the player in the plane, runs its own cam,
-- and fades the screen IN so the descent is visible). If the hold thread kept
-- running it would, every frame, re-hide + re-freeze the ped, yank it back to
-- HoldCoord (ripping it out of the plane seat), and re-DoScreenFadeOut(0) — which
-- would black out the entire cinematic and make arrival.lua's DoScreenFadeIn a
-- no-op. The cinematic sets this true before it touches the ped and clears it in a
-- finally-style guard so the hold can never be left disarmed without a spawn.
function SLIdentity.setArrivalActive(v)
    arrivalActive = v and true or false
end
function SLIdentity.isArrivalActive()
    return arrivalActive == true
end

-- Customization latch: the fivem-appearance creator owns the ped + camera + NUI while a
-- NEW character is being made (before the plane). The hold thread stands down for it too,
-- exactly like the arrival. Cleared by releaseToPlayer() at the end of the arrival.
function SLIdentity.setCustomizeActive(v)
    customizeActive = v and true or false
end
function SLIdentity.isCustomizeActive()
    return customizeActive == true
end

-- ── anti default-spawn hold ───────────────────────────────────────────────────
-- Keep the ped hidden + frozen + controls off until a spawn is handed over. This
-- runs every frame at start and stops the instant spawnHandled flips. It is the
-- guaranteed "never show the vanilla spawn" gate.
CreateThread(function()
    -- Black the screen immediately, before anything renders.
    DoScreenFadeOut(0)
    while not spawnHandled do
        -- While the arrival cinematic owns the ped, stand down completely: do NOT
        -- re-hide / re-freeze / re-teleport / re-fade-out. Otherwise we'd fight the
        -- cinematic every frame (rip the player out of the plane seat back to
        -- HoldCoord and black out the descent the player is supposed to SEE).
        if not arrivalActive and not customizeActive then
            local ped = PlayerPedId()
            SetEntityVisible(ped, false, false)
            FreezeEntityPosition(ped, true)
            SetPlayerControl(PlayerId(), false, 0)
            SetEntityCoordsNoOffset(ped, Config.HoldCoord.x, Config.HoldCoord.y, Config.HoldCoord.z, false, false, false)
            SetEntityInvincible(ped, true)
            -- Keep us from dying / drowning while parked in the sky.
            SetPlayerInvincible(PlayerId(), true)
            if not IsScreenFadedOut() and not IsScreenFadingOut() then
                DoScreenFadeOut(0)
            end
        end
        Wait(0)
    end
end)

-- Also clear NUI focus defensively if something left it stuck before we own the flow.
CreateThread(function()
    SetNuiFocus(false, false)
end)

-- ── 1b: arrival-queue countdown (server-driven) ───────────────────────────────
-- While enqueued for a shared flight, the server pushes 'sl_identity:queueTick'. We do NOT
-- touch the hold latches — the player stays safely held (frozen/invisible/black) exactly as
-- before; we just paint a countdown over the black so the wait isn't a blank screen.
RegisterNetEvent('sl_identity:queueTick', function(data)
    queued     = true
    queueEtaMs = (data and tonumber(data.etaMs)) or 0
    queueCount = (data and tonumber(data.count)) or 1
    queueStamp = GetGameTimer()
end)

CreateThread(function()
    while true do
        if queued and not spawnHandled and not arrivalActive and not customizeActive then
            local remain = queueEtaMs - (GetGameTimer() - queueStamp)
            if remain < 0 then remain = 0 end
            local secs = math.floor(remain / 1000)
            local line1 = (queueCount and queueCount > 1)
                and ('En attente d\'autres arrivants — %d à bord'):format(queueCount)
                or  'Préparation de votre arrivée…'
            local line2 = ('Départ dans ~%ds'):format(secs)

            SetTextFont(4); SetTextScale(0.55, 0.55); SetTextColour(255, 255, 255, 255)
            SetTextCentre(true); SetTextOutline()
            BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(line1)
            EndTextCommandDisplayText(0.5, 0.45)

            SetTextFont(4); SetTextScale(0.42, 0.42); SetTextColour(200, 200, 200, 255)
            SetTextCentre(true); SetTextOutline()
            BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(line2)
            EndTextCommandDisplayText(0.5, 0.51)
            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- ── own the initial spawn ─────────────────────────────────────────────────────
-- basic-gamemode is disabled, so NOTHING auto-spawns the player. We take ownership:
-- disable spawnmanager auto-spawn and force ONE spawn at the hidden hold coord, so we
-- have a valid ped to hold until the identity flow (resume/arrival) hands over the real
-- spawn. skipFade keeps our own black screen; the hold thread above re-hides it instantly.
CreateThread(function()
    while GetResourceState('spawnmanager') ~= 'started' do Wait(50) end
    exports.spawnmanager:setAutoSpawn(false)
    while not NetworkIsSessionStarted() do Wait(50) end
    exports.spawnmanager:spawnPlayer({
        x = Config.HoldCoord.x,
        y = Config.HoldCoord.y,
        z = Config.HoldCoord.z,
        heading = 0.0,
        model = 'mp_m_freemode_01',
        skipFade = true,
    })
    Config.Log('info', 'initial spawn forced at hold coord (autospawn disabled)')
end)

-- ── readiness: tell the server we're ready ────────────────────────────────────
CreateThread(function()
    -- Wait for the session to start (bounded — proceed anyway so we never hang).
    local waited = 0
    while not NetworkIsSessionStarted() and waited < Config.Timeouts.sessionReady do
        Wait(100)
        waited = waited + 100
    end

    -- Wait for sl_core readiness (replicated GlobalState). Bounded; proceed anyway.
    waited = 0
    while GlobalState.slCoreReady ~= true and waited < Config.Timeouts.coreReady do
        Wait(100)
        waited = waited + 100
    end

    if GlobalState.slCoreReady ~= true then
        Config.Log('warn', 'core not ready in time — signalling clientReady anyway')
    end

    TriggerServerEvent('sl_identity:clientReady')
    Config.Log('info', 'clientReady sent')
end)

-- ── NUI screen openers (server-driven) ────────────────────────────────────────
RegisterNetEvent('sl_identity:openSelect', function(payload)
    haveChars = (payload and payload.chars and #payload.chars > 0) or false
    lastSelectPayload = payload
    exports.sl_ui:open('charselect', payload)
end)

RegisterNetEvent('sl_identity:openCreate', function(payload)
    -- canCancel comes from the server for the first-open case; for the in-NUI
    -- "new arrival" button we recompute it from haveChars.
    local canCancel = (payload and payload.canCancel) or false
    exports.sl_ui:open('charcreate', { canCancel = canCancel })
end)

RegisterNetEvent('sl_identity:createError', function(payload)
    local reason = (payload and payload.reason) or 'UNKNOWN'
    exports.sl_ui:notify('error', ('Could not create character (%s).'):format(reason))
    -- Re-open the create screen so the player can correct and retry.
    exports.sl_ui:open('charcreate', { canCancel = haveChars })
end)

-- ── NUI -> client routing (from sl_ui bridge generic dispatch) ────────────────
AddEventHandler('sl_ui:nui', function(event, data)
    if event == 'identity:select' then
        TriggerServerEvent('sl_identity:select', { id = data and data.id })

    elseif event == 'identity:create' then
        TriggerServerEvent('sl_identity:create', {
            firstname = data and data.firstname,
            lastname  = data and data.lastname,
            dob       = data and data.dob,
            gender    = data and data.gender,
        })

    elseif event == 'identity:newchar' then
        -- Player clicked "new arrival" on charselect — open create with cancel
        -- enabled (they already have at least one character to go back to).
        exports.sl_ui:open('charcreate', { canCancel = haveChars })

    elseif event == 'identity:cancelCreate' then
        -- Back to charselect (only meaningful if they have chars; reopen cached payload).
        if lastSelectPayload then
            exports.sl_ui:open('charselect', lastSelectPayload)
        else
            -- No cached list (shouldn't happen if cancel was offered) — ask server.
            TriggerServerEvent('sl_identity:clientReady')
        end
    end
end)

-- ── model application helper (bounded) ────────────────────────────────────────
-- Shared by resume (here) and arrival (client/arrival.lua, via SLIdentity.applyModel).
---@param model string|number
---@return boolean ok
local function applyModel(model)
    if not model then return false end
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        Config.Log('warn', ('applyModel: invalid model %s — keeping current ped'):format(tostring(model)))
        return false
    end
    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < Config.Timeouts.model do
        Wait(50)
        waited = waited + 50
    end
    if not HasModelLoaded(hash) then
        Config.Log('warn', ('applyModel: model %s did not load in time — keeping current ped'):format(tostring(model)))
        return false
    end
    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)
    -- Default component variation so freemode peds aren't invisible/naked-mesh.
    SetPedDefaultComponentVariation(PlayerPedId())
    -- Default head BLEND so hair / eyebrow / beard COLORS resolve. Without a valid head
    -- blend a freshly-modeled freemode ped renders hair + overlays as the engine's
    -- missing-texture FLUO GREEN the moment you change their colour.
    SetPedHeadBlendData(PlayerPedId(), 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)
    return true
end
SLIdentity.applyModel = applyModel

-- ── teleport with bounded collision load ──────────────────────────────────────
-- Returns the ped placed at coords with collision loaded (or after timeout anyway).
---@param coord vector3|table
---@param heading number
local function teleportWithCollision(coord, heading)
    local x = coord.x or coord[1]
    local y = coord.y or coord[2]
    local z = coord.z or coord[3]
    local ped = PlayerPedId()

    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    SetEntityHeading(ped, heading or 0.0)
    FreezeEntityPosition(ped, true)

    local waited = 0
    while not HasCollisionLoadedAroundEntity(ped) and waited < Config.Timeouts.collision do
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
        waited = waited + 50
    end
    -- Whether or not collision finished, place again to be safe and unfreeze later.
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    SetEntityHeading(ped, heading or 0.0)
end

-- ── hand control back to the player (the guaranteed end-state) ────────────────
-- Every path (resume, arrival success, arrival fallback) funnels through here.
local function releaseToPlayer()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityCollision(ped, true, true)
    arrivalActive = false      -- cinematic (if any) is done owning the ped
    customizeActive = false    -- creator (if any) is done owning the ped
    SLIdentity.markSpawned()   -- stops the anti-spawn hold thread
    TriggerServerEvent('sl_core:playerSpawned')  -- sl_core now captures this player's position (déco/reco)
    exports.sl_ui:close()
    -- Guarantee a clean, fully-faded-in screen. If a fade is mid-flight, give it a
    -- bounded window to settle before forcing the fade-in, so we can never leave the
    -- player on a partially-black screen (belt-and-braces over the descent fade).
    local guard = 0
    while IsScreenFadingOut() and guard < 1000 do
        Wait(50)
        guard = guard + 50
    end
    DoScreenFadeIn(800)
end
SLIdentity.releaseToPlayer = releaseToPlayer

-- ── CUSTOMIZE: open the fivem-appearance creator (new character, before the plane) ──
RegisterNetEvent('sl_identity:customize', function(payload)
    local model = payload and payload.model
    customizeActive = true        -- hold thread stands down; the creator owns ped + cam
    exports.sl_ui:close()         -- close the charcreate form + release sl_ui's NUI focus first
    applyModel(model)             -- a freemode ped is required for full customization

    -- Place the ped on a clean ground spot so the creator camera frames it nicely.
    local cc = Config.CustomizeCoord
    teleportWithCollision(cc.coord, cc.heading)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), false, 0)
    DoScreenFadeIn(500)

    -- If fivem-appearance isn't running, don't strand the player — arrive without a creator.
    if GetResourceState('fivem-appearance') ~= 'started' then
        Config.Log('error', 'customize: fivem-appearance not started — arriving without customization')
        TriggerServerEvent('sl_identity:appearanceSaved', nil)
        return
    end

    -- The creator manages its own camera/NUI/ped; cb fires on save. allowExit=false so the
    -- player must finish. Keep customizeActive true — the arrival (server's next step) takes
    -- over and releaseToPlayer() clears both latches.
    exports['fivem-appearance']:startPlayerCustomization(function(appearance)
        if not appearance then
            appearance = exports['fivem-appearance']:getPedAppearance(PlayerPedId())
        end
        TriggerServerEvent('sl_identity:appearanceSaved', appearance)
    end, {
        ped = true, headBlend = true, faceFeatures = true,
        headOverlays = true, components = true, props = true,
        tattoos = false, allowExit = false,
    })
end)

-- ── RESUME an existing character (no plane) ───────────────────────────────────
RegisterNetEvent('sl_identity:resume', function(payload)
    local model  = payload and payload.model
    local coords = (payload and payload.coords) or {}
    local appearance = payload and payload.appearance

    -- Apply the saved appearance (it INCLUDES the model). Fall back to just the model for
    -- characters never customized (applyModel alone would reset to a default look).
    if appearance and GetResourceState('fivem-appearance') == 'started' then
        exports['fivem-appearance']:setPlayerAppearance(appearance)
    else
        applyModel(model)
    end

    -- Resolve coords; fall back to a known-good spawn if the char has none.
    local hasCoords = coords and (coords.x or coords[1])
    local targetCoord, targetHeading
    if hasCoords then
        targetCoord  = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
        targetHeading = coords.heading or coords.w or coords[4] or 0.0
    else
        targetCoord   = Config.FallbackSpawn.coord
        targetHeading = Config.FallbackSpawn.heading
        Config.Log('warn', 'resume: char had no coords — using FallbackSpawn')
    end

    teleportWithCollision(targetCoord, targetHeading)

    -- ALWAYS end controllable, even if collision timed out.
    releaseToPlayer()
    exports.sl_ui:notify('info', 'Welcome back.')
    Config.Log('info', 'resume complete — player controllable')
end)

-- ── ARRIVAL: hand off to the cinematic (client/arrival.lua) ───────────────────
RegisterNetEvent('sl_identity:arrival', function(payload)
    queued = false  -- the flight is departing; stop the queue countdown overlay
    -- arrival.lua reads SLIdentity helpers (applyModel / releaseToPlayer / hold latch).
    if SLIdentity.runArrival then
        -- Protect the cinematic: it sets the arrival latch (which disarms the hold
        -- thread). If ANY native inside it errors before finish() runs, the latch
        -- could be left set with spawnHandled false — a softlock (frozen/invisible/
        -- black). pcall guarantees we always recover: clear the latch and force a
        -- safe disembark release so the player ends controllable no matter what.
        local ok, err = pcall(SLIdentity.runArrival, payload)
        if not ok then
            Config.Log('error', ('arrival cinematic errored — safe disembark fallback: %s'):format(tostring(err)))
            arrivalActive = false
            applyModel(payload and payload.model)
            teleportWithCollision(Config.DisembarkPoint.coord, Config.DisembarkPoint.heading)
            releaseToPlayer()
            exports.sl_ui:notify('info', 'Los Santos.')
        end
    else
        -- Defensive: cinematic file missing/failed to load — do a safe fade-in spawn
        -- at the disembark point so the player is never stranded.
        Config.Log('error', 'arrival handler missing — falling back to disembark teleport')
        applyModel(payload and payload.model)
        teleportWithCollision(Config.DisembarkPoint.coord, Config.DisembarkPoint.heading)
        releaseToPlayer()
        exports.sl_ui:notify('info', 'Los Santos.')
    end
end)

-- ── WIPE: dev /deletechar — fade to black, then re-enter the identity flow (create) ──
RegisterNetEvent('sl_identity:wipe', function()
    DoScreenFadeOut(400)
    Wait(450)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetPlayerControl(PlayerId(), false, 0)
    -- 0 character left -> the server's openEntry will open the create screen (over black).
    -- create -> customize unfreezes + fades in at CustomizeCoord -> arrival.
    TriggerServerEvent('sl_identity:clientReady')
end)

-- ── dev: /here prints your coords + heading (to calibrate placeholder coords) ──
RegisterCommand('here', function()
    if GlobalState.slCoreEnv ~= 'dev' then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local s = ('vector3(%.1f, %.1f, %.1f)  heading=%.1f'):format(c.x, c.y, c.z, h)
    print('^4[sl_identity]^7 ' .. s)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(s)
    EndTextCommandThefeedPostTicker(false, false)
end, false)

-- ── safety net: if this resource stops mid-flow, never leave the player stuck ──
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerControl(PlayerId(), true, 0)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetNuiFocus(false, false)
    if IsScreenFadedOut() then DoScreenFadeIn(0) end
end)
