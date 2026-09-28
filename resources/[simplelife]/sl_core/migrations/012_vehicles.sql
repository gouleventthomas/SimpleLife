-- requires: characters
-- 012_vehicles.sql — owned vehicles for sl_vehicles. One row per owned vehicle, tied to a
-- character (charid). `props` is the full lib.getVehicleProperties() blob (mods/colours/plate/
-- damage), persisted so a vehicle reappears EXACTLY as it was. `fuel`/`body_health`/`engine_health`
-- are also mirrored as columns for cheap queries. `status`: parked|out|impound. When parked,
-- `garage` + park_* hold where the physical car sits so it respawns on its spot at reboot.
CREATE TABLE IF NOT EXISTS vehicles (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    charid        BIGINT UNSIGNED NOT NULL,                 -- owner = characters.id
    plate         VARCHAR(12) NOT NULL UNIQUE,              -- world-unique licence plate
    model         VARCHAR(64) NOT NULL,                     -- spawn name (e.g. 'sultan')
    category      VARCHAR(24) NOT NULL DEFAULT 'car',       -- Config.Catalog category
    props         JSON NULL,                                -- lib.getVehicleProperties() snapshot
    fuel          INT NOT NULL DEFAULT 100,                 -- 0-100
    body_health   INT NOT NULL DEFAULT 1000,                -- 0-1000
    engine_health INT NOT NULL DEFAULT 1000,                -- 0-1000
    status        VARCHAR(16) NOT NULL DEFAULT 'parked',    -- parked | out | impound
    garage        VARCHAR(48) NULL,                         -- garage id when parked/impound origin
    park_x        DOUBLE NULL,
    park_y        DOUBLE NULL,
    park_z        DOUBLE NULL,
    park_h        DOUBLE NULL,
    created       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_veh_owner (charid),
    INDEX idx_veh_status (status),
    INDEX idx_veh_garage (garage)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Shared virtual keys. The OWNER (vehicles.charid) is implicit and not stored here; rows are
-- the EXTRA characters the owner granted a key to (permanent until revoked).
CREATE TABLE IF NOT EXISTS vehicle_keys (
    vehicle_id BIGINT UNSIGNED NOT NULL,
    charid     BIGINT UNSIGNED NOT NULL,
    granted    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (vehicle_id, charid),
    INDEX idx_vk_char (charid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
