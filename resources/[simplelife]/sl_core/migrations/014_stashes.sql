-- requires: characters
-- 014_stashes.sql — generic persistent containers (stashes). Used by sl_inventory's stash API
-- so any feature can expose a DB-backed container with a weight cap. sl_vehicles uses one per
-- vehicle for the TRUNK (id = 'veh:<plate>'); houses/jobs can reuse it later. `items` is the
-- same JSON shape sl_inventory persists for the player grid ({ items = [ {slot,name,count,metadata} ] }).
CREATE TABLE IF NOT EXISTS stashes (
    id      VARCHAR(64) NOT NULL PRIMARY KEY,
    items   JSON NULL,
    updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
