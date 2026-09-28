-- requires:
-- 001_accounts.sql — root migration (no dependencies).
-- An account is one player identity (license). Characters FK to this.

CREATE TABLE IF NOT EXISTS accounts (
    license   VARCHAR(64) PRIMARY KEY,
    created   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
