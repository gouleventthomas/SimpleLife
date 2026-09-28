--[[
    sl_phone/server/main.lua — device-centric phone authority.

    Phase 0: device provisioning (uuid in the phone item's metadata) + settings.
    Phase 1: contacts, notes, SMS, and real calls (pma-voice call channels).

    Source of truth. The device uuid is ALWAYS resolved from the player's INVENTORY,
    never trusted from the client — so a player can only operate the phone they hold and
    can only touch their own device's data. SMS/calls are addressed to the LINE (number);
    the recipient is found by scanning online players for the phone uuid that owns it.
]]

math.randomseed(math.floor(GetGameTimer()) + os.time())

local function trim(s) s = tostring(s or ''); return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
local function digits(s) return (tostring(s or ''):gsub('%D', '')) end

-- Clamp a string to at most `n` UTF-8 characters (Lua 5.4 utf8) without splitting a
-- codepoint mid-byte (a raw :sub() byte-cut could corrupt a trailing accented char).
local function clampChars(s, n)
    s = tostring(s or '')
    local ok, len = pcall(utf8.len, s)
    if not ok or not len then return s:sub(1, n) end -- invalid utf8: byte fallback
    if len <= n then return s end
    local off = utf8.offset(s, n + 1)
    return off and s:sub(1, off - 1) or s
end

-- ── device provisioning (Phase 0) ───────────────────────────────────────────────
local function genUuid()
    return (('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'):gsub('[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(v)
    end))
end

local function genUniqueNumber()
    for _ = 1, 60 do
        local n = (Config.NumberFormat):format(math.random(0, 9999999))
        if not exports.sl_core:dbScalar('SELECT 1 FROM phones WHERE number = ?', { n }) then
            return n
        end
    end
    return nil -- number space effectively exhausted (astronomically rare); caller aborts cleanly
end

local function decodeSettings(raw)
    local saved = {}
    if type(raw) == 'string' and raw ~= '' then
        local ok, d = pcall(json.decode, raw); if ok and type(d) == 'table' then saved = d end
    elseif type(raw) == 'table' then
        saved = raw
    end
    local out = {}
    for k, v in pairs(Config.DefaultSettings) do out[k] = v end
    for k, v in pairs(saved) do out[k] = v end
    return out
end

-- Resolve (and lazily provision) the device the player physically holds. uuid or nil.
local function resolveDevice(src)
    local meta = exports.sl_inventory:getItemMeta(src, Config.Item)
    if meta == nil then return nil end
    local uuid = meta.uuid
    if not uuid or uuid == '' then
        uuid = genUuid()
        exports.sl_inventory:setItemMeta(src, Config.Item, { uuid = uuid })
    end
    if not exports.sl_core:dbSingle('SELECT uuid FROM phones WHERE uuid = ?', { uuid }) then
        local number = genUniqueNumber()
        if not number then return nil end -- no free number (astronomically rare); abort, item keeps its uuid for a retry
        local char = exports.sl_core:getChar(src)
        exports.sl_core:dbInsert(
            'INSERT INTO phones (uuid, number, owner_char, settings) VALUES (?, ?, ?, ?)',
            { uuid, number, char and char.charId or nil, json.encode(Config.DefaultSettings) }
        )
    end
    return uuid
end

-- The held device as { uuid, number }, or nil if the player carries no phone.
local function deviceOf(src)
    local uuid = resolveDevice(src)
    if not uuid then return nil end
    local row = exports.sl_core:dbSingle('SELECT uuid, number FROM phones WHERE uuid = ?', { uuid })
    if not row then return nil end
    return { uuid = row.uuid, number = row.number }
end

-- The name `uuid`'s owner saved for `number` in their contacts (nil if not a contact).
local function contactName(uuid, number)
    if not uuid or not number or number == '' then return nil end
    return exports.sl_core:dbScalar(
        'SELECT name FROM phone_contacts WHERE phone_uuid = ? AND number = ? LIMIT 1', { uuid, number })
end

-- Find the ONLINE player currently holding the phone that owns `number`.
-- Returns (src, uuid): src=nil if number unknown OR holder offline; uuid=nil if unknown.
local function holderOfNumber(number)
    if not number or number == '' then return nil, nil end
    local uuid = exports.sl_core:dbScalar('SELECT uuid FROM phones WHERE number = ?', { number })
    if not uuid then return nil, nil end
    for _, pidStr in ipairs(GetPlayers()) do
        local pid = tonumber(pidStr)
        local metas = exports.sl_inventory:getItemMetaList(pid, Config.Item)
        for _, m in ipairs(metas or {}) do
            if m.uuid == uuid then return pid, uuid end
        end
    end
    return nil, uuid
end

local function pushNotify(src, app, title, body)
    TriggerClientEvent('sl_phone:notify', src, { app = app, title = title or '', body = body or '' })
end

-- installed-apps (iFruit Store): mandatory apps can't be removed; default = all installed.
local MANDATORY, APP_EXISTS = {}, {}
for _, a in ipairs(Config.Apps or {}) do
    APP_EXISTS[a.id] = true
    if a.mandatory then MANDATORY[a.id] = true end
end
local function removedOf(uuid)
    local rows = exports.sl_core:dbQuery('SELECT app FROM phone_removed_apps WHERE phone_uuid = ?', { uuid })
    local out = {}
    for _, r in ipairs(rows or {}) do out[#out + 1] = r.app end
    return out
end

-- ── calls registry ────────────────────────────────────────────────────────────
local activeCalls = {} -- callId -> { id, channel, caller={src,number,uuid}, callee={src,number,uuid}, state, startedAt, acceptedAt }
local nextCallId = 0

local function logCall(c, accepted, duration)
    exports.sl_core:dbInsert(
        'INSERT INTO phone_calls (caller, callee, accepted, duration) VALUES (?, ?, ?, ?)',
        { c.caller.number, c.callee.number, accepted and 1 or 0, duration or 0 })
end

local function callOf(src)
    for id, c in pairs(activeCalls) do
        if c.caller.src == src or c.callee.src == src then return id, c end
    end
end

local function endCall(id, c, reason)
    local wasActive = c.state == 'active'
    activeCalls[id] = nil
    if wasActive then
        exports['pma-voice']:setPlayerCall(c.caller.src, 0)
        exports['pma-voice']:setPlayerCall(c.callee.src, 0)
    end
    local duration = c.acceptedAt and (os.time() - c.acceptedAt) or 0
    logCall(c, wasActive, duration)
    TriggerClientEvent('sl_phone:callEnded', c.caller.src, { callId = id, reason = reason or 'ended', duration = duration })
    TriggerClientEvent('sl_phone:callEnded', c.callee.src, { callId = id, reason = reason or 'ended', duration = duration })
end

-- ── RPC methods (server-authoritative; each re-resolves the held device) ──────────
local ALLOWED_SETTINGS = { wallpaper = 'string', brightness = 'number', frame = 'string' }
local methods = {}

function methods.open(src)
    local uuid = resolveDevice(src)
    if not uuid then return { ok = false, reason = 'NO_PHONE' } end
    local row = exports.sl_core:dbSingle('SELECT uuid, number, settings FROM phones WHERE uuid = ?', { uuid })
    if not row then return { ok = false, reason = 'NO_PHONE' } end
    return {
        ok = true,
        state = {
            uuid = row.uuid, number = row.number, settings = decodeSettings(row.settings),
            apps = Config.Apps, dock = Config.Dock, accent = Config.Accent, env = GlobalState.slCoreEnv,
            removed = removedOf(uuid),
        },
    }
end

function methods.setSettings(src, params)
    local uuid = resolveDevice(src)
    if not uuid then return { ok = false, reason = 'NO_PHONE' } end
    local patch = params and params.patch
    if type(patch) ~= 'table' then return { ok = false, reason = 'BAD_PATCH' } end
    local clean = {}
    for k, v in pairs(patch) do if ALLOWED_SETTINGS[k] == type(v) then clean[k] = v end end
    if clean.brightness then clean.brightness = math.max(0.2, math.min(1.0, clean.brightness)) end
    if not next(clean) then return { ok = false, reason = 'NO_VALID_KEYS' } end
    local row = exports.sl_core:dbSingle('SELECT settings FROM phones WHERE uuid = ?', { uuid })
    local s = decodeSettings(row and row.settings)
    for k, v in pairs(clean) do s[k] = v end
    exports.sl_core:dbUpdate('UPDATE phones SET settings = ? WHERE uuid = ?', { json.encode(s), uuid })
    return { ok = true, settings = s }
end

-- contacts (device-centric: gated on phone_uuid = held device) -------------------
methods['contacts:list'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local rows = exports.sl_core:dbQuery(
        'SELECT id, name, number, favorite FROM phone_contacts WHERE phone_uuid = ? ORDER BY favorite DESC, name ASC',
        { dev.uuid })
    return { ok = true, contacts = rows or {} }
end

methods['contacts:add'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local name, number = clampChars(trim(p and p.name), 64), digits(p and p.number):sub(1, 20)
    if name == '' or number == '' then return { ok = false, reason = 'INVALID' } end
    local count = tonumber(exports.sl_core:dbScalar('SELECT COUNT(*) FROM phone_contacts WHERE phone_uuid = ?', { dev.uuid })) or 0
    if count >= Config.Limits.contacts then return { ok = false, reason = 'LIMIT' } end
    exports.sl_core:dbInsert('INSERT INTO phone_contacts (phone_uuid, name, number, favorite) VALUES (?, ?, ?, ?)',
        { dev.uuid, name, number, (p and p.favorite) and 1 or 0 })
    return methods['contacts:list'](src)
end

methods['contacts:update'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local id = tonumber(p and p.id); if not id then return { ok = false } end
    local name, number = clampChars(trim(p and p.name), 64), digits(p and p.number):sub(1, 20)
    if name == '' or number == '' then return { ok = false, reason = 'INVALID' } end
    exports.sl_core:dbUpdate('UPDATE phone_contacts SET name = ?, number = ?, favorite = ? WHERE id = ? AND phone_uuid = ?',
        { name, number, (p and p.favorite) and 1 or 0, id, dev.uuid })
    return methods['contacts:list'](src)
end

methods['contacts:delete'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local id = tonumber(p and p.id); if not id then return { ok = false } end
    exports.sl_core:dbUpdate('DELETE FROM phone_contacts WHERE id = ? AND phone_uuid = ?', { id, dev.uuid })
    return methods['contacts:list'](src)
end

-- notes (device-centric) ---------------------------------------------------------
methods['notes:list'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local rows = exports.sl_core:dbQuery(
        'SELECT id, title, body, updated_at FROM phone_notes WHERE phone_uuid = ? ORDER BY updated_at DESC', { dev.uuid })
    return { ok = true, notes = rows or {} }
end

methods['notes:save'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local title, body = clampChars(trim(p and p.title), 120), clampChars(tostring(p and p.body or ''), 8000)
    local id = tonumber(p and p.id)
    if id then
        exports.sl_core:dbUpdate('UPDATE phone_notes SET title = ?, body = ? WHERE id = ? AND phone_uuid = ?',
            { title, body, id, dev.uuid })
    else
        local count = tonumber(exports.sl_core:dbScalar('SELECT COUNT(*) FROM phone_notes WHERE phone_uuid = ?', { dev.uuid })) or 0
        if count >= Config.Limits.notes then return { ok = false, reason = 'LIMIT' } end
        exports.sl_core:dbInsert('INSERT INTO phone_notes (phone_uuid, title, body) VALUES (?, ?, ?)',
            { dev.uuid, title, body })
    end
    return methods['notes:list'](src)
end

methods['notes:delete'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local id = tonumber(p and p.id); if not id then return { ok = false } end
    exports.sl_core:dbUpdate('DELETE FROM phone_notes WHERE id = ? AND phone_uuid = ?', { id, dev.uuid })
    return methods['notes:list'](src)
end

-- SMS (addressed to numbers; my view = messages where I'm sender or receiver) ------
methods['sms:conversations'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local me = dev.number
    local rows = exports.sl_core:dbQuery([[
        SELECT t.other AS number,
               (SELECT CASE WHEN m.kind = 'transfer' THEN '💸 Paiement' ELSE m.body END FROM phone_messages m
                  WHERE (m.sender = ? AND m.receiver = t.other) OR (m.sender = t.other AND m.receiver = ?)
                  ORDER BY m.created_at DESC, m.id DESC LIMIT 1) AS last_body,
               MAX(t.created_at) AS last_at,
               SUM(CASE WHEN t.receiver = ? AND t.is_read = 0 THEN 1 ELSE 0 END) AS unread
        FROM (SELECT CASE WHEN sender = ? THEN receiver ELSE sender END AS other, body, created_at, receiver, is_read
              FROM phone_messages WHERE sender = ? OR receiver = ?) t
        GROUP BY t.other
        ORDER BY last_at DESC
    ]], { me, me, me, me, me, me })
    for _, r in ipairs(rows or {}) do r.name = contactName(dev.uuid, r.number) end
    return { ok = true, conversations = rows or {}, me = me }
end

methods['sms:thread'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local me, other = dev.number, digits(p and p.number)
    if other == '' then return { ok = false, reason = 'INVALID' } end
    local rows = exports.sl_core:dbQuery([[
        SELECT id, sender, receiver, body, kind, amount, created_at FROM phone_messages
        WHERE (sender = ? AND receiver = ?) OR (sender = ? AND receiver = ?)
        ORDER BY created_at ASC, id ASC LIMIT 200
    ]], { me, other, other, me })
    exports.sl_core:dbUpdate('UPDATE phone_messages SET is_read = 1 WHERE receiver = ? AND sender = ? AND is_read = 0',
        { me, other })
    return { ok = true, messages = rows or {}, me = me, number = other, name = contactName(dev.uuid, other) }
end

methods['sms:send'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local me, to, body = dev.number, digits(p and p.to), clampChars(trim(p and p.body), 1000)
    if to == '' or body == '' then return { ok = false, reason = 'INVALID' } end
    if to == me then return { ok = false, reason = 'SELF' } end
    -- resolve the recipient up front; reject numbers that belong to no phone (no orphan rows).
    local rsrc, ruuid = holderOfNumber(to)
    if not ruuid then return { ok = false, reason = 'UNKNOWN_NUMBER' } end
    local id = exports.sl_core:dbInsert('INSERT INTO phone_messages (sender, receiver, body, is_read) VALUES (?, ?, ?, 0)',
        { me, to, body })
    -- deliver live only if the recipient is online. ONE channel for the banner (sl_phone:sms);
    -- the client builds the notification from it (no separate pushNotify => no double banner).
    if rsrc then
        TriggerClientEvent('sl_phone:sms', rsrc,
            { id = id, from = me, name = contactName(ruuid, me), body = body, created_at = os.date('%Y-%m-%d %H:%M:%S') })
    end
    return { ok = true, id = id }
end

-- calls (real audio via pma-voice call channels) ----------------------------------
methods['calls:start'] = function(src, p)
    if GetConvarInt('voice_enableCalls', 0) ~= 1 then return { ok = false, reason = 'CALLS_DISABLED' } end
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local to = digits(p and p.number)
    if to == '' then return { ok = false, reason = 'INVALID' } end
    if to == dev.number then return { ok = false, reason = 'SELF' } end
    if callOf(src) then return { ok = false, reason = 'BUSY' } end
    local calleeSrc, calleeUuid = holderOfNumber(to)
    if not calleeUuid then return { ok = false, reason = 'UNKNOWN_NUMBER' } end
    if not calleeSrc then return { ok = false, reason = 'OFFLINE' } end
    if calleeSrc == src then return { ok = false, reason = 'SELF' } end
    if callOf(calleeSrc) then return { ok = false, reason = 'BUSY_TARGET' } end

    nextCallId = nextCallId + 1
    local id = nextCallId
    local call = {
        id = id, channel = 1000000 + id, state = 'ringing', startedAt = os.time(),
        caller = { src = src, number = dev.number, uuid = dev.uuid },
        callee = { src = calleeSrc, number = to, uuid = calleeUuid },
    }
    activeCalls[id] = call
    local calleeName = contactName(dev.uuid, to)         -- how the caller sees the callee
    local callerName = contactName(calleeUuid, dev.number) -- how the callee sees the caller
    TriggerClientEvent('sl_phone:callOutgoing', src, { callId = id, number = to, name = calleeName })
    TriggerClientEvent('sl_phone:callIncoming', calleeSrc, { callId = id, number = dev.number, name = callerName })

    SetTimeout(30000, function()
        local c = activeCalls[id]
        if c and c.state == 'ringing' then
            activeCalls[id] = nil
            logCall(c, false, 0)
            TriggerClientEvent('sl_phone:callEnded', c.caller.src, { callId = id, reason = 'no_answer' })
            TriggerClientEvent('sl_phone:callEnded', c.callee.src, { callId = id, reason = 'missed' })
            pushNotify(c.callee.src, 'phone', callerName or c.caller.number, 'Appel manqué')
        end
    end)
    return { ok = true, callId = id, number = to, name = calleeName }
end

methods['calls:accept'] = function(src, p)
    local id = tonumber(p and p.callId); local c = id and activeCalls[id]
    if not c or c.callee.src ~= src or c.state ~= 'ringing' then return { ok = false } end
    c.state = 'active'; c.acceptedAt = os.time()
    exports['pma-voice']:setPlayerCall(c.caller.src, c.channel)
    exports['pma-voice']:setPlayerCall(c.callee.src, c.channel)
    TriggerClientEvent('sl_phone:callAccepted', c.caller.src, { callId = id })
    TriggerClientEvent('sl_phone:callAccepted', c.callee.src, { callId = id })
    return { ok = true }
end

methods['calls:decline'] = function(src, p)
    local id = tonumber(p and p.callId); local c = id and activeCalls[id]
    if not c or c.callee.src ~= src or c.state ~= 'ringing' then return { ok = false } end
    activeCalls[id] = nil
    logCall(c, false, 0)
    TriggerClientEvent('sl_phone:callEnded', c.caller.src, { callId = id, reason = 'declined' })
    TriggerClientEvent('sl_phone:callEnded', c.callee.src, { callId = id, reason = 'declined' })
    return { ok = true }
end

methods['calls:hangup'] = function(src, p)
    local id = tonumber(p and p.callId); local c = id and activeCalls[id]
    if not c or (c.caller.src ~= src and c.callee.src ~= src) then return { ok = false } end
    endCall(id, c, 'ended')
    return { ok = true }
end

methods['calls:recents'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local me = dev.number
    local rows = exports.sl_core:dbQuery([[
        SELECT id, accepted, duration, created_at,
               CASE WHEN caller = ? THEN 'out' ELSE 'in' END AS dir,
               CASE WHEN caller = ? THEN callee ELSE caller END AS number
        FROM phone_calls WHERE caller = ? OR callee = ?
        ORDER BY created_at DESC LIMIT 100
    ]], { me, me, me, me })
    for _, r in ipairs(rows or {}) do r.name = contactName(dev.uuid, r.number) end
    return { ok = true, recents = rows or {} }
end

-- gallery / media (device-centric: photos travel with the device; stored base64 in DB) -------
local function isImageDataUri(s, maxLen)
    return type(s) == 'string' and #s <= maxLen and s:sub(1, 11) == 'data:image/'
end

methods['gallery:list'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    -- length-guard the thumb so a malformed row can never bloat the list payload.
    local rows = exports.sl_core:dbQuery(
        'SELECT id, CASE WHEN LENGTH(thumb) <= 80000 THEN thumb ELSE NULL END AS thumb, created_at ' ..
        'FROM phone_media WHERE phone_uuid = ? ORDER BY created_at DESC, id DESC LIMIT 60',
        { dev.uuid })
    return { ok = true, media = rows or {} }
end

methods['gallery:get'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local id = tonumber(p and p.id); if not id then return { ok = false } end
    local data = exports.sl_core:dbScalar('SELECT data FROM phone_media WHERE id = ? AND phone_uuid = ?', { id, dev.uuid })
    if not data then return { ok = false } end
    return { ok = true, data = data }
end

methods['gallery:save'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local full, thumb = p and p.data, p and p.thumb
    if not isImageDataUri(full, 1300000) then return { ok = false, reason = 'BAD_IMAGE' } end
    if not isImageDataUri(thumb, 80000) then thumb = nil end -- drop missing/oversized thumb (grid shows a placeholder, full loads on tap)
    local count = tonumber(exports.sl_core:dbScalar('SELECT COUNT(*) FROM phone_media WHERE phone_uuid = ?', { dev.uuid })) or 0
    if count >= Config.Limits.media then return { ok = false, reason = 'LIMIT' } end
    local id = exports.sl_core:dbInsert('INSERT INTO phone_media (phone_uuid, thumb, data) VALUES (?, ?, ?)',
        { dev.uuid, thumb, full })
    return { ok = true, id = id }
end

methods['gallery:delete'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local id = tonumber(p and p.id); if not id then return { ok = false } end
    exports.sl_core:dbUpdate('DELETE FROM phone_media WHERE id = ? AND phone_uuid = ?', { id, dev.uuid })
    return methods['gallery:list'](src)
end

-- ── economy: bank (real sl_core money) + crypto (device-centric coins) ──────────────
local COIN_OK = {}
for _, c in ipairs(Config.Coins or {}) do COIN_OK[c.id] = true end

local MAX_AMOUNT = 1000000000 -- 1B sanity cap on a single phone transfer / request

local function logTx(fromN, toN, amount, reason, kind)
    exports.sl_core:dbInsert('INSERT INTO phone_bank_tx (from_number, to_number, amount, reason, kind) VALUES (?, ?, ?, ?, ?)',
        { fromN, toN, amount, reason, kind or 'transfer' })
end

-- Atomic bank transfer from `src` to the ONLINE holder of `toNumber` (sl_core money).
-- Returns ok, reasonOrTargetSrc. Bank transfers require the recipient online (real per-char money).
local function bankTransfer(src, fromNumber, toNumber, amount, reason, kind)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or amount > MAX_AMOUNT then return false, 'BAD_AMOUNT' end
    if toNumber == '' then return false, 'INVALID' end
    if toNumber == fromNumber then return false, 'SELF' end
    local tsrc, tuuid = holderOfNumber(toNumber)
    if not tuuid then return false, 'UNKNOWN_NUMBER' end
    if not tsrc then return false, 'OFFLINE' end
    local ok = exports.sl_core:economyTransfer(src, tsrc, 'bank', amount, reason or 'phone:transfer')
    if ok ~= true then return false, 'NO_FUNDS' end
    logTx(fromNumber, toNumber, amount, reason, kind or 'transfer')
    pushNotify(tsrc, 'wallet', 'Virement reçu', ('+%d$ de %s'):format(amount, contactName(tuuid, fromNumber) or fromNumber))
    return true, tsrc
end

methods['wallet:state'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local bal = exports.sl_core:economyBalance(src) or {}
    return { ok = true, cash = bal.cash or 0, bank = bal.bank or 0, number = dev.number }
end

methods['wallet:history'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local me = dev.number
    local rows = exports.sl_core:dbQuery([[
        SELECT id, from_number, to_number, amount, reason, kind, created_at,
               CASE WHEN from_number = ? THEN 'out' ELSE 'in' END AS dir
        FROM phone_bank_tx WHERE from_number = ? OR to_number = ?
        ORDER BY created_at DESC, id DESC LIMIT 50
    ]], { me, me, me })
    return { ok = true, history = rows or {} }
end

methods['wallet:transfer'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local ok, reason = bankTransfer(src, dev.number, digits(p and p.to), p and p.amount, trim(p and p.reason):sub(1, 100), 'transfer')
    if not ok then return { ok = false, reason = reason } end
    local bal = exports.sl_core:economyBalance(src) or {}
    return { ok = true, cash = bal.cash or 0, bank = bal.bank or 0 }
end

methods['messages:pay'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local to = digits(p and p.to)
    local ok, reason = bankTransfer(src, dev.number, to, p and p.amount, 'SMS', 'transfer')
    if not ok then return { ok = false, reason = reason } end
    local amount = math.floor(tonumber(p and p.amount) or 0)
    local id = exports.sl_core:dbInsert(
        'INSERT INTO phone_messages (sender, receiver, body, kind, amount, is_read) VALUES (?, ?, ?, ?, ?, 0)',
        { dev.number, to, '', 'transfer', amount })
    local rsrc, ruuid = holderOfNumber(to)
    if rsrc then
        TriggerClientEvent('sl_phone:sms', rsrc, { id = id, from = dev.number, name = contactName(ruuid, dev.number),
            body = '', kind = 'transfer', amount = amount, created_at = os.date('%Y-%m-%d %H:%M:%S') })
    end
    return { ok = true }
end

methods['wallet:requestMoney'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local to = digits(p and p.to)
    local amount = math.floor(tonumber(p and p.amount) or 0)
    if to == '' or amount <= 0 or amount > MAX_AMOUNT then return { ok = false, reason = 'INVALID' } end
    if to == dev.number then return { ok = false, reason = 'SELF' } end
    local tsrc, tuuid = holderOfNumber(to)
    if not tuuid then return { ok = false, reason = 'UNKNOWN_NUMBER' } end
    local pending = tonumber(exports.sl_core:dbScalar('SELECT COUNT(*) FROM phone_pay_requests WHERE from_number = ? AND to_number = ? AND status = ?', { dev.number, to, 'pending' })) or 0
    if pending >= 10 then return { ok = false, reason = 'TOO_MANY' } end
    exports.sl_core:dbInsert('INSERT INTO phone_pay_requests (from_number, to_number, amount, reason) VALUES (?, ?, ?, ?)',
        { dev.number, to, amount, trim(p and p.reason):sub(1, 100) })
    if tsrc then
        pushNotify(tsrc, 'wallet', 'Demande de paiement', ('%s demande %d$'):format(contactName(tuuid, dev.number) or dev.number, amount))
    end
    return { ok = true }
end

methods['wallet:requests'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local me = dev.number
    local incoming = exports.sl_core:dbQuery('SELECT id, from_number AS number, amount, reason, created_at FROM phone_pay_requests WHERE to_number = ? AND status = ? ORDER BY created_at DESC LIMIT 50', { me, 'pending' })
    local outgoing = exports.sl_core:dbQuery('SELECT id, to_number AS number, amount, reason, status, created_at FROM phone_pay_requests WHERE from_number = ? ORDER BY created_at DESC LIMIT 50', { me })
    for _, r in ipairs(incoming or {}) do r.name = contactName(dev.uuid, r.number) end
    for _, r in ipairs(outgoing or {}) do r.name = contactName(dev.uuid, r.number) end
    return { ok = true, incoming = incoming or {}, outgoing = outgoing or {} }
end

methods['wallet:respondRequest'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local id = tonumber(p and p.id); if not id then return { ok = false } end
    local accept = p and p.accept == true
    -- I'm the PAYER (to_number = me).
    local row = exports.sl_core:dbSingle('SELECT from_number, amount, status FROM phone_pay_requests WHERE id = ? AND to_number = ?', { id, dev.number })
    if not row or row.status ~= 'pending' then return { ok = false, reason = 'GONE' } end
    if not accept then
        exports.sl_core:dbUpdate('UPDATE phone_pay_requests SET status = ? WHERE id = ? AND status = ?', { 'declined', id, 'pending' })
        local rsrc, ruuid = holderOfNumber(row.from_number)
        if rsrc then pushNotify(rsrc, 'wallet', 'Demande refusée', contactName(ruuid, dev.number) or dev.number) end
        return { ok = true }
    end
    -- claim the request atomically BEFORE paying (no double-accept), then pay the requester.
    local claimed = exports.sl_core:dbUpdate('UPDATE phone_pay_requests SET status = ? WHERE id = ? AND status = ?', { 'accepted', id, 'pending' })
    if (tonumber(claimed) or 0) < 1 then return { ok = false, reason = 'GONE' } end
    local ok, reason = bankTransfer(src, dev.number, row.from_number, row.amount, 'Demande', 'request')
    if not ok then
        exports.sl_core:dbUpdate('UPDATE phone_pay_requests SET status = ? WHERE id = ?', { 'pending', id }) -- revert on failure
        return { ok = false, reason = reason }
    end
    return { ok = true }
end

-- crypto: device-centric coin balances (DECIMAL math done in SQL for exactness) ----------
local function grantCrypto(src, coin, amount)
    if not COIN_OK[coin] then return false end
    amount = math.floor((tonumber(amount) or 0) * 1e8) / 1e8
    if amount <= 0 then return false end
    local uuid = resolveDevice(src); if not uuid then return false end
    exports.sl_core:dbUpdate('INSERT INTO phone_crypto (phone_uuid, coin, amount) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + ?',
        { uuid, coin, amount, amount })
    return true
end

methods['crypto:state'] = function(src)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local rows = exports.sl_core:dbQuery('SELECT coin, amount FROM phone_crypto WHERE phone_uuid = ? AND amount > 0', { dev.uuid })
    return { ok = true, holdings = rows or {}, coins = Config.Coins }
end

methods['crypto:transfer'] = function(src, p)
    local dev = deviceOf(src); if not dev then return { ok = false, reason = 'NO_PHONE' } end
    local coin = tostring(p and p.coin or '')
    if not COIN_OK[coin] then return { ok = false, reason = 'BAD_COIN' } end
    local amount = tonumber(p and p.amount) or 0
    if amount ~= amount or amount <= 0 then return { ok = false, reason = 'BAD_AMOUNT' } end -- reject NaN / <=0
    amount = math.floor(amount * 1e8) / 1e8
    if amount <= 0 then return { ok = false, reason = 'BAD_AMOUNT' } end
    local to = digits(p and p.to)
    local rsrc, ruuid = holderOfNumber(to)
    if not ruuid then return { ok = false, reason = 'UNKNOWN_NUMBER' } end
    if ruuid == dev.uuid then return { ok = false, reason = 'SELF' } end
    -- deduct with an affected-rows guard (0 rows => insufficient => no credit, no dupe), then credit.
    local deducted = exports.sl_core:dbUpdate('UPDATE phone_crypto SET amount = amount - ? WHERE phone_uuid = ? AND coin = ? AND amount >= ?',
        { amount, dev.uuid, coin, amount })
    if (tonumber(deducted) or 0) < 1 then return { ok = false, reason = 'INSUFFICIENT' } end
    exports.sl_core:dbUpdate('INSERT INTO phone_crypto (phone_uuid, coin, amount) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + ?',
        { ruuid, coin, amount, amount })
    if rsrc then pushNotify(rsrc, 'crypto', 'Crypto reçue', ('+%s %s'):format(tostring(amount), coin)) end
    return { ok = true }
end

-- iFruit Store: install/uninstall apps (device-centric). Mandatory apps can't be removed.
methods['store:install'] = function(src, p)
    local uuid = resolveDevice(src); if not uuid then return { ok = false, reason = 'NO_PHONE' } end
    local app = tostring(p and p.app or '')
    if not APP_EXISTS[app] then return { ok = false, reason = 'UNKNOWN' } end
    exports.sl_core:dbUpdate('DELETE FROM phone_removed_apps WHERE phone_uuid = ? AND app = ?', { uuid, app })
    return { ok = true, removed = removedOf(uuid) }
end

methods['store:uninstall'] = function(src, p)
    local uuid = resolveDevice(src); if not uuid then return { ok = false, reason = 'NO_PHONE' } end
    local app = tostring(p and p.app or '')
    if not APP_EXISTS[app] then return { ok = false, reason = 'UNKNOWN' } end
    if MANDATORY[app] then return { ok = false, reason = 'MANDATORY' } end
    exports.sl_core:dbUpdate('INSERT IGNORE INTO phone_removed_apps (phone_uuid, app) VALUES (?, ?)', { uuid, app })
    return { ok = true, removed = removedOf(uuid) }
end

-- ── bridge ───────────────────────────────────────────────────────────────────────
-- per-source min-interval on the INSERT-producing methods (anti-flood).
local RATE_LIMITED = {
    ['contacts:add'] = true, ['notes:save'] = true, ['sms:send'] = true, ['calls:start'] = true,
    ['gallery:save'] = true, ['wallet:transfer'] = true, ['wallet:requestMoney'] = true,
    ['wallet:respondRequest'] = true, ['messages:pay'] = true, ['crypto:transfer'] = true,
    ['store:install'] = true, ['store:uninstall'] = true,
}
local lastRpc = {}

lib.callback.register('sl_phone:rpc', function(src, data)
    local method = data and data.method
    local fn = method and methods[method]
    if not fn then return { ok = false, reason = 'UNKNOWN_METHOD' } end
    if RATE_LIMITED[method] then
        local now = GetGameTimer()
        lastRpc[src] = lastRpc[src] or {}
        if lastRpc[src][method] and (now - lastRpc[src][method]) < Config.Limits.rpcIntervalMs then
            return { ok = false, reason = 'RATE' }
        end
        lastRpc[src][method] = now
    end
    local ok, res = pcall(fn, src, data and data.params)
    if not ok then
        Config.Log('error', ('rpc %s failed: %s'):format(tostring(method), tostring(res)))
        return { ok = false, reason = 'ERROR' }
    end
    return res or { ok = false }
end)

lib.callback.register('sl_phone:hasPhone', function(src)
    return exports.sl_inventory:hasItem(src, Config.Item) == true
end)

-- grant crypto to a player's device (for jobs / illegal activities / admin). Colon export.
exports('addCrypto', function(src, coin, amount) return grantCrypto(src, coin, amount) end)

-- Cross-resource helpers (used by sl_vehicles leads / theft alerts).
exports('getNumber', function(src) local d = deviceOf(src); return d and d.number or nil end)
exports('pushNotification', function(src, app, title, body) pushNotify(src, app or 'vehicles', title, body) end)

RegisterCommand('givecrypto', function(src, args)
    if src == 0 or GlobalState.slCoreEnv ~= 'dev' then return end
    local coin, amount = args[1], tonumber(args[2]) or 1
    if grantCrypto(src, coin, amount) then
        TriggerClientEvent('sl_phone:notify', src, { app = 'crypto', title = 'Crypto', body = ('+%s %s'):format(tostring(amount), tostring(coin)) })
    else
        TriggerClientEvent('sl_phone:notify', src, { app = 'crypto', title = 'Crypto', body = 'Coin inconnu ou montant invalide' })
    end
end, false)

-- end any call a dropping player is in, freeing the other side.
AddEventHandler('playerDropped', function()
    local src = source
    local id, c = callOf(src)
    if id and c then endCall(id, c, 'ended') end
    lastRpc[src] = nil
end)

Config.Log('info', 'ready — phone authority (Phase 1: contacts/notes/SMS/calls)')
