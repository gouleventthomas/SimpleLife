--[[
    shared/codec.lua — THE single JSON boundary for the whole framework (bug class B4).

    Resource-global `Codec` (no `local`).

    ── Why this exists ──────────────────────────────────────────────────────────
    The original build called cjson.encode on a dense numeric-keyed Lua table
    ({ [1]=..., [2]=... }). cjson/json encodes that as a 0-indexed JS ARRAY, so a
    Lua slot 1 round-tripped back as JS index 0 → off-by-one corruption.

    FIX / RULES:
      * All framework JSON goes through Codec.encodeJson / Codec.decodeJson.
        Raw json.encode / json.decode is FORBIDDEN in feature code.
      * encodeJson NEVER lets a non-empty table serialise as a bare 0-indexed
        array UNLESS the caller explicitly opts in (the table is already a clean
        1..n sequence AND `allowArray` is requested, or it is wrapped by Codec.array).
      * MODELLING RULE: slot / collection data must be an ARRAY-OF-RECORDS,
        e.g.  { { slot = 1, item = 'water' }, { slot = 2, item = 'bread' } }
        — NEVER a bare numeric-keyed map  { [1] = 'water', [2] = 'bread' }.
        Use Codec.array(t) to tag a value as an intentional JSON array.

    ── EMPTY tables (read this) ─────────────────────────────────────────────────
      An untagged bare empty table `{}` is AMBIGUOUS (could be {} or []). This
      codec resolves it to an empty JSON OBJECT `{}` (the common case: default
      metadata / coords). If you need an empty JSON ARRAY `[]`, you MUST pass the
      value through Codec.array(t) — e.g. Codec.array({}) -> `[]`. A bare `{}`
      will NEVER produce `[]`.

    ── ROUND-TRIP truth (read this) ─────────────────────────────────────────────
      JSON object keys are ALWAYS strings. A numeric-keyed map { [1]=x } cannot
      round-trip back to numeric keys: it returns as { ['1']=x }. To stop silent
      corruption, encodeJson REJECTS a numeric-keyed map (a table whose keys are
      all numbers but which is not a clean 1..n sequence, OR a 1..n sequence that
      was NOT tagged with Codec.array) by raising/logging. Model such data as an
      array-of-records and tag it with Codec.array, or use string keys.
    ─────────────────────────────────────────────────────────────────────────────

    Pure module: no DB, no FiveM natives beyond the global `json` codec.

    CFX json note (verified against citizen/scripting/lua/json.lua on this server):
    the CitizenFX-bundled `json` global has NO `json.array` metatable and NO
    `json.empty_array` global (those belong to other json variants). Its encoder
    decides array-vs-object via an isarray() check; an EMPTY table `{}` encodes as
    `[]` (array) BY DEFAULT and only as `{}` (object) when its metatable carries
    `__jsontype = 'object'`. We therefore use __jsontype-tagged EMPTY_OBJECT /
    EMPTY_ARRAY singletons to make empty encodings explicit and deterministic.
    Non-empty 1..n tables already encode as JSON arrays, and object tables (string
    or stringified keys) already encode as JSON objects — no metatable needed there.
]]

Codec = {}

-- Sentinel key: a table carrying this is treated as an intentional JSON array.
local ARRAY_TAG = '__sl_array'

-- ── EMPTY-table sentinels (verified against the bundled CFX json.lua) ─────────
-- The CitizenFX `json` encoder (citizen/scripting/lua/json.lua) decides array-vs-
-- object via isarray(): an EMPTY table `{}` encodes as `[]` (array) BY DEFAULT, and
-- only encodes as `{}` (object) when its metatable carries __jsontype == 'object'.
-- (There is NO json.empty_array global in this runtime — confirmed.) So:
--   * empty OBJECT  -> a table tagged __jsontype='object'
--   * empty ARRAY   -> a bare `{}` (already encodes as `[]`); we tag it 'array'
--     anyway for explicitness and forward-compat with json variants that default
--     empty tables to objects.
-- These shared singletons are read-only to the encoder, so sharing is safe.
local EMPTY_OBJECT = setmetatable({}, { __jsontype = 'object' })
local EMPTY_ARRAY  = setmetatable({}, { __jsontype = 'array' })

--- Tag a Lua table as an INTENTIONAL JSON array (array-of-records, etc.).
--- The returned wrapper is unwrapped by encodeJson into a clean 1..n sequence.
---@generic T
---@param t T[]
---@return table
function Codec.array(t)
    return { [ARRAY_TAG] = true, data = t }
end

-- Classify a table without relying on `#t` (undefined for sparse tables in 5.4).
-- Walks keys once tracking count, max integer key, and whether any non-positive-
-- integer key exists. Returns:
--   kind = 'empty'    -> no keys
--   kind = 'sequence' -> clean 1..n integer keys, no holes
--   kind = 'nummap'   -> all keys are positive integers but with holes (sparse)
--   kind = 'object'   -> at least one non-integer / string key present
local function classify(t)
    local count, maxKey = 0, 0
    local hasNonInteger = false
    for k in pairs(t) do
        if type(k) == 'number' and k % 1 == 0 and k >= 1 then
            if k > maxKey then maxKey = k end
        else
            hasNonInteger = true
        end
        count = count + 1
    end
    if count == 0 then return 'empty' end
    if hasNonInteger then return 'object' end
    if count == maxKey then return 'sequence' end -- contiguous 1..n, no holes
    return 'nummap'                               -- positive integers but sparse
end

-- Forward declarations so buildArray and normaliseValue can mutually recurse
-- while staying file-local (no global namespace pollution — B3 hygiene).
local buildArray
local normaliseValue

-- Build a normalised JSON array from a 1..n source. Empty -> the CFX empty-array
-- sentinel so the encoder emits `[]`. Non-empty -> a plain 1..n table (CFX json
-- already encodes a holeless 1..n table as a JSON array; no metatable needed).
function buildArray(src, forceObject)
    local n = #src
    if n == 0 then return EMPTY_ARRAY end
    local out = {}
    for i = 1, n do
        out[i] = normaliseValue(src[i], forceObject)
    end
    return out
end

-- Recursively normalise a Lua value so the encoder cannot turn a MAP into an array.
-- Maps are forced to objects by stringifying their keys, guaranteeing a JSON object
-- `{ "1": ... }` rather than `[ ... ]`. A numeric-keyed map that was NOT tagged with
-- Codec.array is REJECTED (it cannot round-trip to numeric keys) — this enforces the
-- B4 modelling rule by construction instead of silently mangling it.
function normaliseValue(value, forceObjectForNumericMaps)
    if type(value) ~= 'table' then
        return value
    end

    -- Explicit array wrapper -> emit a true JSON array (recurse into its elements).
    if value[ARRAY_TAG] then
        return buildArray(value.data or {}, forceObjectForNumericMaps)
    end

    local kind = classify(value)

    if kind == 'empty' then
        -- Ambiguous bare {}. Documented choice: empty OBJECT (tagged so the CFX
        -- encoder emits `{}`, not its default `[]`). Use Codec.array({}) to get [].
        return EMPTY_OBJECT
    end

    if kind == 'sequence' then
        if forceObjectForNumericMaps then
            -- An untagged bare 1..n sequence: reject rather than guess. The caller
            -- must tag intentional arrays (Codec.array) or pass opts.allowArray.
            error('Codec.encodeJson: untagged numeric/sequence table — wrap intentional '
                .. 'arrays in Codec.array(t) (or pass opts.allowArray=true). Numeric-keyed '
                .. 'maps cannot round-trip to numeric keys; model as array-of-records.', 0)
        end
        -- Caller explicitly allowed bare arrays.
        return buildArray(value, forceObjectForNumericMaps)
    end

    if kind == 'nummap' then
        -- Sparse positive-integer keys ({ [1]=a, [3]=c }). Always a hard error:
        -- there is no safe JSON representation that round-trips to numeric keys.
        error('Codec.encodeJson: sparse numeric-keyed map detected — JSON object keys '
            .. 'are strings and will NOT round-trip to numbers. Model as array-of-records '
            .. 'tagged with Codec.array(t), or use string keys.', 0)
    end

    -- kind == 'object': stringify any (positive-integer) keys defensively so encode
    -- always emits an object, never a 0-indexed array. Core B4 protection.
    local out = {}
    for k, v in pairs(value) do
        local key = type(k) == 'number' and tostring(k) or k
        out[key] = normaliseValue(v, forceObjectForNumericMaps)
    end
    return out
end

--- Encode a Lua value to a JSON string.
--- By default, numeric-keyed maps are forced to JSON objects (B4 protection).
--- Pass an array via Codec.array(t) (or opts.allowArray=true on clean sequences)
--- when you genuinely want a JSON array.
---@param value any
---@param opts? { allowArray?: boolean }
---@return string
function Codec.encodeJson(value, opts)
    opts = opts or {}
    -- forceObjectForNumericMaps = true unless caller explicitly allows bare arrays.
    local forceObject = not opts.allowArray
    local ok, normalised = pcall(normaliseValue, value, forceObject)
    if not ok then
        -- A modelling-rule violation (sparse/untagged numeric map). Surface it loudly
        -- but do NOT let one bad payload crash a save path; the caller gets nil and a log.
        if Config and Config.Log then
            Config.Log('error', ('Codec.encodeJson rejected a value: %s'):format(tostring(normalised)))
        end
        return nil
    end
    return json.encode(normalised)
end

--- Decode a JSON string to a Lua value. Returns nil on nil/empty input.
---@param str string?
---@return any
function Codec.decodeJson(str)
    if str == nil or str == '' then return nil end
    if type(str) == 'table' then return str end -- already decoded by oxmysql JSON column
    local ok, decoded = pcall(json.decode, str)
    if not ok then
        if Config and Config.Log then
            Config.Log('error', ('Codec.decodeJson failed: %s'):format(tostring(decoded)))
        end
        return nil
    end
    return decoded
end
