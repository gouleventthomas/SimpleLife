-- requires: accounts
-- 002_characters.sql — a character belongs to an account (license).
-- NOTE the semicolons inside THESE comments are deliberate; they prove the
-- comment/string-aware splitter (B5) does not split on a ';' inside a comment.
-- cash starts at 500; bank at 5000; position/metadata are JSON columns.

CREATE TABLE IF NOT EXISTS characters (
    id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    license    VARCHAR(64) NOT NULL,
    firstname  VARCHAR(48),
    lastname   VARCHAR(48),
    dob        DATE NULL,
    model      VARCHAR(64) NULL,
    cash       BIGINT NOT NULL DEFAULT 500,    -- pocket money; spendable anywhere
    bank       BIGINT NOT NULL DEFAULT 5000,   -- bank balance; ATM/transfer only
    position   JSON NULL,
    metadata   JSON NULL,
    deleted_at TIMESTAMP NULL,
    created    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_char_account FOREIGN KEY (license) REFERENCES accounts(license) ON DELETE CASCADE,
    INDEX idx_char_license (license)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
