--[[
    shared/config.lua — sl_inventory settings + the item catalogue.

    Capacity is WEIGHT-BASED (the only hard limit). The grid is a generous fixed visual size
    so slots are never the constraint. Items stack up to `stack` per slot. Any feature
    (shops, jobs, crafting) can reference these item names via the sl_inventory exports.

    Item spec: { label, weight (grams), stack (max per slot), category, usable, removeOnUse, desc }
      category drives the slot ICON (mapped to a lucide icon in the React grid).
]]

Config = {}

Config.MaxWeight = 40000   -- grams (40 kg) — the binding capacity limit
Config.GridSize  = 50      -- visual slots (kept high so WEIGHT is what limits you)
Config.OpenKey   = 'TAB'   -- open the inventory (rebindable in-game)
Config.Accent    = '#d9a441'  -- Liquid Glass theme accent (warm amber)
Config.DropModel = 'prop_cs_heist_bag_02'  -- ground-bag prop for drops
Config.DropMaxWeight = 100000              -- a ground bag can hold a lot
Config.DropReach = 3.0                     -- metres: SERVER-side gate to open/transfer with a bag / ground

-- Equipment slots shown around the character (functional storage; one item each). `accept` is an
-- optional list of allowed item categories (nil = any). Effects (weapon draw, bag weight bonus)
-- come later — for now they are persistent single-item slots that count toward your weight.
Config.EquipSlots = {
    { id = 'hand',     label = 'Main',     icon = 'hand',     accept = nil },
    { id = 'holster',  label = 'Holster',  icon = 'holster',  accept = nil },
    { id = 'bag',      label = 'Sac',      icon = 'bag',      accept = nil },
    { id = 'clothing', label = 'Vêtement', icon = 'clothing', accept = nil },
}

---@param channel 'info'|'warn'|'error'|'debug'
function Config.Log(channel, msg)
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('^6[sl_inventory]^7 %s%s^7'):format(colour, tostring(msg)))
end

-- ── Item catalogue ────────────────────────────────────────────────────────────
Config.Items = {
    -- drinks / food
    water         = { label = "Bouteille d'eau",  weight = 500,  stack = 12, category = 'drink',    usable = true,  removeOnUse = true, desc = 'Étanche la soif.' },
    cola          = { label = 'Cola',              weight = 350,  stack = 12, category = 'drink',    usable = true,  removeOnUse = true },
    coffee        = { label = 'Café',              weight = 300,  stack = 8,  category = 'drink',    usable = true,  removeOnUse = true },
    beer          = { label = 'Bière',             weight = 500,  stack = 12, category = 'drink',    usable = true,  removeOnUse = true },
    sandwich      = { label = 'Sandwich',          weight = 250,  stack = 8,  category = 'food',     usable = true,  removeOnUse = true, desc = 'Calme la faim.' },
    burger        = { label = 'Burger',            weight = 300,  stack = 6,  category = 'food',     usable = true,  removeOnUse = true },
    -- medical
    bandage       = { label = 'Bandage',           weight = 100,  stack = 10, category = 'medical',  usable = true,  removeOnUse = true, desc = 'Soigne une partie de la vie.' },
    medkit        = { label = 'Medkit',            weight = 1000, stack = 3,  category = 'medical',  usable = true,  removeOnUse = true, desc = 'Soigne complètement.' },
    painkillers   = { label = 'Antidouleurs',      weight = 100,  stack = 10, category = 'medical',  usable = true,  removeOnUse = true },
    -- tools
    phone         = { label = 'Téléphone',         weight = 200,  stack = 1,  category = 'tool',     usable = true,  desc = 'Smartphone personnel. Toutes ses données vivent dans l\'appareil.' },
    sim           = { label = 'Carte SIM',         weight = 5,    stack = 1,  category = 'tool',     usable = false, desc = 'Porte un numéro de téléphone (à insérer dans un téléphone).' },
    broken_phone  = { label = 'Téléphone cassé',   weight = 200,  stack = 1,  category = 'tool',     usable = false, desc = 'Écran brisé — bon pour pièces / réparation.' },
    radio         = { label = 'Radio',             weight = 500,  stack = 1,  category = 'tool',     usable = true },
    lockpick      = { label = 'Crochet',           weight = 150,  stack = 5,  category = 'tool',     usable = true },
    startkit      = { label = 'Kit de démarrage',  weight = 800,  stack = 3,  category = 'tool',     usable = false, desc = 'Permet de forcer le démarrage d\'un véhicule (avec un crochet).' },
    jerrycan      = { label = 'Jerrican',          weight = 8000, stack = 1,  category = 'tool',     usable = true,  desc = 'Carburant d\'appoint pour un véhicule à proximité.' },
    repair_kit    = { label = 'Kit de réparation', weight = 2000, stack = 3,  category = 'tool',     usable = true,  removeOnUse = true },
    flashlight    = { label = 'Lampe torche',      weight = 300,  stack = 1,  category = 'tool',     usable = true },
    rope          = { label = 'Corde',             weight = 800,  stack = 5,  category = 'tool' },
    -- documents / keys
    id_card       = { label = "Carte d'identité",  weight = 10,   stack = 1,  category = 'document', usable = true },
    driver_license= { label = 'Permis de conduire',weight = 10,   stack = 1,  category = 'document', usable = true },
    car_key       = { label = 'Clé de véhicule',   weight = 50,   stack = 50, category = 'key',      usable = true },
    house_key     = { label = 'Clé de maison',     weight = 50,   stack = 50, category = 'key',      usable = true },
    -- materials
    scrap         = { label = 'Ferraille',         weight = 1000, stack = 50, category = 'material' },
    plastic       = { label = 'Plastique',         weight = 500,  stack = 50, category = 'material' },
    electronics   = { label = 'Composants',        weight = 300,  stack = 50, category = 'material' },
    cloth         = { label = 'Tissu',             weight = 200,  stack = 50, category = 'material' },
    -- misc
    cigarette     = { label = 'Cigarette',         weight = 20,   stack = 20, category = 'misc',     usable = true,  removeOnUse = true },
    dice          = { label = 'Dés',               weight = 50,   stack = 5,  category = 'misc',     usable = true },
}

-- Look up an item spec by name (nil if unknown).
function Config.Item(name)
    return Config.Items[name]
end
