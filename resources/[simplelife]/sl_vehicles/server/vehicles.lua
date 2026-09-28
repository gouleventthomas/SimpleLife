--[[
    server/vehicles.lua — the vehicle registry: DB ownership, persistence, and server-side
    OneSync spawning. A live (spawned) vehicle carries its identity in the statebag:
        Entity(veh).state['sl:veh'] = { id, plate, owner = charid, keys = { [charid]=true } }
        Entity(veh).state['fuel']   = 0..100               (consumed/refuelled)
        Entity(veh).state['sl:engine'] = bool              (commanded engine; remote start/stop)
    so any client can resolve "do I have a key?" instantly, and the server can identify the car.
]]

-- active world vehicles ── dbId <-> netId
local activeByDb  = {}   -- dbId -> netId
local activeByNet = {}   -- netId -> dbId

local TYPE = { moto = 'bike' }   -- category -> CreateVehicleServerSetter type (default automobile)

function SLV.dbIdOfNet(netId) return activeByNet[netId] end
function SLV.netOfDb(dbId)     return activeByDb[dbId] end
function SLV.isActive(dbId)    return activeByDb[dbId] ~= nil end

local function registerActive(netId, dbId)
    activeByDb[dbId] = netId
    activeByNet[netId] = dbId
end
local function unregisterActive(dbId)
    local netId = activeByDb[dbId]
    if netId then activeByNet[netId] = nil end
    activeByDb[dbId] = nil
end

-- ── rows ────────────────────────────────────────────────────────────────────────
function SLV.getVehicleRow(dbId)
    return SLV.single('SELECT * FROM vehicles WHERE id = ?', { dbId })
end
function SLV.getVehicleByPlate(plate)
    return SLV.single('SELECT * FROM vehicles WHERE plate = ?', { plate })
end
function SLV.ownerOf(dbId)
    return SLV.scalar('SELECT charid FROM vehicles WHERE id = ?', { dbId })
end
function SLV.countOwned(charId)
    return tonumber(SLV.scalar('SELECT COUNT(*) FROM vehicles WHERE charid = ?', { charId })) or 0
end

-- The set of EXTRA key-holders (string charids) for a vehicle (owner is separate).
function SLV.keysSet(dbId)
    local set = {}
    for _, r in ipairs(SLV.query('SELECT charid FROM vehicle_keys WHERE vehicle_id = ?', { dbId }) or {}) do
        set[tostring(r.charid)] = true
    end
    return set
end

-- Has this character a key (owner or shared)?
function SLV.hasKey(charId, dbId)
    if not charId or not dbId then return false end
    if tonumber(SLV.ownerOf(dbId)) == tonumber(charId) then return true end
    return SLV.scalar('SELECT 1 FROM vehicle_keys WHERE vehicle_id = ? AND charid = ? LIMIT 1', { dbId, charId }) ~= nil
end

-- Vehicles a character can ACCESS (owned + shared) — for the phone app.
function SLV.accessibleList(charId)
    local out = {}
    local owned = SLV.query([[SELECT id, plate, model, category, fuel, body_health, engine_health, status, garage
                              FROM vehicles WHERE charid = ? ORDER BY id]], { charId }) or {}
    for _, r in ipairs(owned) do
        local spec = Config.CatalogModel(r.model)
        out[#out + 1] = {
            id = r.id, plate = r.plate, model = r.model, category = r.category,
            label = spec and spec.label or r.model, brand = spec and spec.brand,
            fuel = r.fuel, body = r.body_health, engine = r.engine_health,
            status = r.status, garage = r.garage, role = 'owner',
            active = SLV.isActive(r.id),
        }
    end
    local shared = SLV.query([[SELECT v.id, v.plate, v.model, v.category, v.fuel, v.body_health, v.engine_health, v.status, v.garage
                               FROM vehicle_keys k JOIN vehicles v ON v.id = k.vehicle_id
                               WHERE k.charid = ? ORDER BY v.id]], { charId }) or {}
    for _, r in ipairs(shared) do
        local spec = Config.CatalogModel(r.model)
        out[#out + 1] = {
            id = r.id, plate = r.plate, model = r.model, category = r.category,
            label = spec and spec.label or r.model, brand = spec and spec.brand,
            fuel = r.fuel, body = r.body_health, engine = r.engine_health,
            status = r.status, garage = r.garage, role = 'shared',
            active = SLV.isActive(r.id),
        }
    end
    return out
end

-- Vehicles owned and currently parked in a given garage (for the garage UI / reboot respawn).
function SLV.parkedInGarage(garageId)
    return SLV.query([[SELECT * FROM vehicles WHERE garage = ? AND status = 'parked']], { garageId }) or {}
end

-- ── create / persist ─────────────────────────────────────────────────────────────
-- Insert a brand-new owned vehicle row. opts: { category, props, fuel, status, garage }.
function SLV.createVehicle(charId, model, opts)
    opts = opts or {}
    local spec = Config.CatalogModel(model)
    local category = opts.category or (spec and spec.category) or 'car'
    local plate = SLV.genPlate()
    local fuel = opts.fuel or 100
    local id = SLV.insert([[INSERT INTO vehicles (charid, plate, model, category, props, fuel, body_health, engine_health, status, garage)
                            VALUES (?,?,?,?,?,?,?,?,?,?)]],
        { charId, plate, model, category, SLV.encode(opts.props), fuel, 1000, 1000,
          opts.status or 'out', opts.garage })
    return { id = id, plate = plate, model = model, category = category, fuel = fuel }
end

-- Persist a full client-captured snapshot (mods/damage/colour) + mirrored health/fuel columns.
function SLV.saveSnapshot(dbId, props, fuel, body, engine)
    if not dbId then return end
    SLV.update('UPDATE vehicles SET props = ?, fuel = ?, body_health = ?, engine_health = ? WHERE id = ?',
        { SLV.encode(props), math.floor(fuel or 100), math.floor(body or 1000), math.floor(engine or 1000), dbId })
end

-- Cheap periodic health/fuel update (no full props blob).
function SLV.updateHealth(dbId, fuel, body, engine)
    if not dbId then return end
    SLV.update('UPDATE vehicles SET fuel = ?, body_health = ?, engine_health = ? WHERE id = ?',
        { math.floor(fuel or 100), math.floor(body or 1000), math.floor(engine or 1000), dbId })
end

function SLV.setStatus(dbId, status, garage, parkVec)
    if parkVec then
        SLV.update('UPDATE vehicles SET status = ?, garage = ?, park_x = ?, park_y = ?, park_z = ?, park_h = ? WHERE id = ?',
            { status, garage, parkVec.x, parkVec.y, parkVec.z, parkVec.w or parkVec.h or 0.0, dbId })
    else
        SLV.update('UPDATE vehicles SET status = ?, garage = ? WHERE id = ?', { status, garage, dbId })
    end
end

function SLV.transferOwner(dbId, newCharId)
    SLV.update('UPDATE vehicles SET charid = ? WHERE id = ?', { newCharId, dbId })
    -- on a sale/gift, ALL previously shared keys are revoked so old holders lose access
    SLV.update('DELETE FROM vehicle_keys WHERE vehicle_id = ?', { dbId })
end

function SLV.deleteVehicle(dbId)
    SLV.deleteEntityByDbId(dbId)
    SLV.update('DELETE FROM vehicle_keys WHERE vehicle_id = ?', { dbId })
    SLV.update('DELETE FROM vehicles WHERE id = ?', { dbId })
    -- trunk stash (if any) is left to lazy-GC; clear it now if the stash API is present
    local plate = nil  -- already deleted; trunk keyed by id below
    if exports.sl_inventory and exports.sl_inventory.clearStash then
        pcall(function() exports.sl_inventory:clearStash('veh:' .. dbId) end)
    end
    return true
end

-- ── server-side spawning (OneSync) ───────────────────────────────────────────────
local function spawnEntity(model, category, x, y, z, h)
    local hash = joaat(model)
    local vtype = TYPE[category] or 'automobile'
    local veh = CreateVehicleServerSetter(hash, vtype, x + 0.0, y + 0.0, z + 0.0, h + 0.0)
    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do Wait(0); tries = tries + 1 end
    if not DoesEntityExist(veh) then
        Config.Log('error', ('spawnEntity failed for model=%s'):format(tostring(model)))
        return nil
    end
    return veh
end

-- Apply identity + persisted props/fuel + lock to a freshly spawned entity, and register it.
local function applyIdentity(veh, row)
    local plate = row.plate
    SetVehicleNumberPlateText(veh, plate)
    local props = SLV.decode(row.props)
    if type(props) == 'table' then
        props.plate = plate
        pcall(function() lib.setVehicleProperties(veh, props) end)
    end
    local st = Entity(veh).state
    st:set('fuel', row.fuel or 100, true)
    st:set('sl:engine', false, true)
    st:set('sl:veh', {
        id = row.id, plate = plate, owner = tonumber(row.charid),
        keys = SLV.keysSet(row.id), category = row.category,
    }, true)
    SetVehicleDoorsLocked(veh, 2)
    if row.body_health then SetVehicleBodyHealth(veh, row.body_health + 0.0) end
    if row.engine_health then SetVehicleEngineHealth(veh, row.engine_health + 0.0) end
    registerActive(NetworkGetNetworkIdFromEntity(veh), row.id)
end

-- Spawn an OWNED vehicle (by db id) at a world pose. Returns netId or nil. Idempotent: if it's
-- already active, returns the existing netId.
function SLV.spawnOwned(dbId, pose)
    if activeByDb[dbId] then return activeByDb[dbId] end
    local row = SLV.getVehicleRow(dbId)
    if not row then return nil end
    local veh = spawnEntity(row.model, row.category, pose.x, pose.y, pose.z, pose.w or pose.h or 0.0)
    if not veh then return nil end
    applyIdentity(veh, row)
    return NetworkGetNetworkIdFromEntity(veh)
end

-- Delete the live entity for a db id (if spawned) and unregister it.
function SLV.deleteEntityByDbId(dbId)
    local netId = activeByDb[dbId]
    if not netId then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then DeleteEntity(veh) end
    unregisterActive(dbId)
end

-- Refresh the live statebag key-set for a vehicle (after share/revoke) if it's spawned.
function SLV.refreshKeysState(dbId)
    local netId = activeByDb[dbId]
    if not netId then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local vd = Entity(veh).state['sl:veh']
    if type(vd) == 'table' then
        vd.keys = SLV.keysSet(dbId)
        Entity(veh).state:set('sl:veh', vd, true)
    end
end

-- A bare entity not tied to ownership (port stock units, demo). Returns netId.
-- identity = optional { stock = true, dealer = id, model = m } statebag tag.
function SLV.spawnNeutral(model, category, pose, tag)
    local veh = spawnEntity(model, category, pose.x, pose.y, pose.z, pose.w or pose.h or 0.0)
    if not veh then return nil end
    -- UNLOCKED: these are job vehicles (transport + import stock units), they carry no 'sl:veh' so the
    -- engine gate never applies — they must be freely drivable. (SetVehicleNeedsToBeHotwired is a
    -- CLIENT-only native, applied client-side when the transport is taken; not callable here.)
    SetVehicleDoorsLocked(veh, 1)
    Entity(veh).state:set('fuel', 100, true)
    if tag then Entity(veh).state:set('sl:stock', tag, true) end
    return NetworkGetNetworkIdFromEntity(veh), veh
end

-- Resolve the live entity handle from a netId, server-side.
function SLV.entityFromNet(netId)
    if not netId then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then return veh end
    return nil
end

Config.Log('info', 'vehicles registry ready')
