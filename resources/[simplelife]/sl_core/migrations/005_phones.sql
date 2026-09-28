-- 005_phones.sql — device-centric phone registry (sl_phone, Phase 0).
-- The phone is an INVENTORY ITEM: each `phone` item carries a uuid in its metadata
-- (see sl_inventory getItemMeta/setItemMeta). ALL phone data keys on that uuid, never
-- on the character — stealing the item steals the data. `number` is the line (the SIM
-- will own it in Phase 1; for now it lives here so it's ready). `settings` is the JSON
-- blob the home screen reads (wallpaper, brightness…). No FK to characters on purpose:
-- the device outlives any single owner. `owner_char` is informational (who first booted it).
CREATE TABLE IF NOT EXISTS phones (
    uuid        VARCHAR(40)  NOT NULL PRIMARY KEY,
    number      VARCHAR(20)  NULL,
    owner_char  INT          NULL,
    settings    JSON         NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_phone_number (number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
