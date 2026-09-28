--[[
    client/main.lua — sl_inventory client.

    TAB opens the player's grid (modal: cursor for drag&drop). Every op (move / use / drop /
    give) round-trips to the server (authoritative) and the returned state is pushed back to
    the open grid. Ground drops broadcast from the server become local bag props with an
    ox_target (via sl_interact) that opens a 2-grid container view.
]]

local invOpen = false
local currentContainer = nil  -- drop id currently being viewed (or nil)
local dropEntities = {}        -- dropId -> local prop entity
local cam = nil                -- character-preview camera
local invHeading = 0.0         -- the ped heading while previewing (mouse-rotatable)

local function notify(kind, msg) exports.sl_ui:notify(kind, msg) end

-- Front-framed camera on the player's ped, so the (transparent) middle column shows the
-- real character behind the inventory. Rotating drags the ped's heading, not the camera.
local function setupCam()
    if cam then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    invHeading = GetEntityHeading(ped)
    local fwd = GetEntityForwardVector(ped)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        c.x + fwd.x * 1.9, c.y + fwd.y * 1.9, c.z + 0.15, 0.0, 0.0, 0.0, 42.0, false, 0)
    PointCamAtEntity(cam, ped, 0.0, 0.0, 0.1, true)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end

local function clearCam()
    if not cam then return end
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    cam = nil
end

local function pushUpdate(res)
    if not res or not res.player then return end
    -- use/give return only { player } (no container). ALWAYS re-resolve the right panel when it
    -- is absent — getState(currentContainer) is nil-safe (returns the Sol when no bag is open, the
    -- bag when one is). Without this the right panel would arrive as nil and crash the React grid.
    local container = res.container
    if container == nil then
        local r2 = lib.callback.await('sl_inventory:getState', false, currentContainer)
        container = r2 and r2.container
    end
    exports.sl_ui:updateInventory({ player = res.player, container = container, accent = Config.Accent })
end

local function openWith(containerId)
    local res = lib.callback.await('sl_inventory:getState', false, containerId)
    if not res or not res.player then return false end
    invOpen = true
    currentContainer = containerId
    setupCam()
    exports.sl_ui:openInventory({ player = res.player, container = res.container, accent = Config.Accent })
    return true
end

local function closeInv()
    if not invOpen then return end
    invOpen = false
    currentContainer = nil
    clearCam()
    exports.sl_ui:close()
end

-- give the FULL stack to the nearest player in range (v1).
local function doGive(slot)
    local near = lib.callback.await('sl_inventory:nearbyPlayers', false) or {}
    if #near == 0 then notify('error', 'Personne à proximité.'); return end
    local res = lib.callback.await('sl_inventory:give', false, { slot = slot, target = near[1].id })
    if res and res.ok then notify('success', 'Donné à ' .. near[1].name)
    else notify('error', 'Don impossible (' .. tostring(res and res.reason) .. ').') end
    if res then pushUpdate(res) end
end

-- ── op dispatch from the inventory UI ─────────────────────────────────────────
AddEventHandler('sl_ui:nui', function(event, data)
    if event == 'inv:close' then
        closeInv()
    elseif event == 'inv:move' then
        local res = lib.callback.await('sl_inventory:move', false, data)
        pushUpdate(res)
    elseif event == 'inv:use' then
        local res = lib.callback.await('sl_inventory:use', false, data)  -- data = slot (number)
        pushUpdate(res)
    elseif event == 'inv:drop' then
        local res = lib.callback.await('sl_inventory:drop', false, data)
        pushUpdate(res)
    elseif event == 'inv:give' then
        doGive(data and data.slot)
    elseif event == 'inv:rotate' then
        if invOpen and cam then
            invHeading = (invHeading - (tonumber(data and data.delta) or 0)) % 360.0
            SetEntityHeading(PlayerPedId(), invHeading)
        end
    end
end)

-- ── server pushes ─────────────────────────────────────────────────────────────
RegisterNetEvent('sl_inventory:notify', function(kind, msg) notify(kind, msg) end)

RegisterNetEvent('sl_inventory:refresh', function()
    if not invOpen then return end
    local res = lib.callback.await('sl_inventory:getState', false, currentContainer)
    pushUpdate(res)
end)

RegisterNetEvent('sl_inventory:onUse', function(_name)
    -- v1: hook point for per-item animations / effects (eat / drink / etc.)
end)

-- ── ground drops (bags) ───────────────────────────────────────────────────────
RegisterNetEvent('sl_inventory:dropCreated', function(id, coords)
    if dropEntities[id] then return end
    CreateThread(function()
        local hash = GetHashKey(Config.DropModel)
        RequestModel(hash)
        local w = 0
        while not HasModelLoaded(hash) and w < 4000 do Wait(50); w = w + 50 end
        if not HasModelLoaded(hash) then return end
        local obj = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
        dropEntities[id] = obj
        exports.sl_interact:addLocalEntity(obj, {
            { label = 'Ouvrir le sac', icon = 'fa-solid fa-bag-shopping', distance = 2.0,
              onSelect = function() openWith(id) end },
        })
    end)
end)

RegisterNetEvent('sl_inventory:dropRemoved', function(id)
    -- if we're viewing this bag, close it
    if invOpen and currentContainer == id then closeInv() end
    local obj = dropEntities[id]
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end  -- deleting the entity drops its ox_target too
    dropEntities[id] = nil
end)

-- ── open key (TAB) ────────────────────────────────────────────────────────────
RegisterCommand('sl_inv_toggle', function()
    if invOpen then closeInv() else openWith(nil) end
end, false)
RegisterKeyMapping('sl_inv_toggle', 'Ouvrir l\'inventaire', 'keyboard', Config.OpenKey)

-- cleanup any spawned bags if the resource stops
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearCam()
    for _, obj in pairs(dropEntities) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
end)

-- Catalogue for other resources (e.g. the admin "Items" menu): sorted {name,label,category}.
exports('getCatalog', function()
    local list = {}
    for name, s in pairs(Config.Items) do
        list[#list + 1] = { name = name, label = s.label or name, category = s.category or 'misc' }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)
