--[[
    sl_phone/client/main.lua — open/close + NUI bridge + call focus + phone-in-hand anim.

    The phone grabs the MOUSE (cursor) but keeps game input (SetNuiFocusKeepInput) so the
    player can still WALK and DRIVE while it's open — only conflicting controls (weapons /
    chat / pause) are blocked, plus movement is blocked ONLY while typing in a field (so
    WASD doesn't leak into the game). Opening plays a "raise phone" animation + attaches a
    phone prop to the hand; closing plays the put-away animation. An incoming call auto-opens
    the phone, and it can't be closed mid-call (use Hangup).
]]

local isOpen = false
local nuiReady = false
local pending = {}
local inCall = false          -- a call UI is active (incoming/outgoing/active)
local openedForCall = false   -- the phone was auto-opened just to handle a call
local typing = false          -- a text field in the NUI is focused (block movement leak)
local guardRunning = false
local prop = nil
local cameraMode = false      -- the in-game camera viewfinder is active
local stopCamera              -- forward declaration (defined below)

local function send(action, data)
    if nuiReady then
        SendNUIMessage({ action = action, data = data })
    else
        pending[#pending + 1] = { action = action, data = data }
    end
end

-- ── phone prop + animation ───────────────────────────────────────────────────────
local function ensureAnim(dict)
    if HasAnimDictLoaded(dict) then return end
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) and t < 1000 do Wait(10); t = t + 10 end
end

local function attachProp()
    if prop and DoesEntityExist(prop) then return end
    local ped = PlayerPedId()
    local model = GetHashKey(Config.Hand.prop)
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) and t < 1000 do Wait(10); t = t + 10 end
    if not HasModelLoaded(model) then return end
    local c = GetEntityCoords(ped)
    prop = CreateObject(model, c.x, c.y, c.z, true, true, false)
    local o, r = Config.Hand.pos, Config.Hand.rot
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, Config.Hand.bone),
        o.x, o.y, o.z, r.x, r.y, r.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

local function removeProp()
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    prop = nil
end

-- Keep the "looking at phone" loop going on foot; in a vehicle just hold the prop (no anim).
local function startPhoneAnim()
    attachProp()
    CreateThread(function()
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            ensureAnim(Config.Hand.dict)
            TaskPlayAnim(ped, Config.Hand.dict, Config.Hand.inAnim, 3.0, 3.0, -1, 50, 0, false, false, false)
            Wait(850)
        end
        while isOpen do
            ped = PlayerPedId()
            if not cameraMode and not IsPedInAnyVehicle(ped, false)
                and not IsEntityPlayingAnim(ped, Config.Hand.dict, Config.Hand.holdAnim, 3) then
                ensureAnim(Config.Hand.dict)
                -- flag 49 = loop + upperbody + allow movement
                TaskPlayAnim(ped, Config.Hand.dict, Config.Hand.holdAnim, 3.0, 3.0, -1, 49, 0, false, false, false)
            end
            Wait(400)
        end
    end)
end

local function stopPhoneAnim()
    CreateThread(function()
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            ensureAnim(Config.Hand.dict)
            TaskPlayAnim(ped, Config.Hand.dict, Config.Hand.outAnim, 3.0, 3.0, -1, 50, 0, false, false, false)
            Wait(550)
            if not isOpen then ClearPedTasks(ped) end
        end
        if not isOpen then removeProp() end
    end)
end

-- ── input guard (lets you move/drive; blocks weapons/chat; blocks movement while typing) ──
local OPEN_SUPPRESS = {
    1, 2,                     -- mouse look (camera stays frozen — mouse only drives the cursor)
    199, 200,                 -- pause / ESC (React handles ESC)
    245, 246,                 -- text chat
    24, 25, 257,              -- attack / aim
    263, 264, 140, 141, 142,  -- melee
    37, 47,                   -- weapon wheel / detonate
    14, 15, 16, 17,           -- weapon select
    45,                       -- reload
    27,                       -- native phone
    44,                       -- cover
}
-- additionally blocked ONLY while a text field is focused, so keystrokes don't leak as
-- movement/driving — the player gets full control back the moment the field is blurred.
local TYPING_SUPPRESS = {
    30, 31, 32, 33, 34, 35,               -- move
    21, 22, 36, 23,                       -- sprint / jump / duck / enter
    71, 72, 75, 76, 59, 60, 63, 64,       -- vehicle accel/brake/exit/handbrake/steer
}

local function startGuard()
    if guardRunning then return end
    guardRunning = true
    CreateThread(function()
        while isOpen do
            if not cameraMode then
                for i = 1, #OPEN_SUPPRESS do DisableControlAction(0, OPEN_SUPPRESS[i], true) end
                if typing then
                    for i = 1, #TYPING_SUPPRESS do DisableControlAction(0, TYPING_SUPPRESS[i], true) end
                end
            end
            Wait(0)
        end
        guardRunning = false
    end)
end

-- ── camera (scripted-cam viewfinder: you ARE the lens — aim with the mouse, scroll to zoom) ──
local cam = nil
local camHeading, camPitch, camFov, selfie = 0.0, 0.0, 50.0, false
local PHOTO_ANIM = 'cellphone_photo_idle' -- "holding the phone up to take a photo" pose

local function headPos()
    return GetPedBoneCoords(PlayerPedId(), 31086, 0.0, 0.0, 0.0) -- SKEL_Head
end

local function startCamera()
    if cameraMode then return end
    cameraMode = true
    SetNuiFocus(false, false)  -- no cursor: the mouse aims the lens
    SetNuiFocusKeepInput(false)

    local gr = GetGameplayCamRot(2)
    camPitch, camHeading, camFov, selfie = gr.x, gr.z, 50.0, false

    local hp = headPos()
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', hp.x, hp.y, hp.z, camPitch, 0.0, camHeading, camFov, false, 2)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    ensureAnim(Config.Hand.dict)
    TaskPlayAnim(PlayerPedId(), Config.Hand.dict, PHOTO_ANIM, 3.0, 3.0, -1, 49, 0, false, false, false)

    CreateThread(function()
        while cameraMode do
            DisableAllControlActions(0)
            HideHudAndRadarThisFrame() -- no HUD / minimap in the viewfinder or the photo
            local ped = PlayerPedId()
            -- hide our OWN ped locally in rear mode (others still see us); keep visible for selfie
            if not selfie then
                SetEntityLocallyInvisible(ped)
                if prop and DoesEntityExist(prop) then SetEntityLocallyInvisible(prop) end
            end
            -- aim (mouse) + zoom (scroll: 15 up/in, 14 down/out) + selfie flip (RMB) + ratio (G)
            camHeading = camHeading - GetDisabledControlNormal(0, 1) * 6.0
            camPitch = math.max(-80.0, math.min(80.0, camPitch - GetDisabledControlNormal(0, 2) * 6.0))
            if IsDisabledControlPressed(0, 15) then camFov = math.max(20.0, camFov - 2.0) end
            if IsDisabledControlPressed(0, 14) then camFov = math.min(70.0, camFov + 2.0) end
            if IsDisabledControlJustPressed(0, 25) then selfie = not selfie end
            if IsDisabledControlJustPressed(0, 47) then SendNUIMessage({ action = 'camera:toggleMode', data = {} }) end -- G = paysage/portrait
            -- keep the photo pose
            if not IsEntityPlayingAnim(ped, Config.Hand.dict, PHOTO_ANIM, 3) then
                TaskPlayAnim(ped, Config.Hand.dict, PHOTO_ANIM, 3.0, 3.0, -1, 49, 0, false, false, false)
            end
            -- place the lens at the head, pushed forward past the arm (or in front for selfie)
            local hp2 = headPos()
            local hr, pr = math.rad(camHeading), math.rad(camPitch)
            local fx, fy, fz = -math.sin(hr) * math.cos(pr), math.cos(hr) * math.cos(pr), math.sin(pr)
            if selfie then
                SetCamCoord(cam, hp2.x + fx * 0.8, hp2.y + fy * 0.8, hp2.z + fz * 0.8 + 0.05)
                SetCamRot(cam, -camPitch, 0.0, camHeading + 180.0, 2)
            else
                SetCamCoord(cam, hp2.x + fx * 0.3, hp2.y + fy * 0.3, hp2.z + 0.08)
                SetCamRot(cam, camPitch, 0.0, camHeading, 2)
            end
            SetCamFov(cam, camFov)
            -- shutter / exit
            if IsDisabledControlJustPressed(0, 24) then -- LMB
                SendNUIMessage({ action = 'camera:flash', data = {} })
                exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = 0.9 }, function(img)
                    SendNUIMessage({ action = 'camera:captured', data = { image = img } })
                end)
                Wait(500)
            elseif IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) then -- ESC / Backspace
                stopCamera()
            end
            Wait(0)
        end
    end)
end

stopCamera = function()
    if not cameraMode then return end
    cameraMode = false
    RenderScriptCams(false, false, 0, true, true)
    if cam then DestroyCam(cam, false); cam = nil end
    ClearPedTasks(PlayerPedId()) -- drop the photo pose; the hold-loop re-applies the normal pose
    if isOpen then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true)
        startGuard()
    end
    SendNUIMessage({ action = 'camera:closed', data = {} })
end

-- ── open / close ───────────────────────────────────────────────────────────────
local function doOpen(state)
    isOpen = true
    SetNuiFocus(true, true)        -- cursor for the touch UI…
    SetNuiFocusKeepInput(true)     -- …but the game still gets keyboard, so you can walk/drive
    startGuard()
    startPhoneAnim()
    send('phone:open', state)
end

local function openPhone()
    if isOpen then return end
    local res = lib.callback.await('sl_phone:rpc', false, { method = 'open' })
    if not res or not res.ok then
        local msg = (res and res.reason == 'NO_PHONE') and "Vous n'avez pas de téléphone." or 'Téléphone indisponible.'
        exports.sl_ui:notify('error', msg)
        return
    end
    doOpen(res.state)
end

local function closePhone()
    if not isOpen then return end
    isOpen = false
    openedForCall = false
    typing = false
    cameraMode = false -- stops the camera loop if it was running
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    stopPhoneAnim()
end

-- open (with focus) specifically to show a call, even if the phone was closed.
local function ensureOpenForCall()
    if isOpen then return end
    local res = lib.callback.await('sl_phone:rpc', false, { method = 'open' })
    openedForCall = true
    doOpen((res and res.ok and res.state) or { uuid = '', number = '', settings = {}, apps = {}, dock = {} })
end

-- ── NUI callbacks (React -> Lua) ────────────────────────────────────────────────
RegisterNUICallback('uiReady', function(_, cb)
    nuiReady = true
    for _, m in ipairs(pending) do SendNUIMessage({ action = m.action, data = m.data }) end
    pending = {}
    cb({ ok = true })
end)

RegisterNUICallback('phone:close', function(_, cb)
    if not inCall then closePhone() end -- can't close mid-call (Hangup ends it)
    cb({ ok = true })
end)

-- Hard release of focus, used by the React error boundary so a UI crash never leaves the
-- player with a stuck cursor / locked controls (even during a call).
RegisterNUICallback('phone:forceClose', function(_, cb)
    inCall = false
    closePhone()
    cb({ ok = true })
end)

-- React tells us when a text field is focused so we block movement leak while typing.
RegisterNUICallback('phone:typing', function(data, cb)
    typing = data and data.on == true
    cb({ ok = true })
end)

-- The Camera app (route 'camera') signals us to enter the in-game viewfinder.
RegisterNUICallback('camera:start', function(_, cb)
    startCamera()
    cb({ ok = true })
end)

RegisterNUICallback('rpc', function(data, cb)
    local res = lib.callback.await('sl_phone:rpc', false, data)
    cb(res or { ok = false })
end)

-- Relay for the Société app: forwards { method, params } to the sl_shops server callback so the
-- phone can show company stock + bill a customer without sl_phone owning any shop logic.
RegisterNUICallback('shopsRpc', function(data, cb)
    if GetResourceState('sl_shops') ~= 'started' then cb({ ok = false, reason = 'NO_SHOP' }); return end
    local res = lib.callback.await('sl_shops:rpc', false, { method = data.method, params = data.params })
    cb(res or { ok = false })
end)

-- Relay for the "Véhicules/Clés" + "Annuaire" apps: forwards { method, params } to sl_vehicles:rpc
-- (remote lock/locate/engine/trunk/share, the company directory + contact form).
RegisterNUICallback('vehiclesRpc', function(data, cb)
    if GetResourceState('sl_vehicles') ~= 'started' then cb({ ok = false, reason = 'NO_VEH' }); return end
    local res = lib.callback.await('sl_vehicles:rpc', false, { method = data.method, params = data.params })
    cb(res or { ok = false })
end)

-- ── server pushes (real-time) ────────────────────────────────────────────────────
RegisterNetEvent('sl_phone:callIncoming', function(data)
    inCall = true
    if cameraMode then stopCamera() end -- leave the viewfinder so the call screen is visible/answerable
    ensureOpenForCall()
    send('phone:call', { event = 'incoming', call = data })
end)
RegisterNetEvent('sl_phone:callOutgoing', function(data)
    inCall = true
    send('phone:call', { event = 'outgoing', call = data })
end)
RegisterNetEvent('sl_phone:callAccepted', function(data)
    send('phone:call', { event = 'accepted', call = data })
end)
RegisterNetEvent('sl_phone:callEnded', function(data)
    inCall = false
    send('phone:call', { event = 'ended', call = data })
    if openedForCall then
        SetTimeout(1500, function()
            if not inCall and openedForCall then
                openedForCall = false
                if isOpen then closePhone(); send('phone:close', {}) end
            end
        end)
    end
end)
RegisterNetEvent('sl_phone:sms', function(data) send('phone:sms', data) end)
RegisterNetEvent('sl_phone:notify', function(data) send('phone:notify', data) end)

-- ── open triggers ───────────────────────────────────────────────────────────────
RegisterCommand('sl_phone_toggle', function()
    if cameraMode then stopCamera(); return end -- exit the viewfinder first
    if isOpen then
        if inCall then return end
        closePhone(); send('phone:close', {})
    else
        openPhone()
    end
end, false)
RegisterKeyMapping('sl_phone_toggle', 'Ouvrir le téléphone', 'keyboard', Config.OpenKey)

RegisterNetEvent('sl_inventory:onUse', function(name)
    if name == Config.Item then openPhone() end
end)

-- ── exports (other resources) ─────────────────────────────────────────────────
exports('OpenPhone', openPhone)
exports('ClosePhone', function() if isOpen and not inCall then closePhone(); send('phone:close', {}) end end)
exports('IsPhoneOpen', function() return isOpen end)
exports('HasPhoneItem', function() return lib.callback.await('sl_phone:hasPhone', false) == true end)
exports('getCoins', function() return Config.Coins end) -- coin catalogue for menus (e.g. F10 admin)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
        removeProp()
    end
end)
