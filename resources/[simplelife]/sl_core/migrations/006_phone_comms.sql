-- requires: phones
-- 006_phone_comms.sql — phone Phase 1 (Comms): contacts, SMS, call log, notes.
-- Contacts & notes are device-centric (keyed by the phone uuid → stolen with the device).
-- SMS & calls are addressed to the LINE (number), so they key on numbers. Created at boot.
CREATE TABLE IF NOT EXISTS phone_contacts (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    phone_uuid  VARCHAR(40)  NOT NULL,
    name        VARCHAR(64)  NOT NULL,
    number      VARCHAR(20)  NOT NULL,
    favorite    TINYINT(1)   NOT NULL DEFAULT 0,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_contacts_uuid (phone_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS phone_messages (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    sender      VARCHAR(20)  NOT NULL,
    receiver    VARCHAR(20)  NOT NULL,
    body        TEXT         NOT NULL,
    is_read     TINYINT(1)   NOT NULL DEFAULT 0,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_msg_pair (sender, receiver),
    INDEX idx_msg_receiver (receiver, is_read)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS phone_calls (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    caller      VARCHAR(20)  NOT NULL,
    callee      VARCHAR(20)  NOT NULL,
    accepted    TINYINT(1)   NOT NULL DEFAULT 0,
    duration    INT          NOT NULL DEFAULT 0,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_calls_caller (caller),
    INDEX idx_calls_callee (callee)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS phone_notes (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    phone_uuid  VARCHAR(40)  NOT NULL,
    title       VARCHAR(120) NOT NULL DEFAULT '',
    body        TEXT         NOT NULL,
    updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_notes_uuid (phone_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
