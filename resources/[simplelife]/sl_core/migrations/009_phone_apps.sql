-- requires: phones
-- 009_phone_apps.sql — installed-apps state for the iFruit Store. Device-centric. We store the
-- REMOVED (uninstalled) apps per device; absence of a row = installed, so the default (no rows)
-- means everything is installed. Mandatory apps (Config.Apps.mandatory) can never be removed
-- (enforced server-side), so they never appear here.
CREATE TABLE IF NOT EXISTS phone_removed_apps (
    phone_uuid VARCHAR(40) NOT NULL,
    app        VARCHAR(40) NOT NULL,
    PRIMARY KEY (phone_uuid, app)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
