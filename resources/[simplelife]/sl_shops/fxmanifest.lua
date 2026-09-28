--[[
    sl_shops — SimpleLife shops. PED merchants + map blips + ox_target interactions + a
    Liquid-Glass NUI storefront (own React/Vite surface, like sl_phone).

    Two kinds of store:
      • type '247'  → NPC convenience store, server catalogue, infinite stock, money is a sink.
      • type 'ltd'  → ownable: an admin assigns an owner; the owner stocks it at the wholesale
                      NPC, sets retail prices, and the till buffers sales for withdrawal.
                      Unowned LTDs run as NPC stores so the world is never "dead".

    All transactions are SERVER-authoritative (price/stock resolved server-side, proximity
    checked, stock decremented race-safely, money via sl_core economy).

    Build the UI:  cd web && npm install && npm run build   (outputs to html/).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_shops'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife shops: 24/7 NPC stores + player-managed LTDs, wholesale supplier, NUI storefront.'

dependencies {
    'sl_core',
    'sl_inventory',
    'sl_interact',
    'sl_ui',
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/world.lua',
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
