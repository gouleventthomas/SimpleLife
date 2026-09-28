--[[
    server/players.lua — the player / character registry (single owner).

    Keyed by `source` -> a live char object:
        { license, charId, firstname, lastname, cash, bank, job, grade,
          metadata (table), coords ({x,y,z,heading}) }

    Money mutations are WRITE-THROUGH: the in-memory value AND the DB column are
    updated together, then `money:changed` is emitted on the bus. A minimal,
    read-only mirror is published to the owning client via the player state bag
    (Player(src).state) so features/HUDs read it without an authoritative path.

    Uses Codec for the JSON columns (position/metadata) — bug class B4 protection.
    Schema lives in migrations/002_characters.sql; this file never CREATEs tables.
]]

local players = {}
local registry = {}     -- source -> char object
local byCharId = {}     -- charId -> source
local live = {}         -- source -> true once spawned in the world (gates position capture)

-- ── internal helpers ─────────────────────────────────────────────────────────

local function db() return SLCore.require('db') end
local function bus() return SLCore.require('bus') end

-- Publish a read-only view to the owning client via the player state bag.
local function mirror(src, char)
    local p = Player(src)
    if not p or not p.state then return end
    p.state:set('sl:char', {
        charId = char.charId,
        firstname = char.firstname,
        lastname = char.lastname,
        model = char.model,
        cash = char.cash,
        bank = char.bank,
        job = char.job,
        grade = char.grade,
    }, true) -- replicated = true so the client can read it
end

-- ── lookups ──────────────────────────────────────────────────────────────────

--- Get the live char object for a source.
---@param src integer
---@return table?
function players.getChar(src)
    return registry[src]
end

--- Get the live char object by character id.
---@param charId integer
---@return table?
function players.getCharByCharId(charId)
    local src = byCharId[charId]
    return src and registry[src] or nil
end

--- All currently loaded char objects (array).
---@return table[]
function players.all()
    local arr = {}
    for _, char in pairs(registry) do arr[#arr + 1] = char end
    return arr
end

-- ── load / save ──────────────────────────────────────────────────────────────

--- Load a character row from DB into the live registry for a source.
--- Ensures the owning account exists (FK parent) before binding.
---@param src integer
---@param charId integer
---@return table? char
function players.loadCharacter(src, charId)
    local row = db().single(
        'SELECT id, license, firstname, lastname, model, dob, cash, bank, position, metadata, appearance FROM characters WHERE id = ? AND deleted_at IS NULL',
        { charId }
    )
    if not row then
        Config.Log('warn', ('loadCharacter: no character id=%s'):format(tostring(charId)))
        return nil
    end

    local meta = Codec.decodeJson(row.metadata) or {}
    local pos = Codec.decodeJson(row.position) or {}

    local char = {
        source = src,
        license = row.license,
        charId = row.id,
        firstname = row.firstname,
        lastname = row.lastname,
        model = row.model,
        dob = row.dob,
        cash = tonumber(row.cash) or 0,
        bank = tonumber(row.bank) or 0,
        job = meta.job or 'unemployed',
        grade = meta.grade or 0,
        metadata = meta,
        coords = pos,
        -- full fivem-appearance look; nil when never customized (distinct from {}).
        appearance = row.appearance and Codec.decodeJson(row.appearance) or nil,
    }

    registry[src] = char
    byCharId[char.charId] = src
    live[src] = nil  -- a freshly (re)bound char is NOT live until its OWN releaseToPlayer fires
                     -- sl_core:playerSpawned — so resume/create/re-create never save an intermediate pos
    mirror(src, char)

    -- touch account.last_seen
    db().update('UPDATE accounts SET last_seen = CURRENT_TIMESTAMP WHERE license = ?', { char.license })

    bus().emit('char:loaded', { source = src, charId = char.charId, license = char.license })
    Config.Log('debug', ('character loaded: src=%d charId=%s (%s %s)')
        :format(src, tostring(char.charId), char.firstname or '?', char.lastname or '?'))
    return char
end

--- Persist a character's full appearance (fivem-appearance data) as JSON. Updates the
--- DB and the in-memory registry (if the char is loaded). Re-applied on every spawn for
--- cross-reconnect persistence.
---@param charId integer
---@param appearance table
---@return boolean
function players.saveAppearance(charId, appearance)
    if not charId or type(appearance) ~= 'table' then return false end
    db().update('UPDATE characters SET appearance = ? WHERE id = ?', {
        Codec.encodeJson(appearance), charId,
    })
    local src = byCharId[charId]
    if src and registry[src] then registry[src].appearance = appearance end
    Config.Log('debug', ('appearance saved: charId=%s'):format(tostring(charId)))
    return true
end

--- Persist a character's mutable state back to DB.
---@param src integer
---@return boolean
function players.saveChar(src)
    local char = registry[src]
    if not char then return false end

    -- keep job/grade inside metadata for the JSON column
    char.metadata = char.metadata or {}
    char.metadata.job = char.job
    char.metadata.grade = char.grade

    local affected = db().update(
        'UPDATE characters SET firstname = ?, lastname = ?, cash = ?, bank = ?, position = ?, metadata = ? WHERE id = ?',
        {
            char.firstname,
            char.lastname,
            char.cash,
            char.bank,
            Codec.encodeJson(char.coords or {}),
            Codec.encodeJson(char.metadata or {}),
            char.charId,
        }
    )
    Config.Log('debug', ('character saved: src=%d charId=%s'):format(src, tostring(char.charId)))
    return (tonumber(affected) or 0) >= 0
end

--- Save every loaded character (used by autosave + shutdown).
---@return integer count
function players.saveAll()
    local n = 0
    for src in pairs(registry) do
        if players.saveChar(src) then n = n + 1 end
    end
    return n
end

--- Drop a source from the registry (on disconnect). Saves first.
---@param src integer
function players.unload(src)
    local char = registry[src]
    if not char then return end
    -- best-effort final position capture before saving (the ped may already be gone)
    if Config.SavePosition and live[src] then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local c = GetEntityCoords(ped)
            if c and (c.x ~= 0.0 or c.y ~= 0.0) then
                char.coords = { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped) }
            end
        end
    end
    players.saveChar(src)
    bus().emit('char:logout', { source = src, charId = char.charId })
    byCharId[char.charId] = nil
    registry[src] = nil
    live[src] = nil
end

-- ── live position persistence (déco / reco au même endroit) ───────────────────

--- Mark a player as fully spawned in the world (or clear it). Only LIVE players have their
--- position captured, so the hold / creation / arrival-cinematic positions are never saved.
---@param src integer
---@param v boolean
function players.setLive(src, v)
    live[src] = v and true or nil
end

--- Refresh char.coords from each LIVE player's CURRENT server-read position (OneSync). In
--- memory only; the autosave loop / unload persist it to the DB.
function players.refreshPositions()
    if not Config.SavePosition then return end
    for src, char in pairs(registry) do
        if live[src] then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local c = GetEntityCoords(ped)
                if c and (c.x ~= 0.0 or c.y ~= 0.0) then
                    char.coords = { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped) }
                end
            end
        end
    end
end

-- ── money (write-through) ────────────────────────────────────────────────────

local VALID_ACCOUNTS = { cash = 'cash', bank = 'bank' }

-- Internal: apply a signed delta to an account, write through, mirror, emit.
local function applyDelta(src, account, delta, reason)
    local column = VALID_ACCOUNTS[account]
    if not column then
        return false, 'BAD_ACCOUNT'
    end
    local char = registry[src]
    if not char then return false, 'NO_CHAR' end

    local current = char[account]
    local newValue = current + delta
    if newValue < 0 then
        return false, 'INSUFFICIENT_FUNDS'
    end

    char[account] = newValue
    -- write-through to DB (column name is from a fixed allow-list, never user input)
    db().update(('UPDATE characters SET %s = ? WHERE id = ?'):format(column), { newValue, char.charId })

    mirror(src, char)
    bus().emit('money:changed', {
        source = src,
        charId = char.charId,
        account = account,
        delta = delta,
        balance = newValue,
        reason = reason,
    })
    return true, newValue
end

--- Add money to an account ('cash' or 'bank').
---@param src integer
---@param account 'cash'|'bank'
---@param amount integer positive
---@param reason? string
---@return boolean ok, any detail
function players.addMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'BAD_AMOUNT' end
    return applyDelta(src, account, amount, reason)
end

--- Remove money from an account ('cash' or 'bank'). Fails if insufficient.
---@param src integer
---@param account 'cash'|'bank'
---@param amount integer positive
---@param reason? string
---@return boolean ok, any detail
function players.removeMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'BAD_AMOUNT' end
    return applyDelta(src, account, -amount, reason)
end

--- Set an account to an absolute value.
---@param src integer
---@param account 'cash'|'bank'
---@param value integer
---@param reason? string
---@return boolean ok, any detail
function players.setMoney(src, account, value, reason)
    local char = registry[src]
    if not char then return false, 'NO_CHAR' end
    if not VALID_ACCOUNTS[account] then return false, 'BAD_ACCOUNT' end
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return false, 'BAD_AMOUNT' end
    return applyDelta(src, account, value - char[account], reason)
end

--- Transfer between two characters' accounts. Atomic at the in-memory level:
--- debits source first; if credit fails, the debit is rolled back.
---@param fromSrc integer
---@param toSrc integer
---@param account 'cash'|'bank'
---@param amount integer
---@param reason? string
---@return boolean ok, any detail
function players.transfer(fromSrc, toSrc, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'BAD_AMOUNT' end

    local okDebit, detail = players.removeMoney(fromSrc, account, amount, reason or 'transfer:out')
    if not okDebit then return false, detail end

    local okCredit, detail2 = players.addMoney(toSrc, account, amount, reason or 'transfer:in')
    if not okCredit then
        -- roll the debit back
        players.addMoney(fromSrc, account, amount, 'transfer:rollback')
        return false, detail2
    end
    return true
end

SLCore.module('players', players)

-- Persist + drop on disconnect (authoritative, single owner of this lifecycle).
AddEventHandler('playerDropped', function()
    local src = source
    if src then players.unload(src) end
end)

-- A client signals it has fully spawned in the world (sl_identity releaseToPlayer). From now
-- on its position is captured for déco/reco persistence (and never the hold/arrival positions).
RegisterNetEvent('sl_core:playerSpawned', function()
    players.setLive(source, true)
end)

-- Cross-resource exports. Call with COLON syntax: exports.sl_core:addMoney(src, ...).
-- NOTE: these are SERVER exports and take `src` as the first argument — distinct from
-- the CLIENT getChar() which takes NO argument (see client/core.lua). Do not confuse
-- the two: server getChar(src), client getChar().
exports('getChar', function(src) return players.getChar(src) end)
exports('getCharByCharId', function(charId) return players.getCharByCharId(charId) end)
exports('addMoney', function(src, account, amount, reason) return players.addMoney(src, account, amount, reason) end)
exports('removeMoney', function(src, account, amount, reason) return players.removeMoney(src, account, amount, reason) end)
exports('transfer', function(a, b, account, amount, reason) return players.transfer(a, b, account, amount, reason) end)
exports('saveChar', function(src) return players.saveChar(src) end)
exports('loadCharacter', function(src, charId) return players.loadCharacter(src, charId) end)
exports('saveAppearance', function(charId, appearance) return players.saveAppearance(charId, appearance) end)
-- Flat {source, charId} list of currently-loaded characters (for features restoring per-char
-- state after a mid-session `ensure` of their own resource, e.g. sl_inventory).
exports('loadedChars', function()
    local out = {}
    for src, char in pairs(registry) do out[#out + 1] = { source = src, charId = char.charId } end
    return out
end)
