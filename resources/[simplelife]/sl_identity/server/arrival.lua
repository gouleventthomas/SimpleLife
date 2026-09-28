--[[
    server/arrival.lua — the SERVER arrival entry-point.

    Phase 1a builds the SOLO arrival, but the entry-point is deliberately shaped to
    take a LIST of players so Phase 1b (the ~2-minute shared queue) can board a BATCH
    of new arrivals onto the SAME networked plane and land them together. 1a passes a
    list of exactly one.

    Each player is assigned a SEAT INDEX (passenger seat in the airliner). For a solo
    arrival that is seat 0's neighbour onward — we start passengers at seat index 0
    (front-right) and increment; the pilot occupies the driver seat (-1) on the CLIENT
    that owns/creates the plane. In 1a the client creates the plane locally and seats
    only itself; in 1b the plane is networked and the host seats the batch.

    This module owns NO DB state — it is pure orchestration. It is resource-global
    (`Arrival`, no `local`) so server/main.lua can call Arrival.begin(...) directly
    within this resource's shared Lua state.
]]

Arrival = {}

--- Load + downsample a recorded path file (SERVER-side — the server can read any resource
--- file, unlike the client). Sent to clients as compact [t,x,y,z,pitch,roll,yaw] arrays to
--- keep the network event small. Re-read each call so a fresh recording takes effect WITHOUT
--- a restart. Returns an array of frame-arrays, or nil if there is no/invalid recording.
local function loadPathFile(file)
    local raw = LoadResourceFile(GetCurrentResourceName(), file)
    if not raw or raw == '' then return nil end
    local ok, all = pcall(json.decode, raw)
    if not ok or type(all) ~= 'table' or #all < 2 then return nil end
    local n = #all
    local step = math.max(1, math.floor(n / 500))  -- downsample to ~500 frames
    local out = {}
    for i = 1, n, step do
        local f = all[i]
        out[#out + 1] = { f.t, f.x, f.y, f.z, f.pitch, f.roll, f.yaw }
    end
    local last = all[n]  -- always include the final parked frame
    out[#out + 1] = { last.t, last.x, last.y, last.z, last.pitch, last.roll, last.yaw }
    return out
end

--- The recorded PLANE flight (recordings/arrival_last.json, via /startrecarrivage).
function Arrival.loadFrames() return loadPathFile('recordings/arrival_last.json') end

--- The recorded BUS shuttle route (recordings/bus_last.json, via /startrecbus). Replayed
--- after the plane disembark; nil -> the client falls back to a direct disembark teleport.
function Arrival.loadBusFrames() return loadPathFile('recordings/bus_last.json') end

--- Begin an arrival for a LIST of players. Each entry: { src = <serverId>, model = <string> }.
--- Sends 'sl_identity:arrival' to each client with its model + seat index + a shared-start
--- lead. The heavy lifting (plane spawn, landing, disembark) happens CLIENT-side per the
--- experience spec; this server side only assigns seats and the shared departure timing.
---
--- 1a: a single-element list (startInMs = 0, immediate). 1b: a batch dispatched by
--- ArrivalQueue (startInMs = Config.Arrival.spawnLeadMs so all clients begin the replay in
--- lockstep). Seat indices are 1:1 with list order; overflow is stacked client-side.
---@param list { src: integer, model: string }[]
---@param opts { simBatch: integer }? dev-only: pretend the batch is this big (timing test from one account)
function Arrival.begin(list, opts)
    if type(list) ~= 'table' or #list == 0 then
        Config.Log('warn', 'Arrival.begin called with an empty list — nothing to do')
        return
    end

    -- Effective batch size drives the shared-start lead: a true batch (or a dev sim) starts
    -- after a lead so every client's deterministic replay departs at the same wall-clock; a
    -- lone player (batch of 1) keeps lead 0 == the byte-for-byte working 1a path (no delay).
    local batchN = #list
    if opts and type(opts.simBatch) == 'number' and opts.simBatch > batchN then batchN = opts.simBatch end
    local startInMs = (batchN > 1) and ((Config.Arrival and Config.Arrival.spawnLeadMs) or 4000) or 0

    -- Load the recorded flight path ONCE; each arriving client replays it.
    local frames = Arrival.loadFrames()
    if not frames then
        Config.Log('warn', 'arrival: no recording on disk (recordings/arrival_last.json) — clients fall back to direct disembark')
    end

    -- Load the recorded bus route ONCE; clients replay it after the plane disembark.
    local busFrames = Arrival.loadBusFrames()
    if not busFrames then
        Config.Log('warn', 'arrival: no bus recording (recordings/bus_last.json) — clients fall back to direct disembark teleport')
    end

    -- Assign seats by list order. Seat 0 is the first passenger seat; pilot is -1.
    for index, entry in ipairs(list) do
        local src = entry.src
        local model = entry.model
        if type(src) == 'number' and GetPlayerName(src) then
            local seat = index - 1  -- 0-based passenger seat index
            Config.Log('info', ('arrival: dispatching src=%d model=%s seat=%d')
                :format(src, tostring(model), seat))
            -- Each arriving client runs its own cinematic (1a). In 1b the host client
            -- will instead network one plane and seat the batch; the server contract
            -- (this event + payload) stays the same so the client can branch later.
            TriggerClientEvent('sl_identity:arrival', src, {
                model      = model,
                seat       = seat,
                batch      = batchN,        -- so the client can tell solo (1) from a queue (>1)
                startInMs  = startInMs,     -- 1b: ms after receipt to begin the replay (shared lockstep; 0 = solo, immediate)
                frames     = frames,        -- recorded flight path (server-read; the client replays it)
                busFrames  = busFrames,     -- recorded bus route (replayed after the plane disembark)
                appearance = entry.appearance,  -- full look; applied after model (which would reset it)
            })
        else
            Config.Log('warn', ('arrival: skipping invalid/offline src=%s'):format(tostring(src)))
        end
    end
end
