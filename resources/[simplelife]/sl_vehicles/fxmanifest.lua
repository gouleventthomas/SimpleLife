--[[
    sl_vehicles — SimpleLife vehicle system.

    Pillars (all SERVER-authoritative):
      • Player-run dealerships (assigned in F10): showroom expo, employee-operated sale (POS),
        custom grades/permissions/commission, company till, salaries.
      • Import / convoy restock: order at the gestion terminal -> cars spawn at the PORT after a
        delay -> an employee drives a flatbed (1) or car-carrier (n), loads each car by interaction,
        unloads at the dealership delivery bay -> stock.
      • Phone virtual keys: engine cannot start without the key (owner or shared); lock/unlock/locate/
        remote-start/trunk via the phone app + a configurable U shortcut. Hotwire (lockpick + startkit).
      • Physical persistent parking: public garages are real marked spots; parked cars stay on the lot
        and respawn on a free spot at reboot. Retrieve by walking to the car and unlocking it.
      • Impound (multiple, fixed fee; left-out-on-disconnect / destroyed), fuel (stations + jerrycan),
        100% saved state, concession resale, player-to-player transfer.

    Build the UI:  cd web && npm install && npm run build   (outputs to html/, base './').
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_vehicles'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife vehicles: player dealerships, import convoy, phone keys, physical garages, impound, fuel.'

dependencies {
    'sl_core',
    'sl_inventory',
    'sl_interact',
    'sl_ui',
    'ox_lib',
    'ox_target',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/catalog.lua',
}

client_scripts {
    'client/main.lua',
    'client/keys.lua',
    'client/garage.lua',
    'client/dealership.lua',
    'client/convoy.lua',
    'client/fuel.lua',
    'client/impound.lua',
}

server_scripts {
    'server/util.lua',
    'server/vehicles.lua',
    'server/keys.lua',
    'server/garage.lua',
    'server/dealership.lua',
    'server/convoy.lua',
    'server/impound.lua',
    'server/leads.lua',
    'server/rpc.lua',
    'server/admin.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/**/*',
}
