--[[
    shared/config.lua — sl_vehicles settings (loaded server + client).

    Coordinates here are CREDIBLE PLACEHOLDERS — adjust the vec3/vec4 values in-game.
    The vehicle CATALOG (sellable models + import cost + trunk + stats) lives in shared/catalog.lua.
]]

Config = {}

Config.Accent = '#3ba9e0'     -- Liquid Glass accent for the NUI (vehicle blue)
Config.Debug  = false

---@param channel 'info'|'warn'|'error'|'debug'
function Config.Log(channel, msg)
    if channel == 'debug' and not Config.Debug then return end
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('^6[sl_vehicles]^7 %s%s^7'):format(colour, tostring(msg)))
end

-- ── Categories (drive showroom filters & garage acceptance) ─────────────────────
Config.Categories = {
    car     = 'Voiture',
    utility = 'Utilitaire',
    moto    = 'Moto',
    luxury  = 'Luxe & Sport',
}

-- ── Permissions (dealership grades; owner implicitly has all) ────────────────────
-- Same model as sl_shops: a grade is a name + a set of these permission keys.
Config.Permissions = {
    'vente',     -- hold the counter / sell to clients (earns commission)
    'import',    -- order imports + do the convoy restock
    'prix',      -- set retail prices (within the margin band)
    'caisse',    -- withdraw the till + pay salaries
    'employes',  -- recruit / fire / set grade
    'grades',    -- create / edit grades & permissions
    'expo',      -- choose which models are displayed in the showroom
    'leads',     -- view contact-form leads + call clients
}

-- ── Global tuning (all adjustable) ──────────────────────────────────────────────
Config.Limits = {
    maxOwned          = 5,      -- vehicles a character may own
    marginMinPct      = 10,     -- min retail markup over import cost
    marginMaxPct      = 40,     -- max retail markup over import cost
    resalePct         = 50,     -- % of import cost the dealership pays on buy-back
    commissionDefault = 5,      -- default grade commission %
    salaryIntervalMin = 60,     -- minutes of presence between salary ticks
    lockKeyReach      = 12.0,   -- metres: U shortcut targets the nearest keyed vehicle
    plateUnique       = true,
}

Config.Keys = {
    lockToggle = 'U',           -- (un)lock nearest owned vehicle (rebindable in-game)
}

-- ── Import / convoy ─────────────────────────────────────────────────────────────
Config.Import = {
    normalDelay   = 15 * 60,    -- seconds until an order is ready at the port
    priorityDelay = 5 * 60,     -- seconds with priority delivery
    priorityFee   = 1500,       -- flat fee (from till) for priority
    -- The port pickup zone: ordered cars spawn locked on these marked spots.
    portBlip   = vec3(853.0, -3105.0, 5.9),
    portSpots  = {
        vec4(845.0, -3105.0, 5.0, 270.0),
        vec4(845.0, -3110.0, 5.0, 270.0),
        vec4(845.0, -3115.0, 5.0, 270.0),
        vec4(845.0, -3120.0, 5.0, 270.0),
        vec4(845.0, -3125.0, 5.0, 270.0),
        vec4(845.0, -3130.0, 5.0, 270.0),
    },
    -- Transport given to the employee at the port. flatbed for a single car, carrier for many.
    transport = {
        single = { model = 'flatbed',  slots = 1 },
        multi  = { model = 'tr2',      slots = 3 },   -- car-carrier trailer (towed by a hauler)
        hauler = 'hauler',                              -- truck that tows the tr2 trailer
        spawn  = vec4(860.0, -3140.0, 5.0, 90.0),
    },
    loadReach   = 4.0,          -- metres to load a car onto the trailer / unload at the bay
    -- Trailer slot offsets (relative to the trailer) for attached cars.
    carrierOffsets = {
        vec3(0.0, 3.6, 1.0),
        vec3(0.0, 0.2, 1.0),
        vec3(0.0, -3.2, 1.4),
    },
    flatbedOffset = vec3(0.0, -1.2, 1.0),
}

-- ── Public garages (physical persistent parking) ────────────────────────────────
-- `spots` = marked parking places (vec4 x,y,z,heading). `classes` = accepted categories.
Config.Garages = {
    {
        id      = 'central',
        label   = 'Parking Public — Centre-ville',
        classes = { 'car', 'utility', 'moto', 'luxury' },
        blip    = { coords = vec3(215.0, -810.0, 30.7), sprite = 357, color = 3, scale = 0.8 },
        spawnReach = 80.0,      -- parked cars materialise when a player is this close
        spots = {
            vec4(228.0, -801.0, 30.5, 250.0),
            vec4(231.0, -804.0, 30.5, 250.0),
            vec4(234.0, -807.0, 30.5, 250.0),
            vec4(237.0, -810.0, 30.5, 250.0),
            vec4(240.0, -813.0, 30.5, 250.0),
            vec4(243.0, -816.0, 30.5, 250.0),
            vec4(246.0, -819.0, 30.5, 250.0),
            vec4(249.0, -822.0, 30.5, 250.0),
            vec4(252.0, -825.0, 30.5, 250.0),
            vec4(255.0, -828.0, 30.5, 250.0),
            vec4(258.0, -831.0, 30.5, 250.0),
            vec4(261.0, -834.0, 30.5, 250.0),
        },
    },
}

-- ── Impound lots (fourrières) ───────────────────────────────────────────────────
Config.Impound = {
    fee = 750,                  -- flat recovery fee
    lots = {
        { id = 'depot', label = 'Fourrière Municipale',
          ped = vec4(409.0, -1622.0, 29.3, 230.0),
          retrieve = vec4(415.0, -1638.0, 29.3, 320.0),   -- where the recovered car spawns
          blip = { coords = vec3(409.0, -1622.0, 29.3), sprite = 68, color = 5, scale = 0.7 } },
        { id = 'airport', label = 'Fourrière Aéroport',
          ped = vec4(-1043.0, -2742.0, 21.4, 240.0),
          retrieve = vec4(-1050.0, -2730.0, 21.3, 150.0),
          blip = { coords = vec3(-1043.0, -2742.0, 21.4), sprite = 68, color = 5, scale = 0.7 } },
    },
}

-- ── Fuel (essence simple, persisted via statebag) ───────────────────────────────
Config.Fuel = {
    enabled        = true,
    idleDrainPerMin = 0.6,      -- % per minute idling (engine on, stationary)
    drivePerKm      = 4.0,      -- % per km driven
    pricePerUnit    = 3,        -- $ per % refuelled at a station
    jerrycanRefill  = 30,       -- % restored by using a jerrycan (uses the item)
    jerrycanPrice   = 0,        -- (bought elsewhere; here for reference)
    refuelReach     = 4.0,
    -- Station pumps targeted with ox_target (GTA gas pump props).
    pumpModels = {
        'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d',
        'prop_vintage_pump', 'prop_gas_pump_old2', 'prop_gas_pump_old3',
    },
}

-- ── Hotwire (criminal theft) ────────────────────────────────────────────────────
Config.Hotwire = {
    enabled        = true,
    needLockpick   = true,      -- item 'lockpick' to open the door
    needStartkit   = true,      -- item 'startkit' to bypass ignition
    pickDuration   = 6000,      -- ms progress to pick the lock
    skillDifficulty = 'medium', -- lib.skillCheck difficulty to bypass ignition
    engineDamage   = 250.0,     -- engine health removed by a successful hotwire
    alarm          = true,      -- trigger the vehicle alarm on a pick attempt
    cooldownMs     = 20000,     -- per-player cooldown after a failed attempt
}

-- ── Dealerships (player-run; assigned in F10) ───────────────────────────────────
-- MVP: ONE dealership selling car + utility. Add moto / luxury entries later.
Config.Dealerships = {
    {
        id         = 'auto_centre',
        label      = 'Concession Auto — Centre',
        categories = { 'car', 'utility' },
        blip       = { coords = vec3(-41.186, -1099.691, 26.422), sprite = 523, color = 3, scale = 0.9 },
        points = {
            vente   = vec4(-30.646, -1106.633, 26.422, 317.15), -- employee counter (POS + catalogue)
            gestion = vec4(-32.14, -1114.397, 26.422, 78.22),   -- management terminal (stock/import/prices/HR/till/leads)
        },
        delivery     = vec4(-19.797, -1113.238, 26.672, 160.39),  -- convoy UNLOAD bay (= même point que la sortie camion)
        deliveryReach = 8.0,
        saleSpawn    = vec4(-49.198, -1080.123, 26.800, 55.31),   -- sold car appears here for the client
        transportSpawn = vec4(-19.797, -1113.238, 26.672, 160.39), -- where the flatbed / hauler+tr2 appears (drive it to the port)
        -- Showroom display spots; the owner picks which models sit here.
        expo = {
            vec4(-47.417, -1093.338, 25.815, 189.40),
            vec4(-41.743, -1096.173, 25.815, 181.92),
            vec4(-47.336, -1101.194, 25.815, 293.67),
        },
    },
}

-- ── Convenience lookups ─────────────────────────────────────────────────────────
function Config.Garage(id)
    for _, g in ipairs(Config.Garages) do if g.id == id then return g end end
end

function Config.Dealership(id)
    for _, d in ipairs(Config.Dealerships) do if d.id == id then return d end end
end

function Config.ImpoundLot(id)
    for _, l in ipairs(Config.Impound.lots) do if l.id == id then return l end end
end
