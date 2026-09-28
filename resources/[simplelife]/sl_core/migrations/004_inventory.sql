-- requires: characters
-- 004_inventory.sql — per-character item inventory.
-- Stored as a single JSON blob on the character (weight-based grid; ~50 visual slots).
-- sl_inventory owns the logic; sl_core owns the column + persistence plumbing.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS inventory JSON NULL;
