--[[
    migrations/manifest.lua — the ordered list of migration files.

    Returned as a plain Lua table and read by server/migrate.lua via
    LoadResourceFile. The NUMERIC PREFIX order here is a human cross-check; actual
    execution order is decided by the topological sort over each file's first-line
    "-- requires:" declaration (bug class B2). To add a migration, append it here
    and declare its deps in the file header.
]]

return {
    '001_accounts.sql',
    '002_characters.sql',
    '003_appearance.sql',
    '004_inventory.sql',
    '005_phones.sql',
    '006_phone_comms.sql',
    '007_phone_media.sql',
    '008_phone_economy.sql',
    '009_phone_apps.sql',
    '010_shops.sql',
    '011_shop_business.sql',
    '012_vehicles.sql',
    '013_dealerships.sql',
    '014_stashes.sql',
}
