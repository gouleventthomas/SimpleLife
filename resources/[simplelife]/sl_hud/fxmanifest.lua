--[[
    sl_hud — SimpleLife HUD. Four circular gauges (vie / armure / faim / soif) to the RIGHT of the
    minimap, and hides the native GTA health + armour bars. Health/armour are read natively;
    hunger/thirst come from sl_core's player state bag (Player.state['sl:needs']).
    Lightweight no-build NUI (single html/index.html).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_hud'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife HUD: circular health/armor/hunger/thirst gauges; hides native bars.'

dependencies { 'sl_core' }

client_scripts { 'client/main.lua' }

ui_page 'html/index.html'
files { 'html/index.html' }
