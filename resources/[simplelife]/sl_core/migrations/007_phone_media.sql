-- requires: phones
-- 007_phone_media.sql — phone gallery (Phase 2). Device-centric: photos travel with the
-- device (keyed by phone uuid → stolen with it). Stored LOCALLY as base64 data URIs
-- (downscaled client-side): `thumb` for the grid, `data` for the full view. No external CDN.
CREATE TABLE IF NOT EXISTS phone_media (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    phone_uuid  VARCHAR(40)  NOT NULL,
    kind        VARCHAR(16)  NOT NULL DEFAULT 'photo',
    thumb       MEDIUMTEXT   NULL,
    data        MEDIUMTEXT   NOT NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_media_uuid (phone_uuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
