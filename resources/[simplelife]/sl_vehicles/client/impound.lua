--[[
    client/impound.lua — impound lot clerks (ox_target) that open the recovery NUI.
]]

local PED = 's_m_y_dockwork_01'

CreateThread(function()
    while GetResourceState('sl_interact') ~= 'started' do Wait(200) end
    local hash = joaat(PED)
    lib.requestModel(hash, 8000)
    for _, lot in ipairs(Config.Impound.lots) do
        local p = lot.ped
        local ped = CreatePed(4, hash, p.x, p.y, p.z - 1.0, p.w or 0.0, false, true)
        SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true); SetBlockingOfNonTemporaryEvents(ped, true)
        local lotId = lot.id
        exports.sl_interact:addLocalEntity(ped, {
            { label = 'Fourrière — récupérer un véhicule', icon = 'fa-solid fa-car-burst', distance = 2.5,
              onSelect = function() VehClient.openWith('impound:list', { lotId = lotId }, 'open:impound') end },
        })
    end
    SetModelAsNoLongerNeeded(hash)
end)

Config.Log('info', 'client impound ready')
