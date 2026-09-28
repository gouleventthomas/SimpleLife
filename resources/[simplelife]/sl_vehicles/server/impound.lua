--[[
    server/impound.lua — fourrière. A vehicle goes to impound when it's left OUT at disconnect, or
    when it's destroyed. Recovery is a flat fee at any impound lot ped. Recovered cars spawn at the
    lot's retrieve pose with status 'out'.
]]

SLV.methods = SLV.methods or {}
local M = SLV.methods

-- Send a vehicle to impound (despawn + status).
function SLV.impound(dbId)
    local row = SLV.getVehicleRow(dbId); if not row then return end
    if row.status == 'impound' then return end
    SLV.deleteEntityByDbId(dbId)
    SLV.setStatus(dbId, 'impound', nil)
end

-- destroyed (client reports an owned vehicle wreck)
RegisterNetEvent('sl_vehicles:destroyed', function(netId)
    local src = source
    local dbId = SLV.dbIdOfNet(netId); if not dbId then return end
    -- only the owner or a key holder can flag it (anti-spam); and only if actually wrecked
    if not SLV.hasKey(SLV.charId(src), dbId) then return end
    SLV.impound(dbId)
    local osrc = SLV.sourceOfChar(SLV.ownerOf(dbId))
    if osrc then SLV.notify(osrc, 'warning', 'Votre véhicule a été détruit — récupérable à la fourrière.') end
end)

-- left-out-on-disconnect → impound the player's OUT vehicles (parked cars stay parked)
CreateThread(function()
    while GetResourceState('sl_core') ~= 'started' do Wait(100) end
    exports.sl_core:on('char:logout', function(payload)
        if not payload or not payload.charId then return end
        local outs = SLV.query("SELECT id FROM vehicles WHERE charid = ? AND status = 'out'", { payload.charId }) or {}
        for _, r in ipairs(outs) do SLV.impound(r.id) end
    end)
end)

-- ── lot UI ────────────────────────────────────────────────────────────────────────
local function lotNear(src, lotId)
    local lot = Config.ImpoundLot(lotId)
    return lot and SLV.near(src, lot.ped, 4.0) and lot or nil
end

M['impound:list'] = function(src, p)
    local lot = lotNear(src, p and p.lotId); if not lot then return { ok = false, reason = 'TOO_FAR' } end
    local char = SLV.char(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    local out = {}
    for _, r in ipairs(SLV.query("SELECT id, plate, model, fuel, body_health, engine_health FROM vehicles WHERE charid = ? AND status = 'impound' ORDER BY id", { char.charId }) or {}) do
        local spec = Config.CatalogModel(r.model)
        out[#out + 1] = { id = r.id, plate = r.plate, model = r.model, label = spec and spec.label or r.model,
                          fuel = r.fuel, body = r.body_health, engine = r.engine_health }
    end
    return { ok = true, lot = { id = lot.id, label = lot.label, accent = Config.Accent }, vehicles = out, fee = Config.Impound.fee,
             balances = SLV.balance(src) or { cash = 0, bank = 0 } }
end

M['impound:retrieve'] = function(src, p)
    local lot = lotNear(src, p and p.lotId); if not lot then return { ok = false, reason = 'TOO_FAR' } end
    local char = SLV.char(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    local dbId = tonumber(p and p.dbId); if not dbId then return { ok = false, reason = 'BAD' } end
    local row = SLV.getVehicleRow(dbId)
    if not row or tonumber(row.charid) ~= tonumber(char.charId) or row.status ~= 'impound' then return { ok = false, reason = 'NOT_YOURS' } end
    local account = (p and p.account == 'bank') and 'bank' or 'cash'
    local fee = Config.Impound.fee
    if (SLV.balance(src, account) or 0) < fee then return { ok = false, reason = 'FUNDS' } end
    if not SLV.tryDebit(src, account, fee, 'impound_fee') then return { ok = false, reason = 'FUNDS' } end
    SLV.setStatus(dbId, 'out', nil)
    local pose = lot.retrieve
    local net = SLV.spawnOwned(dbId, { x = pose.x, y = pose.y, z = pose.z, w = pose.w })
    if not net then
        -- refund if we somehow failed to materialise
        SLV.credit(src, account, fee, 'impound_refund')
        SLV.setStatus(dbId, 'impound', nil)
        return { ok = false, reason = 'SPAWN' }
    end
    return { ok = true, plate = row.plate, balances = SLV.balance(src) or { cash = 0, bank = 0 } }
end

Config.Log('info', 'impound ready')
