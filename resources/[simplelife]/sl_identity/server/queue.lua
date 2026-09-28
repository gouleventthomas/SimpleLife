--[[
    server/queue.lua — Phase 1b arrival batching queue (`ArrivalQueue`).

    New characters that finish the creator are ENQUEUED here instead of departing
    immediately, so several who arrive close together board the SAME flight and land
    together. A SHORT window (Config.Queue.maxWaitMs, chosen ~40s) batches them; a lone
    player departs solo after the window — byte-for-byte the working 1a path.

    On depart we snapshot + CLEAR the queue under a `dispatching` guard (so a batch can
    never double-fire and late joiners open a FRESH window — never injected mid-flight),
    re-validate everyone is still online, then hand the batch to Arrival.begin (unchanged
    contract; it stamps the shared-start lead). Waiting clients get a bounded countdown via
    'sl_identity:queueTick'; a disconnect is cleaned by main.lua's playerDropped -> remove().

    Resource-global (same Lua state as Arrival) so it can call Arrival.begin directly.
    RELIABILITY: the evaluation ticker is pcall-wrapped + self-re-arming; every wait bounded;
    if Arrival.begin ever throws, each member is still sent a direct solo arrival (never stranded
    mid-creator). The queue holds NO authority over the ped — the client hold keeps waiters safe.
]]

ArrivalQueue = {}

local members      = {}    -- ordered: { { src, model, appearance, joinedAt }, ... }
local firstJoinMs  = nil   -- when the CURRENT batch's first member enqueued (drives maxWait)
local lastJoinMs   = nil   -- when the most recent member enqueued (drives the quiet-settle)
local dispatching  = false -- guard: a batch can't double-fire
local tickerOn     = false -- whether the evaluation thread is currently running
local lastBroadcast = 0

local function nowMs() return GetGameTimer() end
local function count() return #members end

-- ms until the current batch is force-dispatched (for the waiting countdown).
local function remainingMs()
    if not firstJoinMs then return 0 end
    local maxWait = (Config.Queue and Config.Queue.maxWaitMs) or 40000
    local r = maxWait - (nowMs() - firstJoinMs)
    return r > 0 and r or 0
end

-- push the live countdown to everyone currently waiting.
local function broadcast()
    local eta, n = remainingMs(), count()
    for _, m in ipairs(members) do
        TriggerClientEvent('sl_identity:queueTick', m.src, { etaMs = eta, count = n })
    end
end

-- drop any members who went offline (defensive; also done right before depart).
local function pruneOffline()
    for i = #members, 1, -1 do
        local m = members[i]
        if not (type(m.src) == 'number' and GetPlayerName(m.src)) then
            table.remove(members, i)
        end
    end
    if #members == 0 then firstJoinMs, lastJoinMs = nil, nil end
end

-- atomically take the whole queue and dispatch it as ONE flight.
local function depart(reason)
    if dispatching then return end
    dispatching = true

    pruneOffline()
    if #members == 0 then
        firstJoinMs, lastJoinMs, dispatching = nil, nil, false
        return
    end

    -- snapshot + CLEAR before dispatching, so anyone finishing the creator now opens a NEW
    -- window and can never be injected into this already-departed flight.
    local batch = {}
    for i = 1, #members do
        batch[i] = { src = members[i].src, model = members[i].model, appearance = members[i].appearance }
    end
    members = {}
    firstJoinMs, lastJoinMs = nil, nil

    Config.Log('info', ('queue: DEPART (%s) — %d passenger(s)'):format(tostring(reason), #batch))
    local ok, err = pcall(function() Arrival.begin(batch) end)
    if not ok then
        Config.Log('error', ('queue: Arrival.begin failed (%s) — direct fallback per player'):format(tostring(err)))
        for _, e in ipairs(batch) do
            TriggerClientEvent('sl_identity:arrival', e.src, {
                model = e.model, seat = 0, batch = 1, startInMs = 0, appearance = e.appearance,
            })
        end
    end

    dispatching = false
end

-- evaluate the depart triggers; return a reason string or nil.
local function shouldDepart()
    local n = count()
    if n == 0 then return nil end
    local Q = Config.Queue or {}
    if n >= (Q.maxBatch or 8) then return 'full' end
    if firstJoinMs and (nowMs() - firstJoinMs) >= (Q.maxWaitMs or 40000) then return 'maxWait' end
    if n >= (Q.minBatch or 2) and lastJoinMs and (nowMs() - lastJoinMs) >= (Q.quietMs or 8000) then return 'quiet' end
    return nil
end

-- start (or re-arm) the bounded evaluation ticker; it self-stops when the queue empties.
local function startTicker()
    if tickerOn then return end
    tickerOn = true
    CreateThread(function()
        while tickerOn do
            local ok, err = pcall(function()
                if count() == 0 then
                    tickerOn = false  -- sleep until the next enqueue re-arms us
                    return
                end
                pruneOffline()
                local reason = shouldDepart()
                if reason then
                    depart(reason)
                elseif (nowMs() - lastBroadcast) >= ((Config.Queue and Config.Queue.broadcastMs) or 1000) then
                    lastBroadcast = nowMs()
                    broadcast()
                end
            end)
            if not ok then
                Config.Log('error', ('queue: ticker error (re-arming): %s'):format(tostring(err)))
            end
            Wait((Config.Queue and Config.Queue.tickMs) or 250)
        end
    end)
end

--- Enqueue a finished-creator new character for the next shared flight.
---@param entry { src: integer, model: string, appearance: table? }
function ArrivalQueue.enqueue(entry)
    if type(entry) ~= 'table' or type(entry.src) ~= 'number' then
        Config.Log('warn', 'queue.enqueue: bad entry — ignoring')
        return
    end
    -- de-dupe: if this src is somehow already queued, refresh its data (never double-seat).
    for _, m in ipairs(members) do
        if m.src == entry.src then
            m.model, m.appearance = entry.model, entry.appearance
            Config.Log('warn', ('queue: src=%d already queued — updated in place'):format(entry.src))
            return
        end
    end

    local t = nowMs()
    if #members == 0 then firstJoinMs = t end
    lastJoinMs = t
    members[#members + 1] = { src = entry.src, model = entry.model, appearance = entry.appearance, joinedAt = t }
    Config.Log('info', ('queue: ENQUEUE src=%d (%d in queue, ~%ds left)')
        :format(entry.src, #members, math.floor(remainingMs() / 1000)))

    broadcast()      -- immediate feedback to the joiner + refresh the others
    startTicker()
end

--- Remove a src from the queue (playerDropped / cancel). Safe if absent.
---@param src integer
function ArrivalQueue.remove(src)
    local removed = false
    for i = #members, 1, -1 do
        if members[i].src == src then
            table.remove(members, i); removed = true
        end
    end
    if not removed then return end
    Config.Log('info', ('queue: remove src=%d (%d left)'):format(src, #members))
    if #members == 0 then firstJoinMs, lastJoinMs = nil, nil else broadcast() end
end

--- Dev introspection for /queuestatus.
function ArrivalQueue.status()
    local list = {}
    for i, m in ipairs(members) do
        list[i] = ('#%d src=%d age=%ds'):format(i, m.src, math.floor((nowMs() - m.joinedAt) / 1000))
    end
    return {
        count       = #members,
        remainingMs = remainingMs(),
        firstAgeMs  = firstJoinMs and (nowMs() - firstJoinMs) or 0,
        lastAgeMs   = lastJoinMs and (nowMs() - lastJoinMs) or 0,
        members     = list,
    }
end
