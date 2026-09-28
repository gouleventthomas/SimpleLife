--[[
    server/util.lua — shared server namespace + helpers (loaded FIRST).

    Every server module hangs its cross-file functions off the global `SLV` table (same Lua
    state within this resource). Features in OTHER resources must use the flat exports / the
    'sl_vehicles:rpc' callback, never SLV.
]]

SLV = SLV or {}

local Core = function() return exports.sl_core end

-- ── identity helpers ────────────────────────────────────────────────────────────
function SLV.charId(src)
    local char = Core():getChar(src)
    return char and char.charId or nil
end

function SLV.char(src)
    return Core():getChar(src)
end

-- Resolve an online source from a character id (nil if that character isn't connected).
function SLV.sourceOfChar(charId)
    if not charId then return nil end
    charId = tonumber(charId)
    local ok, loaded = pcall(function() return Core():loadedChars() or {} end)
    if not ok then return nil end
    for _, e in ipairs(loaded) do
        if tonumber(e.charId) == charId then return e.source end
    end
    return nil
end

function SLV.charName(charId)
    if not charId then return nil end
    local row = Core():dbSingle('SELECT firstname, lastname FROM characters WHERE id = ?', { charId })
    if not row then return nil end
    return (row.firstname or '') .. ' ' .. (row.lastname or '')
end

-- ── db convenience (always via sl_core's pooled connection) ─────────────────────
function SLV.query(sql, p)  return Core():dbQuery(sql, p) end
function SLV.single(sql, p) return Core():dbSingle(sql, p) end
function SLV.scalar(sql, p) return Core():dbScalar(sql, p) end
function SLV.insert(sql, p) return Core():dbInsert(sql, p) end
function SLV.update(sql, p) return Core():dbUpdate(sql, p) end

-- ── money (always via sl_core economy; never mutate char.cash directly) ──────────
function SLV.balance(src, account) return Core():economyBalance(src, account) end
function SLV.tryDebit(src, account, amount, reason) return Core():economyTryDebit(src, account, amount, reason) end
function SLV.credit(src, account, amount, reason) return Core():economyCredit(src, account, amount, reason) end

-- ── notify (uses ox_lib's client notify event) ──────────────────────────────────
function SLV.notify(src, kind, msg, title)
    TriggerClientEvent('ox_lib:notify', src, { title = title or 'Véhicules', description = msg, type = kind or 'inform' })
end

-- ── json (CFX global) ───────────────────────────────────────────────────────────
function SLV.encode(v) return v ~= nil and json.encode(v) or nil end
function SLV.decode(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) == 'string' and raw ~= '' then
        local ok, d = pcall(json.decode, raw); if ok then return d end
    end
    return nil
end

-- ── single-flight lock per player (race / spam guard for money/stock ops) ────────
local inFlight = {}
function SLV.withLock(src, fn)
    if inFlight[src] then return { ok = false, reason = 'RATE' } end
    inFlight[src] = true
    local ok, res = pcall(fn)
    inFlight[src] = nil
    if not ok then
        Config.Log('error', ('withLock error: %s'):format(tostring(res)))
        return { ok = false, reason = 'ERROR' }
    end
    return res
end

-- ── unique plate generation (standard GTA-style 8-char alphanumeric) ─────────────
local PLATE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
math.randomseed(GetGameTimer() + os.time())

local function randomPlate()
    local t = {}
    for i = 1, 8 do
        local n = math.random(1, #PLATE_CHARS)
        t[i] = PLATE_CHARS:sub(n, n)
    end
    return table.concat(t)
end

-- Generate a plate guaranteed not present in the vehicles table.
function SLV.genPlate()
    for _ = 1, 25 do
        local p = randomPlate()
        local exists = SLV.scalar('SELECT 1 FROM vehicles WHERE plate = ? LIMIT 1', { p })
        if not exists then return p end
    end
    -- extremely unlikely fallback
    return randomPlate()
end

-- ── distance helper ─────────────────────────────────────────────────────────────
function SLV.near(src, coords, reach)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local p = GetEntityCoords(ped)
    return #(p - vector3(coords.x, coords.y, coords.z)) <= (reach or 3.0)
end

Config.Log('info', 'util ready')
