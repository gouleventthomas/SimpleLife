--[[
    sl_inventory — SimpleLife inventory (weight-based grid, drag&drop, ground bags).

    Server-authoritative items persisted to the character (sl_core `inventory` column). The
    Liquid Glass grid lives in sl_ui; ground drops are bags targetable via sl_interact. Other
    features (shops / jobs / crafting) move items through the exports: addItem / removeItem /
    hasItem / getItemCount / canCarry.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_inventory'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife inventory: weight grid, drag&drop, use/drop/give, ground bags.'

dependencies {
    'sl_core',
    'sl_ui',
    'sl_interact',
    'ox_lib',
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
