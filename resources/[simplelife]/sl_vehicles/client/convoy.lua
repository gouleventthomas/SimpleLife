--[[
    client/convoy.lua — the import convoy: grab a transport at the port, LOAD ready port units onto
    it by interaction, drive to the dealership delivery bay, UNLOAD them into stock by interaction.
]]

local transport = nil    -- { kind='flatbed'|'carrier', trailer=entity, hauler=entity }
local loaded = {}        -- netId -> true (loaded by me, awaiting unload)

local function waitEntity(netId)
    local tries = 0
    while tries < 80 do
        local e = NetToVeh(netId)
        if e ~= 0 and DoesEntityExist(e) then return e end
        Wait(50); tries = tries + 1
    end
    return nil
end

-- ── take a transport at the port ────────────────────────────────────────────────────
local function takeTransport(dealerId, kind)
    local res = VehClient.rpc('convoy:transport', { dealerId = dealerId, kind = kind })
    if not res or not res.ok then VehClient.notify('error', VehClient.reason(res and res.reason)); return end
    if res.kind == 'flatbed' then
        local e = waitEntity(res.transport)
        if e then SetVehicleDoorsLocked(e, 1); SetVehicleNeedsToBeHotwired(e, false) end
        transport = { kind = 'flatbed', trailer = e, slots = 1 }
        VehClient.notify('inform', 'Flatbed prêt au concess — roule jusqu\'au port, charge la voiture, puis reviens la livrer.')
    else
        local hauler = waitEntity(res.hauler)
        local trailer = waitEntity(res.trailer)
        if hauler then SetVehicleDoorsLocked(hauler, 1); SetVehicleNeedsToBeHotwired(hauler, false) end
        if trailer then SetVehicleDoorsLocked(trailer, 1) end
        if hauler and trailer then
            AttachVehicleToTrailer(hauler, trailer, 1.0)
        end
        transport = { kind = 'carrier', trailer = trailer, hauler = hauler, slots = res.slots }
        VehClient.notify('inform', 'Camion porte-voitures prêt au concess — roule jusqu\'au port, charge, puis reviens livrer.')
    end
end

CreateThread(function()
    while GetResourceState('sl_interact') ~= 'started' do Wait(200) end
    -- "Sortir un camion de livraison" AT EACH DEALERSHIP (drive it to the port, fetch, come back).
    for _, d in ipairs(Config.Dealerships) do
        local id = d.id
        local sp = d.transportSpawn
        if sp then
            exports.sl_interact:addCoords(vector3(sp.x, sp.y, sp.z), 3.0, {
                {
                    label = 'Sortir un flatbed (1 véhicule)', icon = 'fa-solid fa-truck-pickup', distance = 3.0,
                    canInteract = function() return VehClient.myDealer == id end,
                    onSelect = function() takeTransport(id, 'flatbed') end,
                },
                {
                    label = 'Sortir un porte-voitures (plusieurs)', icon = 'fa-solid fa-truck-ramp-box', distance = 3.0,
                    canInteract = function() return VehClient.myDealer == id end,
                    onSelect = function() takeTransport(id, 'carrier') end,
                },
            })
        end
    end
    -- port blip (où récupérer les véhicules importés)
    local blip = AddBlipForCoord(Config.Import.portBlip.x, Config.Import.portBlip.y, Config.Import.portBlip.z)
    SetBlipSprite(blip, 477); SetBlipColour(blip, 3); SetBlipScale(blip, 0.7); SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName("Port d'import"); EndTextCommandSetBlipName(blip)
end)

-- ── load / unload via global vehicle target ─────────────────────────────────────────
CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do Wait(200) end
    exports.ox_target:addGlobalVehicle({
        {
            name = 'sl_veh_convoy_load',
            label = 'Charger sur le transport',
            icon = 'fa-solid fa-dolly',
            distance = Config.Import.loadReach or 4.0,
            canInteract = function(entity)
                if not transport or not transport.trailer then return false end
                local st = Entity(entity).state['sl:stock']
                return type(st) == 'table' and st.dealer == VehClient.myDealer and not loaded[VehToNet(entity)]
            end,
            onSelect = function(data)
                local entity = data.entity
                local res = VehClient.rpc('convoy:load', {
                    vehNet = VehToNet(entity), trailerNet = VehToNet(transport.trailer), kind = transport.kind,
                })
                if not res or not res.ok then VehClient.notify('error', VehClient.reason(res and res.reason)); return end
                loaded[VehToNet(entity)] = true
                local o = res.offset
                AttachEntityToEntity(entity, transport.trailer, 0,
                    o.x + 0.0, o.y + 0.0, o.z + 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0, true)
                VehClient.notify('success', 'Véhicule chargé.')
            end,
        },
    })
end)

-- ── déchargement : "[E] Décharger le convoi" sur la zone de livraison (pas besoin de viser) ──
local unloadShown = false
CreateThread(function()
    while true do
        local wait = 700
        local show = false
        if next(loaded) ~= nil then
            local pc = GetEntityCoords(PlayerPedId())
            for _, d in ipairs(Config.Dealerships) do
                if VehClient.myDealer == d.id and d.delivery
                    and #(pc - vector3(d.delivery.x, d.delivery.y, d.delivery.z)) < (d.deliveryReach or 8.0) then
                    show = true; break
                end
            end
        end
        if show then
            wait = 0
            unloadShown = true
            lib.showTextUI('[E] Décharger le convoi', { position = 'bottom-center' })
            if IsControlJustReleased(0, 38) then  -- E
                lib.hideTextUI(); unloadShown = false
                local nets = {}
                for net in pairs(loaded) do nets[#nets + 1] = net end
                for _, net in ipairs(nets) do
                    local res = VehClient.rpc('convoy:unload', { vehNet = net })
                    if res and res.ok then
                        loaded[net] = nil
                        local e = NetToVeh(net)
                        if e ~= 0 and DoesEntityExist(e) then DetachEntity(e, true, false) end
                        VehClient.notify('success', ('%s livré au stock.'):format(res.label or 'Véhicule'))
                    else
                        VehClient.notify('error', VehClient.reason(res and res.reason))
                    end
                end
                Wait(700)
            end
        elseif unloadShown then
            unloadShown = false
            lib.hideTextUI()
        end
        Wait(wait)
    end
end)

-- marqueur au sol sur le point « Sortir un camion » (visible par le staff, à proximité)
CreateThread(function()
    while true do
        local wait = 1000
        local pc = GetEntityCoords(PlayerPedId())
        for _, d in ipairs(Config.Dealerships) do
            if VehClient.myDealer == d.id then
                -- point de sortie du camion (bleu)
                local sp = d.transportSpawn
                if sp and #(pc - vector3(sp.x, sp.y, sp.z)) < 25.0 then
                    wait = 0
                    DrawMarker(1, sp.x, sp.y, sp.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        2.0, 2.0, 0.5, 59, 169, 224, 120, false, false, 2, false, nil, nil, false)
                end
                -- zone de livraison / déchargement (vert)
                local dv = d.delivery
                if dv and #(pc - vector3(dv.x, dv.y, dv.z)) < 25.0 then
                    wait = 0
                    DrawMarker(1, dv.x, dv.y, dv.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        3.0, 3.0, 0.5, 52, 199, 89, 120, false, false, 2, false, nil, nil, false)
                end
            end
        end
        Wait(wait)
    end
end)

Config.Log('info', 'client convoy ready')
