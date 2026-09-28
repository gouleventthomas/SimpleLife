--[[
    client/world.lua — world setup.
      • 24/7 ('247')  → clerk PED + "Acheter" ox_target (self-service from the NPC).
      • LTD ('ltd')   → NO ped. THREE staff-only sphere zones (one per points.* coord):
                          Caisse (vendre + caisse), Stock (items in/out), Gestion (prix/employés/grades).
      • Grossiste     → PED; "Réappro" for players affiliated with a shop.
    Blips for every store + the wholesaler.
]]

local peds, blips, zones = {}, {}, {}

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < 5000 do Wait(50); waited = waited + 50 end
    return HasModelLoaded(hash) and hash or nil
end

local function spawnPed(ped)
    local hash = loadModel(ped.model or Config.PedModel)
    if not hash then return nil end
    local c = ped.coords
    local entity = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityHeading(entity, c.w or 0.0)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetBlockingOfNonTemporaryEvents(entity, true)
    return entity
end

local function makeBlip(coords, b, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, b.sprite or 52)
    SetBlipColour(blip, b.color or 2)
    SetBlipScale(blip, b.scale or 0.7)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function setupWorld()
    for _, shop in ipairs(Config.Shops) do
        if shop.type == '247' then
            local entity = spawnPed(shop.ped)
            if entity then
                peds[#peds + 1] = entity
                exports.sl_interact:addLocalEntity(entity, {
                    { label = 'Acheter', icon = 'fa-solid fa-basket-shopping', distance = 2.5,
                      onSelect = function() OpenShopUI(shop.id) end },
                })
            end
        elseif shop.points then
            -- staff-only zone helper (only the shop's owner/employees see the option)
            local function staffZone(coords, label, icon, fn)
                if not coords then return end
                local zid = exports.sl_interact:addCoords(vector3(coords.x, coords.y, coords.z), 1.5, {
                    { label = label, icon = icon, distance = 2.0,
                      canInteract = function() return ShopClient.myShop == shop.id end,
                      onSelect = fn },
                })
                if zid then zones[#zones + 1] = zid end
            end
            staffZone(shop.points.caisse,  'Caisse',  'fa-solid fa-cash-register', function() OpenCaisse(shop.id) end)
            staffZone(shop.points.stock,   'Stock',   'fa-solid fa-boxes-stacked', function() OpenStock(shop.id) end)
            staffZone(shop.points.gestion, 'Gestion', 'fa-solid fa-briefcase',     function() OpenGestion(shop.id) end)
        end

        local bc = (shop.blip and shop.blip.coords) or (shop.ped and shop.ped.coords)
        if shop.blip and bc then blips[#blips + 1] = makeBlip(bc, shop.blip, shop.label) end
    end

    local w = Config.Wholesaler
    if w and w.ped then
        local entity = spawnPed(w.ped)
        if entity then
            peds[#peds + 1] = entity
            exports.sl_interact:addLocalEntity(entity, {
                { label = (w.label or 'Grossiste') .. ' (réappro)', icon = 'fa-solid fa-truck-ramp-box', distance = 2.5,
                  canInteract = function() return ShopClient.myShop ~= nil end,
                  onSelect = function() OpenWholesaleUI() end },
            })
        end
        if w.blip then blips[#blips + 1] = makeBlip(w.ped.coords, w.blip, w.label or 'Grossiste') end
    end
end

CreateThread(function()
    Wait(1000)
    setupWorld()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in ipairs(peds) do if DoesEntityExist(p) then DeleteEntity(p) end end
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    for _, z in ipairs(zones) do if z then pcall(function() exports.sl_interact:removeZone(z) end) end end
end)
