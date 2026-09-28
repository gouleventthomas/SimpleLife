--[[
    client/debug.lua — the developer/debug toolbox behind the admin "Debug" submenu.

    Everything prints to the F8 console (^5 tagged) AND pops a short toast, so you can read
    the value live or scroll the console. Built for the "I'm fixing this prop/coord" loop.
]]

Debug = {}

local ENTITY_TYPES = { [1] = 'ped', [2] = 'véhicule', [3] = 'objet/prop' }

-- Print the player's exact position + heading (ready to paste into a config).
function Debug.printCoords()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local s = ('vector3(%.3f, %.3f, %.3f)  heading = %.2f'):format(c.x, c.y, c.z, h)
    print('^5[sl_admin:debug]^7 coords = ' .. s)
    exports.sl_ui:notify('info', 'Coords (F8) : ' .. ('%.1f, %.1f, %.1f'):format(c.x, c.y, c.z))
end

-- Raycast from the camera and report whatever entity you're looking at.
function Debug.inspectAim()
    local ped = PlayerPedId()
    local from = GetGameplayCamCoord()
    local r = GetGameplayCamRot(2)
    local p, y = math.rad(r.x), math.rad(r.z)
    local cp = math.cos(p)
    local dir = vector3(-math.sin(y) * cp, math.cos(y) * cp, math.sin(p))
    local to = from + dir * 60.0

    local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, ped, 0)
    local _, hit, coords, _, entity = GetShapeTestResult(ray)

    if hit ~= 1 or not entity or entity == 0 then
        print('^5[sl_admin:debug]^7 raycast: rien touché (vise un objet/véhicule/PNJ).')
        exports.sl_ui:notify('warn', 'Rien visé.')
        return
    end

    local etype = GetEntityType(entity)
    local model = GetEntityModel(entity)
    local ec = GetEntityCoords(entity)
    local label = ENTITY_TYPES[etype] or ('type ' .. etype)
    local extra = ''
    if etype == 2 then
        extra = (' nom=%s plaque=%s'):format(GetDisplayNameFromVehicleModel(model) or '?', (GetVehicleNumberPlateText(entity) or ''):gsub('%s+$', ''))
    end

    print(('^5[sl_admin:debug]^7 %s  model(hash)=%d  entity=%d  coords=(%.2f, %.2f, %.2f)%s')
        :format(label, model, entity, ec.x, ec.y, ec.z, extra))
    print(('^5[sl_admin:debug]^7 impact = vector3(%.3f, %.3f, %.3f)'):format(coords.x, coords.y, coords.z))
    exports.sl_ui:notify('info', ('%s — model %d'):format(label, model))
end

-- Print the current vehicle's model + plate + net id, or warn if on foot.
function Debug.printVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        exports.sl_ui:notify('warn', 'Tu n\'es pas dans un véhicule.')
        return
    end
    local model = GetEntityModel(veh)
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+$', '')
    local netId = NetworkGetNetworkIdFromEntity(veh)
    print(('^5[sl_admin:debug]^7 véhicule: nom=%s model(hash)=%d plaque=%s netId=%d')
        :format(GetDisplayNameFromVehicleModel(model) or '?', model, plate, netId))
    exports.sl_ui:notify('info', ('Véhicule: %s (%s)'):format(GetDisplayNameFromVehicleModel(model) or '?', plate))
end

-- Print the player's current heading only (handy for facing calibration).
function Debug.printHeading()
    local h = GetEntityHeading(PlayerPedId())
    print(('^5[sl_admin:debug]^7 heading = %.2f'):format(h))
    exports.sl_ui:notify('info', ('Heading : %.2f'):format(h))
end
