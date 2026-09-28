-- requires: characters
-- 003_appearance.sql — full character appearance (fivem-appearance data) as JSON.
-- Stored once at creation (and editable later); re-applied on every spawn so the look
-- persists across reconnects. NULL = never customized (legacy / pre-creator characters).

ALTER TABLE characters ADD COLUMN IF NOT EXISTS appearance JSON NULL;
