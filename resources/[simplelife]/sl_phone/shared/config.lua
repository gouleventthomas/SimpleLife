--[[
    sl_phone/shared/config.lua — phone settings + the home-screen app catalogue.

    The app list is sent to the NUI on open, so the home screen is config-driven (matches
    the blueprint's "installed apps"). `phase` marks which roadmap phase an app belongs to:
    phase 0 apps are functional now; higher-phase apps render a "Bientôt" placeholder until
    their phase ships. `icon` is a lucide-react icon name (mapped in web/src/lib/icons.ts).
]]

Config = {}

Config.OpenKey = 'F1'          -- open the phone (rebindable in FiveM keybinds). Requires the phone ITEM.
Config.Item    = 'phone'       -- the inventory item that IS the device
Config.Accent  = '#0a84ff'     -- iOS blue — primary UI accent

-- Written when a phone first boots; the server merges saved settings over these.
Config.DefaultSettings = {
    wallpaper  = 'aurora',
    brightness = 1.0,
    frame      = 'coral', -- iPhone case/bezel colour
}

-- Phone number format (Phase 0: number lives on the phones row; the SIM owns it in Phase 1).
Config.NumberFormat = '06%07d' -- "06" + 7 digits

-- Phone-in-hand: prop + animation played while the phone is open (you can still walk/drive).
-- Offsets/rotation are tweakable if the prop sits oddly in the hand.
Config.Hand = {
    prop  = 'prop_amb_phone',
    bone  = 28422,                  -- right-hand bone
    pos   = { x = 0.0, y = 0.0, z = 0.0 },
    rot   = { x = 0.0, y = 0.0, z = 0.0 },
    dict  = 'cellphone@',
    inAnim   = 'cellphone_text_in',         -- raise the phone
    holdAnim = 'cellphone_text_read_base',  -- looped "looking at phone" (lets you move)
    outAnim  = 'cellphone_text_out',        -- put the phone away
}

-- Crypto coins (Phase 3, "simple wallet": hold + transfer, no market/buy-sell). Display only.
Config.Coins = {
    { id = 'slc', label = 'SimpleCoin', symbol = '§', color = '#0a84ff' },
    { id = 'btc', label = 'Bitcoin',    symbol = '₿', color = '#f7931a' },
    { id = 'eth', label = 'Ethereum',   symbol = 'Ξ', color = '#627eea' },
}

-- Anti-abuse limits (per device / per source).
Config.Limits = {
    contacts     = 250,  -- max contacts per device
    notes        = 200,  -- max notes per device
    media        = 100,  -- max photos per device (stored base64 in DB)
    rpcIntervalMs = 350, -- min interval between two INSERT-producing RPCs from one player
}

-- Home-screen apps. Functional now: settings. The rest are placeholders for later phases.
-- Home grid order (uniform iOS icons, 4 columns). Functional apps keep their ids; the rest
-- are placeholders (render "arrive bientôt"). 'calendrier' renders a live date face.
-- `mandatory = true` → app can never be uninstalled from the iFruit Store (system / core apps).
-- The others are installable / removable. Default (new device) = everything installed.
Config.Apps = {
    { id = 'calendrier',  label = 'Calendrier',   icon = 'Calendar',      color = '#ffffff', phase = 6, mandatory = true },
    { id = 'store',       label = 'iFruit Store',  icon = 'Store',         color = '#0a84ff', phase = 0, mandatory = true },
    { id = 'gallery',     label = 'Galerie',      icon = 'Image',         color = '#ff375f', phase = 2, mandatory = true },
    { id = 'horloge',     label = 'Horloge',      icon = 'Clock',         color = '#1c1c1e', phase = 6, mandatory = true },
    { id = 'calculatrice',label = 'Calculatrice', icon = 'Calculator',    color = '#ff9500', phase = 6 },
    { id = 'wallet',      label = 'Banque',       icon = 'Landmark',      color = '#30d158', phase = 3, mandatory = true },
    { id = 'crypto',      label = 'Crypto',       icon = 'Bitcoin',       color = '#ff9f0a', phase = 3 },
    { id = 'mail',        label = 'Mail',         icon = 'Mail',          color = '#0a84ff', phase = 5 },
    { id = 'notes',       label = 'Notes',        icon = 'StickyNote',    color = '#ffd60a', phase = 1 },
    { id = 'camera',      label = 'Caméra',       icon = 'Camera',        color = '#8e8e93', phase = 2, mandatory = true },
    { id = 'news',        label = 'Actus',        icon = 'Newspaper',     color = '#ff3b30', phase = 6 },
    { id = 'darkchat',    label = 'Dark Chat',    icon = 'Lock',          color = '#7c3aed', phase = 5 },
    { id = 'sante',       label = 'Santé',        icon = 'Heart',         color = '#ff2d55', phase = 6 },
    { id = 'contacts',    label = 'Contacts',     icon = 'Users',         color = '#5e9bff', phase = 1, mandatory = true },
    { id = 'evenements',  label = 'Événements',   icon = 'CalendarDays',  color = '#ff453a', phase = 6 },
    { id = 'vehicules',   label = 'Véhicules',    icon = 'Car',           color = '#34c759', phase = 0 },
    { id = 'annuaire',    label = 'Annuaire',     icon = 'Building2',      color = '#5e9bff', phase = 0 },
    { id = 'proprietes',  label = 'Propriétés',   icon = 'Home',          color = '#0a84ff', phase = 6 },
    { id = 'marketplace', label = 'Marketplace',  icon = 'ShoppingBag',   color = '#ff9500', phase = 6 },
    { id = 'business',    label = 'Société',      icon = 'Briefcase',     color = '#5e5ce6', phase = 0 },
    -- dock apps (excluded from the grid) — all mandatory
    { id = 'phone',       label = 'Téléphone',    icon = 'Phone',         color = '#34c759', phase = 1, mandatory = true },
    { id = 'messages',    label = 'Messages',     icon = 'MessageSquare', color = '#34c759', phase = 1, mandatory = true },
    { id = 'navigateur',  label = 'Internet',     icon = 'Compass',       color = '#0a84ff', phase = 6, mandatory = true },
    { id = 'settings',    label = 'Réglages',     icon = 'Settings',      color = '#8e8e93', phase = 0, mandatory = true },
}

-- Bottom dock (favourites). ids referencing Config.Apps; excluded from the page grid.
Config.Dock = { 'phone', 'messages', 'navigateur', 'settings' }

---@param channel 'info'|'warn'|'error'|'debug'
function Config.Log(channel, msg)
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('^6[sl_phone]^7 %s%s^7'):format(colour, tostring(msg)))
end
