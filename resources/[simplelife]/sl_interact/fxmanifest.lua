--[[
    sl_interact — SimpleLife interaction layer (a thin wrapper over ox_target).

    Every feature that wants a "look at it + press the target key" interaction goes
    THROUGH this resource's exports, never ox_target directly. This gives ONE place to:
      - swap the targeting backend later (ox_target -> anything),
      - apply SimpleLife defaults (icon / distance),
      - clean a feature's targets when that FEATURE restarts (ox_target would otherwise
        attribute the zones to sl_interact and never purge them),
      - optionally bridge into sl_core's AUTHORITATIVE interaction registry (server re-check).

    Pairs with sl_core/server/interact.lua: sl_interact is the CLIENT placement layer;
    sl_core is the SERVER authority for gated actions. A feature uses sl_interact to put the
    target in the world, and either does client work in onSelect (open a menu) or names a
    `serverInteraction` to fire sl_core's server-rechecked trigger.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_interact'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife interaction layer — a thin, cleanup-aware wrapper over ox_target.'

dependencies {
    'sl_core',
    'ox_target',
}

shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}
