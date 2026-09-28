--[[
    sl_identity — SimpleLife character identity + arrival loop (PHASE 1a).

    Responsibilities:
      - account row bootstrap on connect (via sl_core, INSERT IGNORE accounts)
      - character SELECT / CREATE flow (drives sl_ui 'charselect' / 'charcreate')
      - RESUME an existing character at its saved coords (clean fade-in, no plane)
      - ARRIVAL cinematic for a NEW character: a vanilla airliner descends into LSIA,
        lands, taxis/stops, the player disembarks onto the tarmac.

    HARD RELIABILITY CONTRACT: a new player's first minutes must NEVER softlock.
    Every wait (model load, collision, plane landing) has a timeout + a guaranteed
    fallback that ends with the player CONTROLLABLE, VISIBLE, faded-in on the tarmac.

    DATA ACCESS: ONLY through sl_core exports (exports.sl_core:dbQuery/:dbInsert/...).
    This resource NEVER requires oxmysql and NEVER touches MariaDB directly.

    1b NOTE: the server arrival entry-point (Arrival.begin) already takes a LIST of
    players so a future shared-queue flight can board a BATCH on the SAME networked
    plane. 1a passes a list of one.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_identity'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife character identity: select/create, resume, and the plane arrival cinematic.'

-- Hard deps: sl_core (data + readiness) and sl_ui (the single NUI surface).
dependencies {
    'sl_core',
    'sl_ui',
}

shared_scripts {
    'shared/config.lua',
}

server_scripts {
    'server/arrival.lua',   -- Arrival.begin(list) entry-point (load first; queue/main call it)
    'server/queue.lua',     -- 1b: the ~40s arrival batching queue (ArrivalQueue); load before main.lua
    'server/main.lua',
    'server/commands.lua',  -- DEV replay commands (/arrival, /charselect, ...) — env=dev only
}

client_scripts {
    'client/main.lua',
    'client/arrival.lua',   -- the plane cinematic (invoked from main.lua's arrival handler)
    'client/recorder.lua',  -- DEV: /startrecarrivage /stoprecarrivage flight path recorder
}

-- Flight recordings must be STREAMED to the client so client-side LoadResourceFile
-- (in arrival.lua) can read them for the replay. A file written by /stoprecarrivage is
-- only sent to clients after the next `restart sl_identity` (the manifest is re-read).
files {
    'recordings/*.json',
}
