--[[
    server/db.lua — the ONLY file in the entire framework that calls MySQL.* (oxmysql).

    Verified against oxmysql 2.14.1 (resources/oxmysql/lib/MySQL.lua + dist/build.js):
      MySQL.query.await(sql, params)        -> rows (array of row tables)
      MySQL.single.await(sql, params)       -> first row table or nil
      MySQL.scalar.await(sql, params)       -> first column of first row
      MySQL.insert.await(sql, params)       -> insertId (number)
      MySQL.update.await(sql, params)       -> affectedRows (number)
      MySQL.transaction.await(queries)      -> boolean (true on commit, false on rollback)
         queries = { { query = sql, values = params }, ... }  (ghmattimysql syntax)
         NOTE: rawTransaction resolves FALSE on a statement error (it does NOT reject),
         so callers test the boolean. The whole transaction pins ONE pooled connection
         for its lifetime (getConnection at start, released at end).

    ── WHY THERE IS NO db.getLock / GET_LOCK HERE (B1c, important) ───────────────
      oxmysql 2.14.1 is a CONNECTION POOL (build.js: createPool + getConnection/
      releaseConnection). Every MySQL.*.await call acquires a pooled connection and
      RELEASES it the instant the call returns — there is no connection pinning on
      the Lua .await path. MariaDB GET_LOCK/RELEASE_LOCK are SESSION-scoped: the lock
      dies the moment its owning connection returns to the pool. So a GET_LOCK run via
      MySQL.scalar.await would be released microseconds later, before any migration
      statement ran — the cross-instance guarantee would be a LIE.

      Instead the cross-instance migration guard is a PERSISTED CLAIM ROW
      (sl_migrate_lock, PRIMARY KEY) that survives pool churn: the 2nd concurrent
      instance's INSERT fails on the PK and it backs off. See db.acquireClaim /
      db.releaseClaim below and migrate.lua. This is robust by construction and does
      not depend on session pinning or the experimental MySQL.startTransaction API.

    All calls are .await style and MUST run inside a Citizen thread / coroutine
    (boot.lua and the command handlers satisfy this). The wrapper resolves the
    promise via Citizen.Await.

    Exposes module 'db' AND cross-resource exports dbQuery/dbSingle/dbScalar/
    dbInsert/dbUpdate/dbTransaction for future feature resources.
]]

local db = {}

--- Run a SELECT (or any statement) returning all rows.
---@param sql string
---@param params? table
---@return table rows
function db.query(sql, params)
    return MySQL.query.await(sql, params)
end

--- Return the first row (or nil).
---@param sql string
---@param params? table
---@return table?
function db.single(sql, params)
    return MySQL.single.await(sql, params)
end

--- Return a single scalar value (first column of first row).
---@param sql string
---@param params? table
---@return any
function db.scalar(sql, params)
    return MySQL.scalar.await(sql, params)
end

--- Run an INSERT and return the new insertId.
---@param sql string
---@param params? table
---@return integer insertId
function db.insert(sql, params)
    return MySQL.insert.await(sql, params)
end

--- Run an UPDATE/DELETE and return affectedRows.
---@param sql string
---@param params? table
---@return integer affectedRows
function db.update(sql, params)
    return MySQL.update.await(sql, params)
end

--- Run a list of statements atomically in ONE transaction.
--- Accepts a list of { query = sql, values = params } entries (oxmysql/ghmattimysql).
--- Returns true on commit. Any statement error rolls the whole transaction back.
---@param queries { query: string, values?: table }[]
---@return boolean committed
function db.transaction(queries)
    return MySQL.transaction.await(queries)
end

-- Ensure the persisted claim-lock table exists. IF NOT EXISTS => safe to call always.
local function ensureClaimTable()
    MySQL.update.await([[
        CREATE TABLE IF NOT EXISTS sl_migrate_lock (
            id          VARCHAR(64)  NOT NULL PRIMARY KEY,
            holder      VARCHAR(128) NOT NULL,
            acquired_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            expires_at  TIMESTAMP    NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

--- Acquire a PERSISTED cross-instance claim lock that survives connection-pool
--- churn (unlike GET_LOCK). The PRIMARY KEY makes a second concurrent INSERT fail,
--- so only one instance proceeds. A stale claim (past expires_at, e.g. a crashed
--- instance) is atomically stolen via a conditional UPDATE. Polls up to `timeout`s.
---@param name string     claim id (e.g. 'sl_migrate')
---@param holder string   unique id for this instance (used to release safely)
---@param timeout integer seconds to keep retrying before giving up
---@param ttl integer     lock lifetime in seconds (auto-expires if holder crashes)
---@return boolean acquired
function db.acquireClaim(name, holder, timeout, ttl)
    ensureClaimTable()
    local deadline = os.time() + (timeout or 30)
    repeat
        -- Try a fresh INSERT (succeeds only if no row holds this id).
        local insOk = pcall(function()
            MySQL.update.await(
                'INSERT INTO sl_migrate_lock (id, holder, acquired_at, expires_at) '
                .. 'VALUES (?, ?, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND))',
                { name, holder, ttl or 60 }
            )
        end)
        if insOk then return true end

        -- Row exists. Try to STEAL it only if it is expired (crashed holder), atomically.
        local affected = MySQL.update.await(
            'UPDATE sl_migrate_lock SET holder = ?, acquired_at = CURRENT_TIMESTAMP, '
            .. 'expires_at = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND) '
            .. 'WHERE id = ? AND expires_at < CURRENT_TIMESTAMP',
            { holder, ttl or 60, name }
        )
        if (tonumber(affected) or 0) >= 1 then return true end

        Wait(250) -- another live instance holds it; back off and retry
    until os.time() >= deadline
    return false
end

--- Release a claim lock, but ONLY if we still hold it (holder match) — never steal
--- someone else's lock on release.
---@param name string
---@param holder string
---@return boolean released
function db.releaseClaim(name, holder)
    local affected = MySQL.update.await(
        'DELETE FROM sl_migrate_lock WHERE id = ? AND holder = ?', { name, holder }
    )
    return (tonumber(affected) or 0) >= 1
end

--- Lightweight readiness probe used by the boot sequence.
---@return boolean
function db.ping()
    local ok, r = pcall(function() return MySQL.scalar.await('SELECT 1') end)
    return ok and tonumber(r) == 1
end

SLCore.module('db', db)

-- Cross-resource exports (future feature resources call these, never MySQL.* directly).
-- Call with COLON syntax:  exports.sl_core:dbQuery(sql, params)  (the CFX exports
-- wrapper consumes the proxy as `self`; the handler gets exactly sql, params).
exports('dbQuery', function(sql, params) return db.query(sql, params) end)
exports('dbSingle', function(sql, params) return db.single(sql, params) end)
exports('dbScalar', function(sql, params) return db.scalar(sql, params) end)
exports('dbInsert', function(sql, params) return db.insert(sql, params) end)
exports('dbUpdate', function(sql, params) return db.update(sql, params) end)
exports('dbTransaction', function(queries) return db.transaction(queries) end)
