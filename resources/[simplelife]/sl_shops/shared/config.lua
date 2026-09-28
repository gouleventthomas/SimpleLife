--[[
    shared/config.lua — sl_shops settings: store locations, catalogues, wholesale prices.

    Item names MUST exist in sl_inventory (shared/config.lua Config.Items). Prices are in $.
    Coords are vec4(x, y, z, heading) at the clerk's standing spot (the ped is grounded by the
    client at z-1.0). Add/edit locations freely; the DB keys shops by the `id` here.
]]

Config = {}

Config.Accent = '#46d39a'      -- Liquid-Glass accent for the storefront (mint green)
Config.Debug  = false

Config.PedModel = 'mp_m_shopkeep_01'   -- default clerk model

Config.Limits = {
    maxQty        = 100,            -- max units of a single item per purchase
    maxTotal      = 100000000,      -- hard cap on any single transaction ($)
    rpcIntervalMs = 250,            -- min interval between money-producing RPCs per player
    billTtlMs     = 60000,          -- a POS bill expires if the customer doesn't pay in time
}

-- Permission keys an owner can grant to custom employee GRADES (player LTD businesses). The
-- owner always has all of them implicitly. Used by the grade editor (NUI) and enforced server-side.
Config.Permissions = {
    { key = 'pos',       label = 'Tenir la caisse (vendre)' },
    { key = 'restock',   label = 'Commander le stock (grossiste)' },
    { key = 'prices',    label = 'Modifier les prix de vente' },
    { key = 'withdraw',  label = 'Retirer de la caisse' },
    { key = 'employees', label = 'Gérer les employés' },
    { key = 'grades',    label = 'Gérer les grades & permissions' },
}

-- ── Retail catalogues (NPC stores + default for unowned LTDs) ───────────────────
Config.Catalogs = {
    general = {
        { item = 'water',     price = 8 },
        { item = 'cola',      price = 8 },
        { item = 'coffee',    price = 10 },
        { item = 'sandwich',  price = 12 },
        { item = 'burger',    price = 16 },
        { item = 'bandage',   price = 35 },
        { item = 'medkit',    price = 450 },
        { item = 'cigarette', price = 25 },
        { item = 'lockpick',  price = 150 },
        { item = 'phone',     price = 700 },
    },
}

-- ── Wholesale (grossiste) — what shop owners pay to stock their LTD ─────────────
-- `defaultPrice` seeds the owner's retail price when an item is first stocked.
Config.Wholesale = {
    { item = 'water',     price = 3,   defaultPrice = 8 },
    { item = 'cola',      price = 3,   defaultPrice = 8 },
    { item = 'coffee',    price = 4,   defaultPrice = 10 },
    { item = 'sandwich',  price = 5,   defaultPrice = 12 },
    { item = 'burger',    price = 7,   defaultPrice = 16 },
    { item = 'bandage',   price = 15,  defaultPrice = 35 },
    { item = 'medkit',    price = 200, defaultPrice = 450 },
    { item = 'cigarette', price = 10,  defaultPrice = 25 },
    { item = 'lockpick',  price = 65,  defaultPrice = 150 },
}

-- ── Store locations ─────────────────────────────────────────────────────────────
-- type '247' = always-NPC convenience store (one clerk ped).
-- type 'ltd' = player business: NO ped, and THREE separate staff interaction points, each with
--   its own coords (use F10 → Debug → coords to grab exact spots):
--     points.caisse  = vendre au client + caisse (solde / retrait)
--     points.stock   = entrer / sortir des items du stock
--     points.gestion = prix de vente + employés + grades & permissions
-- `blip.coords` places the map blip. vec4 = (x, y, z, heading).
Config.Shops = {
    { id = 's247_strawberry', label = '24/7 Strawberry', type = '247', catalog = 'general',
      ped = { coords = vec4(25.7, -1347.3, 29.49, 266.0) },
      blip = { sprite = 52, color = 2, scale = 0.7 } },
    { id = 's247_davis', label = '24/7 Davis', type = '247', catalog = 'general',
      ped = { coords = vec4(-47.0, -1757.6, 29.42, 50.0) },
      blip = { sprite = 52, color = 2, scale = 0.7 } },
    { id = 's247_sandy', label = '24/7 Sandy Shores', type = '247', catalog = 'general',
      ped = { coords = vec4(1961.46, 3740.0, 32.34, 300.0) },
      blip = { sprite = 52, color = 2, scale = 0.7 } },

    -- The single player-run LTD. Adjust the 3 point coords to your interior.
    { id = 'ltd_morningwood', label = 'LTD Morningwood', type = 'ltd', catalog = 'general',
      points = {
          caisse  = vec4(-1222.007, -908.415, 12.326, 29.74),  -- vendre + caisse
          stock   = vec4(-1219.424, -910.649, 12.326, 136.78),  -- items in/out
          gestion = vec4(-1219.918, -907.385, 12.326, 5.72),    -- prix/employés/grades
      },
      blip = { coords = vec3(-1221.0, -908.5, 12.3), sprite = 59, color = 5, scale = 0.8 } },
}

-- The wholesale supplier (one ped). Only shop owners can buy here (server-enforced).
Config.Wholesaler = {
    label = 'Grossiste',
    ped   = { model = 's_m_m_dockwork_01', coords = vec4(2747.55, 1503.6, 24.49, 188.0) },
    blip  = { sprite = 478, color = 47, scale = 0.7 },
}

---@param channel 'info'|'warn'|'error'|'debug'
function Config.Log(channel, msg)
    if channel == 'debug' and not Config.Debug then return end
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('^6[sl_shops]^7 %s%s^7'):format(colour, tostring(msg)))
end

function Config.Catalog(id) return Config.Catalogs[id] end
function Config.Shop(id)
    for _, s in ipairs(Config.Shops) do if s.id == id then return s end end
    return nil
end
