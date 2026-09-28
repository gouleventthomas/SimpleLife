-- requires: characters
-- 013_dealerships.sql — player-run car dealerships for sl_vehicles. Mirrors the sl_shops LTD
-- model (owner + till + custom grades/permissions + employees) but for VEHICLES. Stock is per
-- (dealer, model) with the owner's retail price; restocked via the import/convoy loop. Orders
-- track the import job (ready_at = when the cars appear at the port). company_leads is the
-- generic "contact form" inbox shared by the phone "Annuaire des sociétés" app.
CREATE TABLE IF NOT EXISTS dealerships (
    id           VARCHAR(48) NOT NULL PRIMARY KEY,   -- = Config.Dealerships[].id
    owner_charid BIGINT UNSIGNED NULL,               -- characters.id (nullable = unassigned)
    till         BIGINT NOT NULL DEFAULT 0,          -- company money buffer (pays imports, salaries)
    INDEX idx_deal_owner (owner_charid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dealership_stock (
    dealer_id VARCHAR(48) NOT NULL,
    model     VARCHAR(64) NOT NULL,
    qty       INT NOT NULL DEFAULT 0,                -- units in showroom stock
    price     BIGINT NOT NULL DEFAULT 0,            -- owner retail price (0 = use catalog default)
    display   TINYINT NOT NULL DEFAULT 0,            -- 1 = exposed in the showroom
    PRIMARY KEY (dealer_id, model),
    INDEX idx_dstock_dealer (dealer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Custom grades (name + JSON perm keys, see Config.Permissions) + a per-grade commission %.
CREATE TABLE IF NOT EXISTS dealership_grades (
    id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    dealer_id  VARCHAR(48) NOT NULL,
    name       VARCHAR(48) NOT NULL,
    perms      JSON NULL,
    commission INT NOT NULL DEFAULT 0,               -- 0-100 % of each sale this grade closes
    salary     BIGINT NOT NULL DEFAULT 0,            -- fixed wage paid per salary tick (from till)
    INDEX idx_dgrades_dealer (dealer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dealership_employees (
    dealer_id VARCHAR(48) NOT NULL,
    charid    BIGINT UNSIGNED NOT NULL,
    grade_id  BIGINT UNSIGNED NULL,
    PRIMARY KEY (dealer_id, charid),
    INDEX idx_demp_char (charid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Import orders (the convoy loop). `remaining` = units still to spawn/load at the port.
-- ready_at = unix seconds when the cars become available at the port (15 min, or 5 min priority).
CREATE TABLE IF NOT EXISTS dealership_orders (
    id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    dealer_id VARCHAR(48) NOT NULL,
    model     VARCHAR(64) NOT NULL,
    qty       INT NOT NULL DEFAULT 1,
    remaining INT NOT NULL DEFAULT 1,
    ready_at  BIGINT NOT NULL DEFAULT 0,
    priority  TINYINT NOT NULL DEFAULT 0,
    status    VARCHAR(16) NOT NULL DEFAULT 'pending', -- pending | ready | delivered | cancelled
    created   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_dorders_dealer (dealer_id),
    INDEX idx_dorders_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Contact-form leads (phone "Annuaire des sociétés"). company_kind = 'dealership' | 'shop'.
CREATE TABLE IF NOT EXISTS company_leads (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    company_id    VARCHAR(48) NOT NULL,
    company_kind  VARCHAR(16) NOT NULL DEFAULT 'dealership',
    client_charid BIGINT UNSIGNED NOT NULL,
    client_name   VARCHAR(96) NULL,
    client_number VARCHAR(24) NULL,
    subject       VARCHAR(96) NULL,
    message       VARCHAR(512) NULL,
    status        VARCHAR(16) NOT NULL DEFAULT 'open',  -- open | handled
    created       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_leads_company (company_id),
    INDEX idx_leads_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
