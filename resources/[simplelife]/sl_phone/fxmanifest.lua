--[[
    sl_phone — SimpleLife phone (device-centric, React/Vite NUI). Phase 0: foundations.

    The phone is an INVENTORY ITEM (`phone`). Each item carries a uuid in its metadata;
    ALL phone data (settings now; contacts/SMS/… later) keys on that uuid, never on the
    character — so stealing the item steals the data. The number is on the phones row for
    now (the SIM will own it in Phase 1). This resource owns its OWN NUI surface (web/ ->
    html/), separate from sl_ui, because the phone is large (its own React app + router).

    Build the UI: cd web && npm install && npm run build   (outputs to html/).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_phone'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife phone — device-centric, React NUI. Phase 0: foundations (home, dock, settings).'

dependencies {
    'sl_core',
    'sl_inventory',
    'ox_lib',
    'screenshot-basic',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

-- Built NUI assets (produced by `cd web && npm run build`, base './').
files {
    'html/index.html',
    'html/**/*',
}
