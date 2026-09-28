--[[
    server/migrate.lua — the migration runner (bug classes B1 + B2 + B5).

    Invoked from EXACTLY ONE place: server/boot.lua (sl_core's own guarded boot).
    It does NOT auto-run on load. No feature resource can trigger it.

    ── B1 (migration race / double-apply) — TRIPLE GUARD ───────────────────────
      (a) In-process boolean latch `applied` — a second ApplyAll() in the same
          process is a no-op.
      (b) An sl_migrations(id PK, name, checksum, applied_at) ledger — files whose
          id already exists are SKIPPED.
      (c) A PERSISTED claim-row lock (sl_migrate_lock, PRIMARY KEY) around the whole
          apply phase. Unlike MariaDB GET_LOCK (which is SESSION-scoped and dies the
          instant its pooled connection is released — useless under oxmysql's pool),
          a claim ROW survives connection churn: the 2nd concurrent instance's INSERT
          fails on the PK and it backs off, so even a manual restart or a second
          server instance cannot double-apply concurrently. A crashed holder's lock
          auto-expires (TTL) and is atomically stolen. See db.acquireClaim.

    ── B2 (foreign-key order, errno 150) — TOPOLOGICAL SORT ─────────────────────
      All schema lives in migrations/*.sql. Each file's first line MAY declare
      deps:  "-- requires: accounts, characters". A migration "provides" the name
      derived from its file (sans numeric prefix / .sql). The runner builds a
      dependency graph over the declared TABLE names and topologically sorts files
      so a child (characters) never runs before its parent (accounts). The numeric
      prefix is a human cross-check; correctness comes from the toposort.
      Graph NODES are keyed by the unique FILE id (filename), never by the
      collision-prone provides-name; duplicate provides names are rejected at build
      time, so every file is emitted exactly once (no silent drop).

    ── B5 (split on ';') + DDL ATOMICITY CAVEAT ────────────────────────────────
      Each file is tokenised by SLCore.use('sql').splitStatements — comment/string
      aware — so a ';' inside a comment/string never mis-splits.

      IMPORTANT, HONEST LIMITATION: MySQL/MariaDB IMPLICITLY COMMIT on every DDL
      statement (CREATE/ALTER/DROP TABLE). Therefore wrapping CREATE TABLE + the
      ledger INSERT in ONE transaction does NOT give atomic rollback — the CREATE
      auto-commits immediately and a crash before the ledger INSERT would leave a
      created table with no ledger row. We DO NOT rely on transactional rollback for
      DDL. The real guards are:
        * every DDL migration is idempotent (CREATE TABLE IF NOT EXISTS / ADD COLUMN
          IF NOT EXISTS), so a re-run after a partial apply is a clean no-op, not a
          fatal errno 1050; and
        * the ledger INSERT runs as the LAST statement of the per-file transaction,
          so for pure-DML migrations the bundle IS atomic, and for DDL the
          IF-NOT-EXISTS + ledger-skip combination is self-healing.

    Reads files via LoadResourceFile(resource, 'migrations/<name>') and the ordered
    list in migrations/manifest.lua (returned as a Lua table).
]]

local migrate = {}

local applied = false          -- (B1a) in-process latch
local lastStatus = {
    applied = 0,
    present = 0,
    files = {},                -- { { name, id, provides, requires, status } }
}

local RESOURCE = GetCurrentResourceName()

-- ── helpers ────────────────────────────────────────────────────────────────

-- FNV-1a 32-bit checksum over the file body (stable, fast, no external deps).
local function checksum(str)
    local hash = 2166136261
    for i = 1, #str do
        hash = (hash ~ str:byte(i)) & 0xffffffff
        -- multiply by FNV prime 16777619 with 32-bit wraparound
        hash = (hash * 16777619) & 0xffffffff
    end
    return ('%08x'):format(hash)
end

-- Derive the "provides" name from a filename: '002_characters.sql' -> 'characters'.
local function provideName(filename)
    local base = filename:gsub('%.sql$', '')
    base = base:gsub('^%d+[_%-]?', '') -- strip leading numeric prefix + separator
    return base
end

-- Parse "-- requires: a, b, c" from the first non-empty line of the file.
local function parseRequires(body)
    local firstLine = body:match('^%s*([^\r\n]*)') or ''
    local list = firstLine:match('^%s*%-%-%s*requires:%s*(.*)$')
    local reqs = {}
    if list then
        for name in list:gmatch('([%w_]+)') do
            reqs[#reqs + 1] = name
        end
    end
    return reqs
end

-- Load the ordered manifest list of filenames.
local function loadManifest()
    local chunk = LoadResourceFile(RESOURCE, 'migrations/manifest.lua')
    if not chunk then
        error('migrate: migrations/manifest.lua not found')
    end
    local fn, err = load(chunk, '@@sl_core/migrations/manifest.lua')
    if not fn then
        error(('migrate: failed to load manifest.lua: %s'):format(err))
    end
    local list = fn()
    assert(type(list) == 'table', 'migrate: manifest.lua must return a table')
    return list
end

-- Read a migration file body.
local function readMigration(filename)
    local body = LoadResourceFile(RESOURCE, ('migrations/%s'):format(filename))
    if not body then
        error(('migrate: migration file not found: %s'):format(filename))
    end
    return body
end

-- Deterministic topological sort (B2). Kahn-like with stable ordering: among nodes
-- whose deps are satisfied, pick the one with the lowest manifest index so the
-- numeric prefix order is honoured as a tie-breaker. Raises on cycle / missing dep /
-- duplicate provides-name.
--
-- CRITICAL: nodes are tracked by their UNIQUE id (node.id == filename), NOT by the
-- collision-prone provides-name. Two files that strip to the same provides-name
-- (e.g. 001_accounts.sql and a future 005_accounts.sql -> both 'accounts') would
-- otherwise overwrite each other in the provides map and silently drop one file.
-- We key done[]/the pick loop by id, and detect duplicate provides names up front.
local function topoSort(nodes)
    -- nodes: array of { id=filename, name=provides, requires={...}, index=manifestIndex, file=... }

    -- provides-name -> node, with explicit duplicate detection.
    local provided = {}
    for _, n in ipairs(nodes) do
        if provided[n.name] then
            error(('migrate: two migrations both provide "%s": %s and %s — provides-names '
                .. 'must be unique (rename one file so its stripped name differs)')
                :format(n.name, provided[n.name].file, n.file))
        end
        provided[n.name] = n
    end

    -- validate deps exist
    for _, n in ipairs(nodes) do
        for _, dep in ipairs(n.requires) do
            if not provided[dep] then
                error(('migrate: %s requires "%s" which is not provided by any migration')
                    :format(n.file, dep))
            end
        end
    end

    local doneById = {}   -- node.id -> true once emitted (unique, never collides)
    -- A dep is "done" when the node that PROVIDES it has been emitted.
    local function depDone(depName)
        local provider = provided[depName]
        return provider ~= nil and doneById[provider.id] == true
    end

    local order = {}
    local remaining = #nodes

    while remaining > 0 do
        -- pick the lowest-index node (by manifest order) whose deps are all done
        local pick = nil
        for _, n in ipairs(nodes) do
            if not doneById[n.id] then
                local ready = true
                for _, dep in ipairs(n.requires) do
                    if not depDone(dep) then ready = false; break end
                end
                if ready and (not pick or n.index < pick.index) then
                    pick = n
                end
            end
        end

        if not pick then
            -- no progress possible => cycle
            local stuck = {}
            for _, n in ipairs(nodes) do
                if not doneById[n.id] then stuck[#stuck + 1] = n.file end
            end
            error(('migrate: dependency cycle detected among: %s'):format(table.concat(stuck, ', ')))
        end

        order[#order + 1] = pick
        doneById[pick.id] = true
        remaining = remaining - 1
    end

    return order
end

-- Ensure the ledger table exists. Safe to call repeatedly (IF NOT EXISTS).
local function ensureLedger(db)
    db.update([[
        CREATE TABLE IF NOT EXISTS sl_migrations (
            id          VARCHAR(128) NOT NULL PRIMARY KEY,
            name        VARCHAR(255) NOT NULL,
            checksum    CHAR(8)      NOT NULL,
            applied_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

-- Fetch the set of already-applied migration ids.
local function loadLedger(db)
    local rows = db.query('SELECT id, checksum FROM sl_migrations')
    local set = {}
    for _, r in ipairs(rows or {}) do
        set[r.id] = r.checksum
    end
    return set
end

-- ── public API ───────────────────────────────────────────────────────────────

--- Apply all pending migrations exactly once. Idempotent within a process (latch),
--- across ledger (skip applied), and across instances (PERSISTED claim lock that
--- survives oxmysql's connection-pool churn — see db.acquireClaim).
--- MUST be called from a Citizen thread (boot.lua satisfies this).
---@return { applied: integer, present: integer, skipped: integer }
function migrate.ApplyAll()
    if applied then
        Config.Log('warn', 'migrate.ApplyAll() called again — ignored (in-process latch).')
        return { applied = 0, present = lastStatus.present, skipped = lastStatus.present }
    end

    local db = SLCore.require('db')
    local sqlmod = SLCore.require('sql')

    -- (B1c) serialise across instances with a PERSISTED claim-row lock (NOT GET_LOCK,
    -- which would die with its pooled connection). A unique holder id lets us release
    -- only our own lock. TTL auto-expires a crashed holder's lock. The holder mixes
    -- the resource name, the boot-time game timer, and two random draws so two
    -- instances starting at the same instant don't collide on the same holder string.
    local holder = ('%s#%d.%d.%d'):format(
        RESOURCE, math.floor(GetGameTimer()), math.random(0, 0xffffff), math.random(0, 0xffffff))
    local gotLock = db.acquireClaim(
        Config.MigrateLock, holder, Config.MigrateLockTimeout, Config.MigrateLockTTL or 60
    )
    if not gotLock then
        error(('migrate: could not acquire migration claim lock "%s" within %ds (another instance migrating?)')
            :format(Config.MigrateLock, Config.MigrateLockTimeout))
    end

    local result = { applied = 0, present = 0, skipped = 0 }

    local ok, err = pcall(function()
        ensureLedger(db)
        local ledger = loadLedger(db)

        -- Build nodes from the manifest.
        local manifest = loadManifest()
        local nodes = {}
        for idx, filename in ipairs(manifest) do
            local body = readMigration(filename)
            nodes[#nodes + 1] = {
                file = filename,
                index = idx,
                name = provideName(filename),
                requires = parseRequires(body),
                body = body,
                id = filename, -- ledger id == filename (stable, unique)
            }
        end
        result.present = #nodes

        -- (B2) topologically sort by declared table deps.
        local order = topoSort(nodes)

        lastStatus.files = {}

        for _, node in ipairs(order) do
            local sum = checksum(node.body)
            local statusLabel

            if ledger[node.id] then
                -- (B1b) already applied — skip. Warn if the body changed.
                if ledger[node.id] ~= sum then
                    Config.Log('warn', ('migration %s already applied but checksum changed (%s -> %s); skipping (immutable).')
                        :format(node.id, ledger[node.id], sum))
                    statusLabel = 'skipped(changed)'
                else
                    statusLabel = 'skipped'
                end
                result.skipped = result.skipped + 1
            else
                -- (B5) split into statements; run them + the ledger INSERT in ONE
                -- transaction. For pure-DML files this bundle is truly atomic. For DDL
                -- files MySQL/MariaDB IMPLICITLY COMMITs each CREATE/ALTER, so the
                -- transaction gives NO rollback for the DDL — the real safety net is
                -- that every DDL migration uses IF NOT EXISTS (idempotent) so a re-run
                -- after a partial apply is a clean no-op, not a fatal errno 1050. The
                -- ledger INSERT being last means a re-run simply re-applies the
                -- IF-NOT-EXISTS DDL (no-op) and writes the ledger row.
                local statements = sqlmod.splitStatements(node.body)
                local queries = {}
                for _, stmt in ipairs(statements) do
                    queries[#queries + 1] = { query = stmt }
                end
                -- Append the ledger row LAST so it is the final committed statement.
                -- INSERT IGNORE: if a racing instance already ledgered this id between
                -- our loadLedger() and here, we don't fatal — the schema is identical
                -- and idempotent, so a swallowed duplicate ledger row is harmless.
                queries[#queries + 1] = {
                    query = 'INSERT IGNORE INTO sl_migrations (id, name, checksum) VALUES (?, ?, ?)',
                    values = { node.id, node.name, sum },
                }

                local committed = db.transaction(queries)
                if not committed then
                    error(('migrate: transaction failed applying %s (statements ran; check the '
                        .. 'oxmysql:transaction-error log for the failing statement)'):format(node.file))
                end

                Config.Log('info', ('applied migration %s (%d statements)'):format(node.file, #statements))
                result.applied = result.applied + 1
                statusLabel = 'applied'
            end

            lastStatus.files[#lastStatus.files + 1] = {
                name = node.file,
                id = node.id,
                provides = node.name,
                requires = node.requires,
                status = statusLabel,
            }
        end
    end)

    -- Always release OUR claim lock, even on error (holder match prevents stealing
    -- another instance's lock). pcall so a release failure cannot mask the real error.
    pcall(db.releaseClaim, Config.MigrateLock, holder)

    if not ok then
        error(err) -- propagate to boot.lua, which records bootError
    end

    applied = true
    lastStatus.applied = result.applied
    lastStatus.present = result.present
    return result
end

--- Read-only status snapshot for the /sl command and diagnostics.
---@return table
function migrate.Status()
    return {
        latched = applied,
        applied = lastStatus.applied,
        present = lastStatus.present,
        files = lastStatus.files,
    }
end

SLCore.module('migrate', migrate)
