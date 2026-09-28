--[[
    sl_core — SimpleLife framework foundation resource.

    THE ONE authoritative resource:
      - the only resource that depends on oxmysql
      - the only resource that runs DB migrations
      - sole owner of the player/character registry, event bus, service registry,
        world-interaction registry, and core services (economy, notifications, autosave).

    Feature resources are dumb plugins: they call sl_core via exports / bus / services
    and NEVER touch MariaDB directly.

    ────────────────────────────────────────────────────────────────────────────
    CROSS-FILE / CROSS-RESOURCE CONVENTION (bug class B3 — fixed by construction):

      Within THIS resource FiveM shares a SINGLE Lua state across every server_script.
      A NON-local (resource-global) table is therefore shared across all our files.
      We exploit that: `SLCore` is declared resource-global in server/_bootstrap.lua
      (no `local`) and every server file attaches its module table to SLCore.modules.

      NEVER cache `local X = exports['sl_core']` at a file's top level hoping it
      crosses files — that pattern caused the original nil-deref bug. Inside this
      resource use the shared global `SLCore`. From OTHER (future feature) resources,
      resolve live at each call site and use the FLAT exported FUNCTIONS with COLON
      syntax:
          local Core = exports.sl_core
          Core:isReady()
          Core:getChar(src)
          Core:addMoney(src, 'cash', 100, 'reward')
          Core:call('economy.credit', src, 'bank', 50, 'payday')
      COLON is the documented convention. The CFX exports proxy wraps handlers as
      `function(self, ...) return handler(...) end`, so the colon form passes the
      proxy as `self` and delivers your real args intact; the DOT form would DROP the
      first argument for any export that takes one (zero-arg exports work either way).
      Do NOT call `Core:use('players')` cross-resource to then invoke a method on the
      returned table — module tables don't marshal callable methods across the export
      boundary; use the flat exports instead.
    ────────────────────────────────────────────────────────────────────────────
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_core'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife framework foundation: registry, bus, players, economy, migrations.'

dependencies {
    'oxmysql',
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/codec.lua',
}

server_scripts {
    -- oxmysql Lua wrapper exposes MySQL.* (query/single/scalar/insert/update/transaction).
    '@oxmysql/lib/MySQL.lua',

    -- Resource-global bootstrap MUST load first: defines SLCore = { modules = {}, ... }.
    'server/_bootstrap.lua',

    -- Core building blocks (order: low-level -> high-level; boot.lua runs LAST).
    'server/db.lua',        -- the ONLY file that calls MySQL.*
    'server/sql.lua',       -- comment/string-aware statement splitter (B5)
    'server/migrate.lua',   -- migration runner (B1+B2+B5). Does NOT auto-run.
    'server/registry.lua',  -- service registry
    'server/bus.lua',       -- validated event bus
    'server/players.lua',   -- player/character registry
    'server/economy.lua',   -- economy services on top of players
    'server/needs.lua',     -- hunger/thirst (persisted in char metadata; consumed via item:used)
    'server/interact.lua',  -- authoritative interaction registry
    'server/commands.lua',  -- /sl admin command

    -- Awaited boot sequence — runs migrations ONCE, flips ready. Loads LAST.
    'server/boot.lua',
}

client_scripts {
    'client/core.lua',
    'client/world.lua',   -- world control (peds / traffic / wanted / dispatch / events) via Config.World
}
