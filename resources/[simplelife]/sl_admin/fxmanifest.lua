--[[
    sl_admin — SimpleLife staff menu (Liquid Glass) + dev/debug toolbox.

    F10 opens a nested admin menu (money, weapons, vehicles, players TP, self, noclip) and a
    debug submenu (coords, raycast entity inspector, vehicle info). The menu only opens for
    admins; the SERVER re-checks the `sl.admin` ace on EVERY action (server/main.lua), so the
    client gate is UX only and a crafted net event from a non-admin is rejected + logged.

    Grant access by mapping a principal to group.admin in server.cfg (already done for the
    owner) plus `add_ace group.admin sl.admin allow`.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_admin'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife admin + debug menu (Liquid Glass) — money/weapons/vehicles/players/noclip/debug.'

dependencies {
    'sl_core',
    'sl_ui',
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/noclip.lua',   -- Noclip table (loaded before main.lua uses it)
    'client/debug.lua',    -- Debug table  (loaded before main.lua uses it)
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
