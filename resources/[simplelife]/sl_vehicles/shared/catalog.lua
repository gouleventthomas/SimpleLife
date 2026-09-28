--[[
    shared/catalog.lua — the curated vehicle catalog (the "sellable" models).

    Each entry:
      label    : display name
      brand    : marque (display only)
      category : 'car' | 'utility' | 'moto' | 'luxury'  (must exist in Config.Categories)
      price    : IMPORT cost (what the dealership pays to import a unit). The client retail price
                 is price + the owner's margin (within Config.Limits margin band), or a per-model
                 override the owner sets. Buy-back = price * Config.Limits.resalePct%.
      trunk    : trunk capacity in grams (drives the vehicle stash weight cap)
      seats    : occupant count (display)
      stats    : { speed, accel, braking, handling } each 0-100 (display in the catalogue)

    `model` is the GTA spawn name (the table key).
]]

Config.Catalog = {
    -- ── Voitures (car) ──────────────────────────────────────────────────────────
    blista    = { label = 'Blista',     brand = 'Dinka',     category = 'car', price = 9000,   trunk = 30000, seats = 4, stats = { speed=48, accel=55, braking=45, handling=60 } },
    issi3     = { label = 'Issi',       brand = 'Weeny',     category = 'car', price = 12000,  trunk = 25000, seats = 2, stats = { speed=46, accel=52, braking=44, handling=58 } },
    premier   = { label = 'Premier',    brand = 'Declasse',  category = 'car', price = 14000,  trunk = 45000, seats = 4, stats = { speed=50, accel=50, braking=48, handling=52 } },
    sultan    = { label = 'Sultan',     brand = 'Karin',     category = 'car', price = 22000,  trunk = 40000, seats = 4, stats = { speed=60, accel=62, braking=55, handling=68 } },
    fugitive  = { label = 'Fugitive',   brand = 'Cheval',    category = 'car', price = 24000,  trunk = 50000, seats = 4, stats = { speed=58, accel=56, braking=54, handling=56 } },
    schafter2 = { label = 'Schafter',   brand = 'Benefactor',category = 'car', price = 38000,  trunk = 55000, seats = 4, stats = { speed=64, accel=64, braking=60, handling=66 } },
    kuruma    = { label = 'Kuruma',     brand = 'Karin',     category = 'car', price = 42000,  trunk = 38000, seats = 4, stats = { speed=68, accel=70, braking=62, handling=72 } },
    sentinel  = { label = 'Sentinel',   brand = 'Übermacht', category = 'car', price = 30000,  trunk = 35000, seats = 2, stats = { speed=66, accel=66, braking=58, handling=64 } },
    buffalo   = { label = 'Buffalo',    brand = 'Bravado',   category = 'car', price = 28000,  trunk = 48000, seats = 4, stats = { speed=65, accel=63, braking=57, handling=62 } },

    -- ── Utilitaires (utility) ────────────────────────────────────────────────────
    rumpo     = { label = 'Rumpo',      brand = 'Bravado',   category = 'utility', price = 16000, trunk = 200000, seats = 4, stats = { speed=42, accel=40, braking=42, handling=44 } },
    bison     = { label = 'Bison',      brand = 'Bravado',   category = 'utility', price = 18000, trunk = 150000, seats = 4, stats = { speed=46, accel=44, braking=46, handling=46 } },
    bobcatxl  = { label = 'Bobcat XL',  brand = 'Declasse',  category = 'utility', price = 17000, trunk = 160000, seats = 4, stats = { speed=44, accel=42, braking=44, handling=45 } },
    mule      = { label = 'Mule',       brand = 'Maibatsu',  category = 'utility', price = 32000, trunk = 600000, seats = 2, stats = { speed=38, accel=34, braking=40, handling=38 } },
    speedo    = { label = 'Speedo',     brand = 'Vapid',     category = 'utility', price = 20000, trunk = 300000, seats = 2, stats = { speed=44, accel=42, braking=44, handling=46 } },

    -- ── Motos (moto) — for a future moto dealership ──────────────────────────────
    faggio2   = { label = 'Faggio',     brand = 'Pegassi',   category = 'moto', price = 6000,  trunk = 8000,  seats = 2, stats = { speed=40, accel=48, braking=40, handling=70 } },
    sanchez   = { label = 'Sanchez',    brand = 'Maibatsu',  category = 'moto', price = 9000,  trunk = 6000,  seats = 2, stats = { speed=52, accel=66, braking=48, handling=80 } },
    bati      = { label = 'Bati 801',   brand = 'Pegassi',   category = 'moto', price = 26000, trunk = 5000,  seats = 2, stats = { speed=78, accel=82, braking=64, handling=84 } },

    -- ── Luxe & Sport (luxury) — for a future luxury dealership ───────────────────
    comet2    = { label = 'Comet',      brand = 'Pfister',   category = 'luxury', price = 95000,  trunk = 30000, seats = 2, stats = { speed=82, accel=80, braking=76, handling=86 } },
    elegy2    = { label = 'Elegy RH8',  brand = 'Annis',     category = 'luxury', price = 90000,  trunk = 28000, seats = 2, stats = { speed=84, accel=84, braking=74, handling=84 } },
    t20       = { label = 'T20',        brand = 'Progen',    category = 'luxury', price = 220000, trunk = 22000, seats = 2, stats = { speed=96, accel=94, braking=88, handling=92 } },
    zentorno  = { label = 'Zentorno',   brand = 'Pegassi',   category = 'luxury', price = 240000, trunk = 20000, seats = 2, stats = { speed=97, accel=95, braking=88, handling=90 } },
}

-- Look up a model spec (nil if not in the catalog / not sellable).
function Config.CatalogModel(model)
    return model and Config.Catalog[string.lower(model)]
end

-- All catalog entries (as a sorted array) for the given category list.
function Config.CatalogFor(categories)
    local set = {}
    for _, c in ipairs(categories or {}) do set[c] = true end
    local out = {}
    for model, spec in pairs(Config.Catalog) do
        if not categories or set[spec.category] then
            out[#out + 1] = {
                model = model, label = spec.label, brand = spec.brand, category = spec.category,
                price = spec.price, trunk = spec.trunk, seats = spec.seats, stats = spec.stats,
            }
        end
    end
    table.sort(out, function(a, b) return a.price < b.price end)
    return out
end

-- Default retail price for a model given a dealership's margin band (clamped). Used when the
-- owner hasn't set an explicit price. min margin keeps the dealer profitable.
function Config.DefaultRetail(model)
    local spec = Config.CatalogModel(model)
    if not spec then return 0 end
    return math.floor(spec.price * (1 + (Config.Limits.marginMinPct / 100)))
end
