--[[
    server/garage.lua — physical persistent parking.

    Parked cars are NOT a cloud menu: each parked vehicle physically sits on a marked spot.
    To save server load they only materialise while a player is INSIDE the garage area
    (presence ref-count). Park = drive an owned car onto a free marked spot + confirm; the exact
    spot pose is stored so it reappears there. Retrieve = walk to the car and unlock it (no menu).
]]

local presence = {}        -- garageId -> count of players inside the area
local playerIn = {}        -- src -> { [garageId]=true }

local function dist2(a, bx, by)
    local dx, dy = a.x - bx, a.y - by
    return dx * dx + dy * dy
end

-- Is a given spot pose free (no parked vehicle of this garage occupies it)?
local function spotFree(garageId, spot)
    for _, r in ipairs(SLV.parkedInGarage(garageId)) do
        if r.park_x and dist2({ x = r.park_x, y = r.park_y }, spot.x, spot.y) < (2.0 * 2.0) then
            return false
        end
    end
    return true
end

-- Nearest FREE spot of a garage to a world coord, within snapReach. Returns vec4 or nil.
local function nearestFreeSpot(garage, coords, snapReach)
    local best, bestD
    for _, s in ipairs(garage.spots or {}) do
        local d = dist2(coords, s.x, s.y)
        if d <= (snapReach * snapReach) and spotFree(garage.id, s) and (not bestD or d < bestD) then
            best, bestD = s, d
        end
    end
    return best
end

-- ── park ──────────────────────────────────────────────────────────────────────────
-- data = { netId, garageId, props, fuel, body, engine }
function SLV.parkVehicle(src, data)
    local netId = data and data.netId
    local dbId = netId and SLV.dbIdOfNet(netId)
    if not dbId then return { ok = false, reason = 'NOT_OWNED' } end
    if tonumber(SLV.ownerOf(dbId)) ~= tonumber(SLV.charId(src)) then return { ok = false, reason = 'NOT_OWNER' } end

    local garage = Config.Garage(data.garageId)
    if not garage then return { ok = false, reason = 'NO_GARAGE' } end

    local veh = SLV.entityFromNet(netId)
    if not veh then return { ok = false, reason = 'GONE' } end
    local vc = GetEntityCoords(veh)
    -- the player must actually be at the vehicle (anti-remote-park)
    if not SLV.near(src, vc, 8.0) then return { ok = false, reason = 'TOO_FAR' } end

    -- category gate
    local row = SLV.getVehicleRow(dbId)
    local accepted = false
    for _, c in ipairs(garage.classes or {}) do if c == row.category then accepted = true break end end
    if not accepted then return { ok = false, reason = 'WRONG_CLASS' } end

    local spot = nearestFreeSpot(garage, vc, 4.0)
    if not spot then return { ok = false, reason = 'NO_FREE_SPOT' } end

    SLV.saveSnapshot(dbId, data.props, data.fuel, data.body, data.engine)
    SLV.setStatus(dbId, 'parked', garage.id, { x = spot.x, y = spot.y, z = spot.z, w = spot.w })
    SLV.deleteEntityByDbId(dbId)
    return { ok = true, label = (Config.CatalogModel(row.model) or {}).label or row.model }
end

-- Owner pulled a parked car off its spot (engine started + moving): flip to 'out'.
function SLV.undock(src, netId)
    local dbId = SLV.dbIdOfNet(netId)
    if not dbId then return end
    if not SLV.hasKey(SLV.charId(src), dbId) then return end
    local row = SLV.getVehicleRow(dbId)
    if row and row.status ~= 'out' then SLV.setStatus(dbId, 'out', nil) end
end

-- ── presence / spawn-on-approach ───────────────────────────────────────────────────
local function spawnParked(garageId)
    local garage = Config.Garage(garageId); if not garage then return end
    for _, r in ipairs(SLV.parkedInGarage(garageId)) do
        if not SLV.isActive(r.id) then
            local pose
            if r.park_x then
                pose = { x = r.park_x, y = r.park_y, z = r.park_z, w = r.park_h or 0.0 }
            else
                pose = garage.spots[1]
            end
            SLV.spawnOwned(r.id, pose)
        end
    end
end

local function despawnParked(garageId)
    for _, r in ipairs(SLV.parkedInGarage(garageId)) do
        if SLV.isActive(r.id) then SLV.deleteEntityByDbId(r.id) end
    end
end

function SLV.garageEnter(src, garageId)
    if not Config.Garage(garageId) then return end
    playerIn[src] = playerIn[src] or {}
    if playerIn[src][garageId] then return end
    playerIn[src][garageId] = true
    presence[garageId] = (presence[garageId] or 0) + 1
    if presence[garageId] == 1 then spawnParked(garageId) end
end

function SLV.garageExit(src, garageId)
    if not playerIn[src] or not playerIn[src][garageId] then return end
    playerIn[src][garageId] = nil
    presence[garageId] = math.max(0, (presence[garageId] or 1) - 1)
    if presence[garageId] == 0 then despawnParked(garageId) end
end

AddEventHandler('playerDropped', function()
    local src = source
    if not playerIn[src] then return end
    for garageId in pairs(playerIn[src]) do
        presence[garageId] = math.max(0, (presence[garageId] or 1) - 1)
        if presence[garageId] == 0 then despawnParked(garageId) end
    end
    playerIn[src] = nil
end)

Config.Log('info', 'garage ready')
