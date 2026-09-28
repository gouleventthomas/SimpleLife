--[[
    server/leads.lua — the phone "Annuaire des sociétés" backend: a directory of all companies
    (dealerships + sl_shops LTDs) and a contact form that drops a lead in their inbox. Dealership
    leads surface in the GESTION terminal; shop leads ping the shop owner. Reached from the phone
    relay (vehiclesRpc -> sl_vehicles:rpc).
]]

SLV.methods = SLV.methods or {}
local M = SLV.methods

-- Resolve a player's phone number (device-centric sl_phone). Best-effort; nil if unavailable.
function SLV.playerNumber(src)
    local ok, num = pcall(function()
        if exports.sl_phone and exports.sl_phone.getNumber then return exports.sl_phone:getNumber(src) end
        return nil
    end)
    return ok and num or nil
end

-- Best-effort phone push (falls back to an ox_lib notify).
function SLV.phoneNotify(src, title, body)
    local ok = pcall(function()
        if exports.sl_phone and exports.sl_phone.pushNotification then
            exports.sl_phone:pushNotification(src, 'vehicles', title, body)
            return true
        end
        error('no push')
    end)
    if not ok then SLV.notify(src, 'inform', body, title) end
end

function SLV.notifyDealerStaff(dealerId, title, body)
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local aff = SLV.dealAffiliationOf(SLV.charId(pid))
        if aff and aff.dealerId == dealerId then SLV.phoneNotify(pid, title, body) end
    end
end

-- ── directory ───────────────────────────────────────────────────────────────────────
M['phone:directory'] = function(src, _)
    local out = {}
    for _, d in ipairs(Config.Dealerships) do
        local owned = SLV.scalar('SELECT owner_charid FROM dealerships WHERE id = ?', { d.id })
        local cats = {}
        for _, c in ipairs(d.categories) do cats[#cats + 1] = Config.Categories[c] or c end
        out[#out + 1] = {
            id = d.id, kind = 'dealership', label = d.label,
            tag = 'Concession', sub = table.concat(cats, ', '),
            owned = owned ~= nil,
        }
    end
    -- shops (sl_shops LTDs) — best-effort
    local ok, shops = pcall(function()
        if exports.sl_shops and exports.sl_shops.getOwnableShops then return exports.sl_shops:getOwnableShops() end
        return {}
    end)
    if ok and type(shops) == 'table' then
        for _, s in ipairs(shops) do
            out[#out + 1] = { id = s.id, kind = 'shop', label = s.label, tag = 'Boutique', sub = 'Commerce', owned = s.owner ~= nil }
        end
    end
    return { ok = true, companies = out }
end

-- ── contact form ─────────────────────────────────────────────────────────────────────
M['phone:contact'] = function(src, p)
    local char = SLV.char(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    local kind = (p and p.kind == 'shop') and 'shop' or 'dealership'
    local companyId = tostring(p and p.companyId or '')
    -- validate the company exists
    local label
    if kind == 'dealership' then
        local d = Config.Dealership(companyId); if not d then return { ok = false, reason = 'BAD_COMPANY' } end
        label = d.label
    else
        local ok, shops = pcall(function() return exports.sl_shops:getOwnableShops() end)
        if ok and type(shops) == 'table' then
            for _, s in ipairs(shops) do if s.id == companyId then label = s.label break end end
        end
        if not label then return { ok = false, reason = 'BAD_COMPANY' } end
    end
    local subject = tostring(p and p.subject or ''):sub(1, 96)
    local message = tostring(p and p.message or ''):sub(1, 512)
    if message == '' then return { ok = false, reason = 'EMPTY' } end
    local number = SLV.playerNumber(src)
    SLV.insert([[INSERT INTO company_leads (company_id, company_kind, client_charid, client_name, client_number, subject, message)
                 VALUES (?,?,?,?,?,?,?)]],
        { companyId, kind, char.charId, (char.firstname .. ' ' .. char.lastname), number, subject, message })

    local who = (char.firstname .. ' ' .. char.lastname)
    if kind == 'dealership' then
        SLV.notifyDealerStaff(companyId, 'Nouvelle demande', ('%s : %s'):format(who, subject ~= '' and subject or message:sub(1, 40)))
    else
        -- ping the shop owner
        local ok, shops = pcall(function() return exports.sl_shops:getOwnableShops() end)
        if ok and type(shops) == 'table' then
            for _, s in ipairs(shops) do
                if s.id == companyId and s.owner then
                    local osrc = SLV.sourceOfChar(s.owner)
                    if osrc then SLV.phoneNotify(osrc, 'Nouvelle demande', ('%s : %s'):format(who, subject ~= '' and subject or message:sub(1, 40))) end
                end
            end
        end
    end
    return { ok = true }
end

Config.Log('info', 'leads ready')
