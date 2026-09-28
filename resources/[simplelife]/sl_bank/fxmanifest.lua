--[[
    sl_bank — SimpleLife banking (Phase 2, first interaction feature).

    ATMs across the map become interactable (via sl_interact / ox_target): look at an ATM,
    press the target key -> a menu (balance / deposit / withdraw). All money math is SERVER-
    AUTHORITATIVE through sl_core's economy (atomic cash<->bank with rollback); the client
    only opens menus and sends amounts via ox_lib callbacks.

    This is the reference consumer of sl_interact: it never touches ox_target directly.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_bank'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife banking: ATM balance / deposit / withdraw on top of sl_core economy.'

dependencies {
    'sl_core',
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
