-- requires: shops
-- 011_shop_business.sql — player-run shop businesses. Custom GRADES (name + a JSON array of
-- permission keys, see Config.Permissions) and EMPLOYEES (character -> grade) per shop. The
-- owner (shops.owner_charid) implicitly has every permission and is not stored here.
CREATE TABLE IF NOT EXISTS shop_grades (
    id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    shop_id VARCHAR(48) NOT NULL,
    name    VARCHAR(48) NOT NULL,
    perms   JSON NULL,
    INDEX idx_grades_shop (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS shop_employees (
    shop_id  VARCHAR(48) NOT NULL,
    charid   BIGINT UNSIGNED NOT NULL,
    grade_id BIGINT UNSIGNED NULL,
    PRIMARY KEY (shop_id, charid),
    INDEX idx_emp_char (charid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
