--[[
    shared/config.lua — sl_admin settings (client + server).

    The whole admin/debug surface is data-driven from here: keybind, theme accents, the
    money presets, and the weapon/vehicle catalogues (extend freely). SECURITY is NOT here —
    every action is re-checked server-side against the `sl.admin` ace (server/main.lua).
]]

Config = {}

-- Open key for the admin menu (RegisterKeyMapping default; rebindable in-game settings).
Config.OpenKey = 'F10'

-- Liquid Glass theme accents.
Config.Accent      = '#a86ff0'  -- admin -> purple
Config.DebugAccent = '#5ad1e0'  -- debug -> cyan

-- Cash/bank quick amounts (a "custom amount" prompt is always offered too).
Config.MoneyPresets = { 1000, 5000, 50000, 100000, 1000000 }

-- Noclip feel (txAdmin-style free flight). Units ~= metres/second.
Config.Noclip = {
    speed = 1.0,    -- base multiplier
    base  = 0.7,    -- metres per frame at 60fps before multipliers
    fast  = 4.0,    -- hold Shift
    slow  = 0.25,   -- hold Alt
}

-- ── Weapon catalogue (category -> weapons) ────────────────────────────────────
Config.Weapons = {
    { cat = 'Pistolets', icon = 'gun', list = {
        { label = 'Pistolet', weapon = 'WEAPON_PISTOL' },
        { label = 'Pistolet de combat', weapon = 'WEAPON_COMBATPISTOL' },
        { label = 'Pistolet .50', weapon = 'WEAPON_PISTOL50' },
        { label = 'Pistolet AP', weapon = 'WEAPON_APPISTOL' },
        { label = 'Pistolet lourd', weapon = 'WEAPON_HEAVYPISTOL' },
        { label = 'Revolver', weapon = 'WEAPON_REVOLVER' },
    }},
    { cat = 'Mitraillettes', icon = 'gun', list = {
        { label = 'Micro SMG', weapon = 'WEAPON_MICROSMG' },
        { label = 'SMG', weapon = 'WEAPON_SMG' },
        { label = 'SMG d\'assaut', weapon = 'WEAPON_ASSAULTSMG' },
        { label = 'Combat PDW', weapon = 'WEAPON_COMBATPDW' },
        { label = 'Mini SMG', weapon = 'WEAPON_MINISMG' },
    }},
    { cat = 'Fusils', icon = 'gun', list = {
        { label = 'Fusil d\'assaut', weapon = 'WEAPON_ASSAULTRIFLE' },
        { label = 'Carabine', weapon = 'WEAPON_CARBINERIFLE' },
        { label = 'Carabine spéciale', weapon = 'WEAPON_SPECIALCARBINE' },
        { label = 'Fusil avancé', weapon = 'WEAPON_ADVANCEDRIFLE' },
        { label = 'Bullpup', weapon = 'WEAPON_BULLPUPRIFLE' },
    }},
    { cat = 'Fusils à pompe', icon = 'gun', list = {
        { label = 'Pump Shotgun', weapon = 'WEAPON_PUMPSHOTGUN' },
        { label = 'Canon scié', weapon = 'WEAPON_SAWNOFFSHOTGUN' },
        { label = 'Pompe d\'assaut', weapon = 'WEAPON_ASSAULTSHOTGUN' },
        { label = 'Pompe lourd', weapon = 'WEAPON_HEAVYSHOTGUN' },
    }},
    { cat = 'Snipers', icon = 'gun', list = {
        { label = 'Sniper', weapon = 'WEAPON_SNIPERRIFLE' },
        { label = 'Sniper lourd', weapon = 'WEAPON_HEAVYSNIPER' },
        { label = 'Marksman', weapon = 'WEAPON_MARKSMANRIFLE' },
    }},
    { cat = 'Lourd', icon = 'gun', list = {
        { label = 'RPG', weapon = 'WEAPON_RPG' },
        { label = 'Lance-grenades', weapon = 'WEAPON_GRENADELAUNCHER' },
        { label = 'Minigun', weapon = 'WEAPON_MINIGUN' },
        { label = 'Railgun', weapon = 'WEAPON_RAILGUN' },
    }},
    { cat = 'Mêlée', icon = 'gun', list = {
        { label = 'Couteau', weapon = 'WEAPON_KNIFE' },
        { label = 'Batte', weapon = 'WEAPON_BAT' },
        { label = 'Machette', weapon = 'WEAPON_MACHETE' },
        { label = 'Poing américain', weapon = 'WEAPON_KNUCKLE' },
        { label = 'Matraque', weapon = 'WEAPON_NIGHTSTICK' },
    }},
    { cat = 'Jetables / divers', icon = 'gun', list = {
        { label = 'Grenade', weapon = 'WEAPON_GRENADE' },
        { label = 'Sticky bomb', weapon = 'WEAPON_STICKYBOMB' },
        { label = 'Molotov', weapon = 'WEAPON_MOLOTOV' },
        { label = 'Taser', weapon = 'WEAPON_STUNGUN' },
        { label = 'Lampe torche', weapon = 'WEAPON_FLASHLIGHT' },
        { label = 'Parachute', weapon = 'GADGET_PARACHUTE' },
    }},
}

-- ── Vehicle catalogue (category -> models) ────────────────────────────────────
Config.Vehicles = {
    { cat = 'Sportives', icon = 'car', list = {
        { label = 'Elegy RH8', model = 'elegy2' }, { label = 'Comet', model = 'comet2' },
        { label = 'Jester', model = 'jester' }, { label = 'Banshee', model = 'banshee' },
        { label = 'Sultan RS', model = 'sultanrs' }, { label = 'Kuruma', model = 'kuruma' },
        { label = 'Feltzer', model = 'feltzer2' },
    }},
    { cat = 'Super', icon = 'car', list = {
        { label = 'Adder', model = 'adder' }, { label = 'Zentorno', model = 'zentorno' },
        { label = 'T20', model = 't20' }, { label = 'Osiris', model = 'osiris' },
        { label = 'Nero', model = 'nero' }, { label = 'Vagner', model = 'vagner' },
        { label = 'Krieger', model = 'krieger' }, { label = 'Deveste', model = 'deveste' },
    }},
    { cat = 'Motos', icon = 'car', list = {
        { label = 'Akuma', model = 'akuma' }, { label = 'Bati 801', model = 'bati' },
        { label = 'Hakuchou', model = 'hakuchou' }, { label = 'Shotaro', model = 'shotaro' },
        { label = 'Defiler', model = 'defiler' }, { label = 'Sanchez', model = 'sanchez' },
    }},
    { cat = 'SUV / 4x4', icon = 'car', list = {
        { label = 'Baller', model = 'baller' }, { label = 'Cavalcade', model = 'cavalcade' },
        { label = 'Granger', model = 'granger' }, { label = 'Dubsta', model = 'dubsta' },
        { label = 'Sandking', model = 'sandking' }, { label = 'Kalahari', model = 'kalahari' },
    }},
    { cat = 'Berlines / compactes', icon = 'car', list = {
        { label = 'Sultan', model = 'sultan' }, { label = 'Asea', model = 'asea' },
        { label = 'Premier', model = 'premier' }, { label = 'Primo', model = 'primo' },
        { label = 'Washington', model = 'washington' }, { label = 'Stanier', model = 'stanier' },
    }},
    { cat = 'Utilitaires', icon = 'car', list = {
        { label = 'Rumpo', model = 'rumpo' }, { label = 'Boxville', model = 'boxville' },
        { label = 'Mule', model = 'mule' }, { label = 'Pounder', model = 'pounder' },
        { label = 'Bus', model = 'bus' }, { label = 'Dépanneuse', model = 'towtruck' },
    }},
    { cat = 'Air', icon = 'car', list = {
        { label = 'Buzzard', model = 'buzzard2' }, { label = 'Frogger', model = 'frogger' },
        { label = 'Maverick', model = 'maverick' }, { label = 'Lazer', model = 'lazer' },
        { label = 'Luxor', model = 'luxor' }, { label = 'Besra', model = 'besra' },
    }},
}

---@param channel 'info'|'warn'|'error'|'debug'
---@param msg string
function Config.Log(channel, msg)
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or channel == 'debug' and '^5' or '^7'
    print(('^5[sl_admin]^7 %s%s^7'):format(colour, tostring(msg)))
end
