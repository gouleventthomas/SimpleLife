--[[
    shared/config.lua — static config for sl_identity (client + server read it).

    Resource-global `Config` (no `local`) so every file in THIS resource sees it.
    (This Config is private to sl_identity; it does not collide with sl_core's Config,
     which lives in a different resource / Lua state.)

    ████ COORDS / HEADINGS / TIMEOUTS BELOW ARE LSIA PLACEHOLDERS ████
    They are deliberately conservative approximations of the Los Santos International
    main runway + apron and WILL be dialled in live in-game. Tune them with a coord
    tool; the reliability fallbacks guarantee the player still lands safely meanwhile.
]]

Config = {}

-- ── Characters ────────────────────────────────────────────────────────────────
Config.CharacterCap = 3  -- max living characters per account (license)

-- Freemode models mapped from the create-form gender ('m' | 'f').
Config.Models = {
    m = 'mp_m_freemode_01',
    f = 'mp_f_freemode_01',
}

-- ── Hidden hold (anti default-spawn) ──────────────────────────────────────────
-- Where we stash the ped (frozen, invisible) before a spawn is handed over, so the
-- vanilla GTA spawn point never flashes on screen. High in the sky, far from play.
Config.HoldCoord = vector3(-2000.0, 3500.0, 350.0)

-- Where the ped stands during the fivem-appearance CREATOR (new character, before the
-- plane). A clean, flat spot so the creator camera frames the character well.
-- PLACEHOLDER — tune with /here for a nicer backdrop.
Config.CustomizeCoord = {
    coord   = vector3(-1037.8, -2737.7, 20.2),
    heading = 337.9,
}

-- ── Validation caps for the create form (server-enforced) ─────────────────────
Config.NameMinLen = 2
Config.NameMaxLen = 24

-- ── Arrival: the plane cinematic (LSIA) ───────────────────────────────────────
-- `jumbo` (the jumbo jet) is NOT spawnable as a vehicle — it fails to load (confirmed
-- in-game). `jet` is the largest reliable airliner that loads; arrival.lua also tries
-- nimbus/luxor2 as fallbacks.
Config.PlaneModel = 'jet'
Config.PilotModel = 's_m_m_pilot_01'  -- ambient pilot ped in the cockpit (visual only)

-- STRAIGHT SCRIPTED LANDING. The plane spawns already ALIGNED on the runway heading,
-- far out + high on the extended centreline, then descends in a perfectly straight
-- line to `touchdown`, then rolls out to a stop — no AI banking/pivoting. Everything
-- derives from touchdown + heading, so calibration is easy:
--   • stand on the LSIA runway centreline -> `touchdown`
--   • face straight down the runway -> `heading`
-- ████ PLACEHOLDERS — dial in live with /arrival. ████
Config.Landing = {
    touchdown    = vector3(-1510.7, -2848.4, 14.0), -- wheels-down point on the LSIA runway (calibrated in-game via /here)
    heading      = 237.8,                            -- runway heading; the jet spawns ALIGNED to this (no AI pivot)
    approachDist = 2600.0,                           -- metres back along the heading where the jet spawns (far out)
    approachAlt  = 320.0,                            -- metres up at spawn -> ~7deg glide slope (realistic, AI-flown)
    approachSpeed = 100.0,                           -- forward speed handed to the jet on spawn so the AI can fly the descent
    rolloutDist  = 550.0,                            -- metres past touchdown where the AI brakes to a stop / parks
}

-- ── Arrival REPLAY (plays back recordings/arrival_last.json, recorded via /startrecarrivage) ──
-- speed > 1 plays the recorded flight faster (shortens a long recording WITHOUT
-- re-flying it); 1.0 = exactly as you flew it. Re-record anytime with /startrecarrivage.
Config.Replay = {
    speed = 1.0,
}

-- ── Arrival BUS SHUTTLE (REPLAY) ───────────────────────────────────────────────
-- After the plane disembark, a bus REPLAYS a route you recorded with /startrecbus
-- (recordings/bus_last.json): the player rides it from the tarmac to the drop-off, then
-- is forced off. The ROUTE + the DROP-OFF come entirely from the recording — drive the
-- bus once from the plane's park spot to wherever you want players to land, /stoprecbus.
-- `dropoff` below is only a legacy reference coord (the AI driver is gone); `speed` /
-- `driveTimeout` are unused by the replay (Config.Replay.speed controls playback tempo).
Config.Bus = {
    enabled      = true,
    model        = 'airbus',  -- the airport shuttle bus
    dropoff      = { coord = vector3(-1034.3, -2723.1, 13.7), heading = 239.2 }, -- legacy reference (replay uses the recording's last frame)
    boardLeadMs  = 5000,      -- 1b: grace after the plane disembark before the SHARED bus replay starts (covers the climb-out + bus spawn so all clients board in sync)
}

-- ── Arrival shared-start (Phase 1b) ────────────────────────────────────────────
-- The arrival is a deterministic timestamp-driven REPLAY, so a batch of players arrive
-- "in the same plane at the same moment" simply by all clients starting the replay at the
-- same wall-clock. The server tells each client to begin `spawnLeadMs` after it receives
-- the event (a relative lead — no cross-machine clock needed); since the server broadcasts
-- to the whole batch in one tick, they receive it within ping-jitter and the lead absorbs
-- that + model-load time, so every client's (coincident, local) plane moves in lockstep.
-- Co-presence is then FREE: OneSync syncs each real player's PED at the identical seat
-- world-coords of their overlapping local planes. SOLO (batch of 1) uses lead 0 = no delay.
Config.Arrival = {
    spawnLeadMs = 4000,  -- ms a BATCH waits (plane frozen at frame 1) before the shared replay starts; solo = 0
}

-- ── Arrival QUEUE (Phase 1b) ───────────────────────────────────────────────────
-- New characters finishing the creator are ENQUEUED instead of departing immediately, so
-- several who arrive close together board the SAME flight. A SHORT window (chosen) keeps the
-- wait tolerable for everyone: a lone player departs solo after at most `maxWaitMs` (== the
-- working 1a path). Overflow beyond a plane's seats is handled client-side by seat-stacking
-- (no batch is ever rejected), so maxBatch is just an "this group is big enough, go now" cap.
Config.Queue = {
    maxWaitMs = 40000,  -- HARD ceiling from the batch's first member -> depart (the ~40s short window)
    minBatch  = 2,      -- a formed group of >= this can depart early on quiet (don't idle the full window)
    quietMs   = 8000,   -- ...if no new member joined for this long
    maxBatch  = 8,      -- depart IMMEDIATELY at this size (seat-stacking handles > plane capacity)
    tickMs    = 250,    -- queue evaluation cadence (bounded ticker)
    broadcastMs = 1000, -- how often the waiting clients get a countdown refresh
}

-- Where the player ends up on foot after disembark (terminal-side tarmac).
-- This is the authoritative "you are now in Los Santos" spot. PLACEHOLDER.
Config.DisembarkPoint = {
    coord   = vector3(-1037.0, -2738.0, 20.2),
    heading = 330.0,
}

-- ── Resume / fallback spawn ───────────────────────────────────────────────────
-- Used when a character resumes but somehow has empty coords (e.g. a brand-new char
-- that never moved). A safe, known-good on-foot spot. PLACEHOLDER (LSIA terminal).
Config.FallbackSpawn = {
    coord   = vector3(-1037.0, -2738.0, 20.2),
    heading = 330.0,
}

-- ── Timeouts (ms) — every native wait is bounded ──────────────────────────────
Config.Timeouts = {
    model        = 10000,  -- RequestModel ceiling (player model or plane/pilot model)
    collision    = 8000,   -- HasCollisionLoadedAroundEntity ceiling on teleport
    land         = 75000,  -- MAX wait for the AI to land+stop (breaks EARLY on touchdown); only a true failure waits this long
    disembark    = 7000,   -- grace for the climb-out animation before we accept it / fall back
    sessionReady = 60000,  -- wait for NetworkIsSessionStarted before giving up (still proceeds)
    coreReady    = 60000,  -- wait for GlobalState.slCoreReady before signalling clientReady
    vehicleEnter = 6000,   -- (legacy) generic vehicle-enter grace
}

-- ── Camera (arrival cinematic) ────────────────────────────────────────────────
-- A chase cam offset behind/above the plane during descent. Tunable.
Config.Camera = {
    behind = -60.0,  -- metres behind the plane along its forward axis
    up     = 25.0,   -- metres above
    fov    = 50.0,
}

-- Deferrals message shown during the short connect gate.
Config.ConnectMessage = 'SimpleLife — preparing your arrival...'

-- Prefixed logger (mirrors sl_core's style but tagged for this resource).
---@param channel 'info'|'warn'|'error'|'debug'
---@param msg string
function Config.Log(channel, msg)
    local tag = '^4[sl_identity]^7'
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('%s %s%s^7'):format(tag, colour, tostring(msg)))
end
