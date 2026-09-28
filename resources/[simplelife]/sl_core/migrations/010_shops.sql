-- requires: characters
-- 010_shops.sql — shops for the sl_shops resource. One row per OWNABLE shop (lazily created
-- when an owner is first assigned, or stock/cash given). owner_charid NULL = NPC-run (24/7).
-- `till` is the shop's money buffer that sales credit and the owner withdraws to their bank.
CREATE TABLE IF NOT EXISTS shops (
    id           VARCHAR(48) NOT NULL PRIMARY KEY,    -- = Config.Shops[].id
    owner_charid BIGINT UNSIGNED NULL,                -- characters.id (nullable = unowned/NPC)
    till         BIGINT NOT NULL DEFAULT 0,
    INDEX idx_shops_owner (owner_charid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Per-shop retail stock (only used while a shop has an owner). qty depletes on sale; price is
-- the owner's retail price. Restocked at the wholesale NPC (qty += ; price kept).
CREATE TABLE IF NOT EXISTS shop_stock (
    shop_id VARCHAR(48) NOT NULL,
    item    VARCHAR(48) NOT NULL,
    qty     INT NOT NULL DEFAULT 0,
    price   BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (shop_id, item),
    INDEX idx_stock_shop (shop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
