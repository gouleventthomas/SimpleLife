--[[
    server/main.lua — sl_identity server: account bootstrap, char select/create,
    resume vs arrival routing. All DB work goes through sl_core's flat exports
    (COLON syntax). This file NEVER requires oxmysql.

    Flow:
      playerConnecting  -> ensure accounts row (INSERT IGNORE), short deferral.
      'sl_identity:clientReady' (net) -> load this license's characters, open the
                                         right sl_ui screen (charselect / charcreate).
      'sl_identity:select' (net, {id}) -> OWNERSHIP GATE -> loadCharacter -> RESUME.
      'sl_identity:create' (net, {...}) -> validate + cap -> dbInsert -> loadCharacter
                                           -> ARRIVAL via Arrival.begin({ one player }).
]]

-- sl_core flat exports are resolved LIVE at each call site (never cached at file
-- top-level — that is the documented B3 anti-pattern). Use COLON syntax so the CFX
-- exports proxy consumes itself as `self` and our real args arrive intact.
local function Core()
    return exports.sl_core
end

-- ── identifier helpers ────────────────────────────────────────────────────────

--- Resolve the canonical 'license:...' identifier for a source. Returns nil if the
--- player has no license identifier yet (extremely early in connect).
---@param src integer|string
---@return string?
local function getLicense(src)
    local n = GetNumPlayerIdentifiers(src)
    for i = 0, n - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, 8) == 'license:' then
            return id
        end
    end
    return nil
end

-- ── JSON column decode (defensive) ────────────────────────────────────────────
-- oxmysql may hand back a JSON column as EITHER a decoded Lua table OR a raw string,
-- depending on driver config. sl_identity must not reach into sl_core's Codec, so we
-- decode defensively here with the native json global, never crashing on bad data.
---@param v any
---@return table
local function decodeJsonColumn(v)
    if type(v) == 'table' then return v end
    if type(v) == 'string' and v ~= '' then
        local ok, decoded = pcall(json.decode, v)
        if ok and type(decoded) == 'table' then return decoded end
    end
    return {}
end

-- ── account bootstrap on connect ──────────────────────────────────────────────
-- Short, non-blocking deferral. We do NOT wait for sl_core to be ready here — the
-- INSERT IGNORE is best-effort; if it fails we still let the player in and the
-- clientReady handler will retry/repair. Never block the connect forever.
AddEventHandler('playerConnecting', function(name, _setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update(Config.ConnectMessage)

    local license = getLicense(src)
    if not license then
        -- No license identifier — let them in anyway; clientReady will handle the
        -- (rare) no-character path. Never hard-kick a connecting player here.
        Config.Log('warn', ('connect: no license identifier for "%s" (src=%s)')
            :format(tostring(name), tostring(src)))
        deferrals.done()
        return
    end

    -- Best-effort account row. Guard on core readiness; if not ready yet, skip the
    -- insert (clientReady re-ensures it before querying characters).
    local ok = pcall(function()
        if Core():isReady() then
            Core():dbInsert('INSERT IGNORE INTO accounts (license) VALUES (?)', { license })
        end
    end)
    if not ok then
        Config.Log('warn', ('connect: account bootstrap failed for %s (continuing)'):format(license))
    end

    deferrals.done()
end)

-- ── helpers shared by clientReady / create ────────────────────────────────────

--- Wait (bounded) for sl_core to be ready, then ensure the account row exists.
--- Returns the license or nil if we never got one.
---@param src integer
---@return string?
local function ensureAccount(src)
    local license = getLicense(src)
    if not license then return nil end

    -- Bounded wait for core readiness (it usually is by the time a client is ready).
    local tries = 0
    while not Core():isReady() and tries < 100 do  -- ~10s ceiling
        Wait(100)
        tries = tries + 1
    end
    if not Core():isReady() then
        Config.Log('error', 'ensureAccount: sl_core never became ready — cannot proceed')
        return license  -- return license anyway; caller will surface a failure to the client
    end

    pcall(function()
        Core():dbInsert('INSERT IGNORE INTO accounts (license) VALUES (?)', { license })
    end)
    return license
end

--- Build the trimmed charselect payload list from raw character rows.
---@param rows table[]
---@return table[]
local function buildCharList(rows)
    local list = {}
    for _, row in ipairs(rows or {}) do
        local meta = decodeJsonColumn(row.metadata)
        list[#list + 1] = {
            id        = row.id,
            firstname = row.firstname,
            lastname  = row.lastname,
            model     = row.model,
            cash      = tonumber(row.cash) or 0,
            bank      = tonumber(row.bank) or 0,
            lastZone  = meta.lastZone,  -- nil if never set
        }
    end
    return list
end

-- ── decide + open the entry screen for a source (charselect / charcreate) ──────
-- Extracted from the clientReady handler so dev replay commands (server/commands.lua,
-- same Lua state) can reuse the REAL entry flow instead of duplicating the query.
local function openEntry(src)
    local license = ensureAccount(src)
    if not license then
        Config.Log('warn', ('openEntry: no license for src=%d — opening fresh create'):format(src))
        TriggerClientEvent('sl_identity:openCreate', src, { canCancel = false })
        return
    end

    local rows
    local ok = pcall(function()
        rows = Core():dbQuery(
            'SELECT id, firstname, lastname, model, cash, bank, position, metadata '
            .. 'FROM characters WHERE license = ? AND deleted_at IS NULL ORDER BY created',
            { license }
        )
    end)
    if not ok then
        Config.Log('error', ('openEntry: character query failed for %s'):format(license))
        rows = {}
    end
    rows = rows or {}

    if #rows >= 1 then
        local chars = buildCharList(rows)
        Config.Log('info', ('openEntry: src=%d has %d character(s) — charselect'):format(src, #chars))
        TriggerClientEvent('sl_identity:openSelect', src, {
            chars = chars,
            cap   = Config.CharacterCap,
        })
    else
        Config.Log('info', ('openEntry: src=%d has no characters — charcreate'):format(src))
        TriggerClientEvent('sl_identity:openCreate', src, { canCancel = false })
    end
end

-- ── client is ready: decide the entry screen ──────────────────────────────────
RegisterNetEvent('sl_identity:clientReady', function()
    openEntry(source)
end)

-- ── select an EXISTING character: OWNERSHIP GATE then RESUME ───────────────────
RegisterNetEvent('sl_identity:select', function(data)
    local src = source
    local charId = data and tonumber(data.id)
    if not charId then
        Config.Log('warn', ('select: src=%d sent no/invalid id'):format(src))
        return
    end

    local license = getLicense(src)
    if not license then
        Config.Log('warn', ('select: src=%d has no license — rejecting'):format(src))
        return
    end

    -- NON-NEGOTIABLE SECURITY GATE: loadCharacter does NO ownership check, so we
    -- re-query the character's license by id and confirm it matches THIS caller's
    -- license before loading. Reject + log on mismatch (anti-IDOR / char theft).
    local owner
    local ok = pcall(function()
        owner = Core():dbSingle(
            'SELECT license FROM characters WHERE id = ? AND deleted_at IS NULL',
            { charId }
        )
    end)
    if not ok or not owner or owner.license ~= license then
        Config.Log('warn', ('select: OWNERSHIP REJECT src=%d license=%s tried charId=%s (owner=%s)')
            :format(src, tostring(license), tostring(charId),
                    owner and tostring(owner.license) or 'none'))
        return
    end

    local char
    local ok2 = pcall(function()
        char = Core():loadCharacter(src, charId)
    end)
    if not ok2 or not char then
        Config.Log('error', ('select: loadCharacter failed src=%d charId=%s'):format(src, tostring(charId)))
        return
    end

    -- EXISTING character -> RESUME at saved coords (no plane). coords is the decoded
    -- `position` JSON; may be empty for a never-moved char (client falls back).
    Config.Log('info', ('select: RESUME src=%d charId=%s (%s %s)')
        :format(src, tostring(charId), char.firstname or '?', char.lastname or '?'))
    TriggerClientEvent('sl_identity:resume', src, {
        model      = char.model,
        coords     = char.coords or {},
        appearance = char.appearance,  -- nil if never customized -> client falls back to model
    })
end)

-- ── create a NEW character: validate + cap -> insert -> ARRIVAL ────────────────

--- Server-side validation of a create payload. Returns ok, cleaned, errReason.
---@param data table
---@return boolean ok, table? cleaned, string? err
local function validateCreate(data)
    if type(data) ~= 'table' then return false, nil, 'BAD_PAYLOAD' end

    local function clean(s)
        if type(s) ~= 'string' then return nil end
        -- trim surrounding whitespace
        return (s:gsub('^%s+', ''):gsub('%s+$', ''))
    end

    local firstname = clean(data.firstname)
    local lastname  = clean(data.lastname)
    local gender    = data.gender
    local dob       = clean(data.dob)  -- 'YYYY-MM-DD' expected; stored as-is (DATE col)

    if not firstname or not lastname then return false, nil, 'NAME_REQUIRED' end
    local lo, hi = Config.NameMinLen, Config.NameMaxLen
    if #firstname < lo or #firstname > hi then return false, nil, 'FIRSTNAME_LEN' end
    if #lastname  < lo or #lastname  > hi then return false, nil, 'LASTNAME_LEN' end

    if gender ~= 'm' and gender ~= 'f' then return false, nil, 'BAD_GENDER' end
    local model = Config.Models[gender]
    if not model then return false, nil, 'BAD_GENDER' end

    -- dob: accept a strict YYYY-MM-DD; otherwise store NULL (column is nullable).
    if dob and not dob:match('^%d%d%d%d%-%d%d%-%d%d$') then
        dob = nil
    end

    return true, {
        firstname = firstname,
        lastname  = lastname,
        gender    = gender,
        model     = model,
        dob       = dob,  -- may be nil -> SQL NULL
    }
end

RegisterNetEvent('sl_identity:create', function(data)
    local src = source

    local ok, cleaned, err = validateCreate(data)
    if not ok then
        Config.Log('warn', ('create: validation failed src=%d reason=%s'):format(src, tostring(err)))
        TriggerClientEvent('sl_identity:createError', src, { reason = err })
        return
    end

    local license = ensureAccount(src)
    if not license then
        Config.Log('warn', ('create: no license for src=%d — rejecting'):format(src))
        TriggerClientEvent('sl_identity:createError', src, { reason = 'NO_LICENSE' })
        return
    end

    -- Enforce the per-account cap server-side (count living characters).
    local count = 0
    local okCount = pcall(function()
        count = tonumber(Core():dbScalar(
            'SELECT COUNT(*) FROM characters WHERE license = ? AND deleted_at IS NULL',
            { license }
        )) or 0
    end)
    if not okCount then
        Config.Log('error', ('create: cap count query failed src=%d'):format(src))
        TriggerClientEvent('sl_identity:createError', src, { reason = 'DB_ERROR' })
        return
    end
    if count >= Config.CharacterCap then
        Config.Log('warn', ('create: cap reached src=%d (%d/%d)'):format(src, count, Config.CharacterCap))
        TriggerClientEvent('sl_identity:createError', src, { reason = 'CAP_REACHED' })
        return
    end

    -- Insert. cash/bank default from the schema (500 / 5000). position/metadata NULL.
    -- IMPORTANT: a `nil` dob would create a HOLE in the params array constructor
    -- ({a,b,c,nil,e}), and Lua's `#` over a table with a hole is undefined — oxmysql
    -- could then bind the wrong number of params. So we branch the SQL: include the
    -- dob column ONLY when we have a valid date; otherwise let it default to NULL.
    local newId
    local okInsert = pcall(function()
        if cleaned.dob then
            newId = Core():dbInsert(
                'INSERT INTO characters (license, firstname, lastname, dob, model) VALUES (?,?,?,?,?)',
                { license, cleaned.firstname, cleaned.lastname, cleaned.dob, cleaned.model }
            )
        else
            newId = Core():dbInsert(
                'INSERT INTO characters (license, firstname, lastname, model) VALUES (?,?,?,?)',
                { license, cleaned.firstname, cleaned.lastname, cleaned.model }
            )
        end
    end)
    if not okInsert or not newId then
        Config.Log('error', ('create: dbInsert failed src=%d'):format(src))
        TriggerClientEvent('sl_identity:createError', src, { reason = 'DB_ERROR' })
        return
    end

    -- Load it into the live registry.
    local char
    local okLoad = pcall(function()
        char = Core():loadCharacter(src, newId)
    end)
    if not okLoad or not char then
        Config.Log('error', ('create: loadCharacter failed src=%d newId=%s'):format(src, tostring(newId)))
        TriggerClientEvent('sl_identity:createError', src, { reason = 'LOAD_FAILED' })
        return
    end

    Config.Log('info', ('create: NEW char src=%d id=%s (%s %s) model=%s -> CUSTOMIZE')
        :format(src, tostring(newId), cleaned.firstname, cleaned.lastname, char.model))

    -- NEW character -> CUSTOMIZATION first (fivem-appearance creator). The plane arrival
    -- is triggered from 'sl_identity:appearanceSaved' once the player finishes the creator.
    TriggerClientEvent('sl_identity:customize', src, { model = char.model })
end)

-- ── appearance saved from the creator -> persist, then ARRIVE ──────────────────
RegisterNetEvent('sl_identity:appearanceSaved', function(appearance)
    local src = source
    local char = Core():getChar(src)
    if not char then
        Config.Log('warn', ('appearanceSaved: no loaded char for src=%d — ignoring'):format(src))
        return
    end
    if type(appearance) == 'table' then
        Core():saveAppearance(char.charId, appearance)
        Config.Log('info', ('appearanceSaved: src=%d charId=%s -> ARRIVAL'):format(src, tostring(char.charId)))
    else
        Config.Log('warn', ('appearanceSaved: invalid appearance src=%d — arriving without'):format(src))
        appearance = nil
    end
    -- NEW character -> ENQUEUE for the next shared flight (Phase 1b). The queue batches
    -- players who arrive close together onto one plane; a lone player departs after the
    -- short window == the 1a path. It calls Arrival.begin(batch) on depart.
    ArrivalQueue.enqueue({ src = src, model = char.model, appearance = appearance })
end)

-- ── disconnect: drop the player from the arrival queue if they were waiting ─────
AddEventHandler('playerDropped', function()
    if ArrivalQueue and ArrivalQueue.remove then ArrivalQueue.remove(source) end
end)

-- ── expose entry internals for dev replay commands (same server Lua state) ─────
-- server/commands.lua reads these via the resource-global table (NOT an export
-- cache — that is the documented B3 anti-pattern). Only the few helpers the dev
-- commands need are exposed.
IdentityServer = {
    openEntry  = openEntry,
    getLicense = getLicense,
}
