-- requires: phone_comms
-- 008_phone_economy.sql — phone economy (Phase 3): bank transaction log, payment requests,
-- and crypto holdings. Bank money itself stays in sl_core (characters.bank) — these tables
-- only LOG/route it. Crypto is device-centric (keyed by phone uuid). Money sent inside a SMS
-- conversation adds kind/amount columns to phone_messages.
ALTER TABLE phone_messages ADD COLUMN IF NOT EXISTS kind VARCHAR(16) NOT NULL DEFAULT 'text';
ALTER TABLE phone_messages ADD COLUMN IF NOT EXISTS amount BIGINT NULL;

CREATE TABLE IF NOT EXISTS phone_bank_tx (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    from_number VARCHAR(20)  NOT NULL,
    to_number   VARCHAR(20)  NOT NULL,
    amount      BIGINT       NOT NULL,
    reason      VARCHAR(100) NULL,
    kind        VARCHAR(16)  NOT NULL DEFAULT 'transfer',
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_tx_from (from_number),
    INDEX idx_tx_to (to_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS phone_pay_requests (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    from_number VARCHAR(20)  NOT NULL,  -- requester (wants to be paid)
    to_number   VARCHAR(20)  NOT NULL,  -- payer (asked to pay)
    amount      BIGINT       NOT NULL,
    reason      VARCHAR(100) NULL,
    status      VARCHAR(16)  NOT NULL DEFAULT 'pending',
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_req_to (to_number, status),
    INDEX idx_req_from (from_number, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS phone_crypto (
    phone_uuid  VARCHAR(40)   NOT NULL,
    coin        VARCHAR(16)   NOT NULL,
    amount      DECIMAL(24,8) NOT NULL DEFAULT 0,
    PRIMARY KEY (phone_uuid, coin)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
