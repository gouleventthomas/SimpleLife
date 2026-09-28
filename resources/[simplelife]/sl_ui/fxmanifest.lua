--[[
    sl_ui — SimpleLife unified NUI (React + Vite + Tailwind + ShadCN).

    THE single NUI surface: HUD, screens (character select/create, later phone/
    inventory), notifications. Feature resources NEVER call SendNUIMessage directly
    — they go through the exports in client/bridge.lua:
        exports.sl_ui:open(screen, data)   -- interactive screen (grabs focus)
        exports.sl_ui:close()              -- release focus, hide screens
        exports.sl_ui:notify(kind, msg)    -- toast (no focus)
        exports.sl_ui:hud(data)            -- push HUD values

    The web/ folder is the React/Vite source; `npm run build` compiles it into
    html/ (this is what FiveM serves). Edit web/, never html/.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_ui'
author 'SimpleLife'
version '0.1.0'
description 'SimpleLife unified NUI: HUD, screens, notifications (React/Vite/Tailwind/ShadCN).'

dependencies {
    'sl_core',
}

ui_page 'html/index.html'

client_scripts {
    'client/bridge.lua',
}

-- Built NUI assets (produced by `cd web && npm run build`, base './').
files {
    'html/index.html',
    'html/**/*',
}
