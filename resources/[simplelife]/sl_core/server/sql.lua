--[[
    server/sql.lua — comment/string-aware SQL statement splitter (bug class B5).

    The original runner did  text:gmatch('[^;]+')  / naive split on ';'. A ';'
    inside a comment or a string literal broke parsing and split statements wrongly.

    splitStatements(text) walks the file ONE CHARACTER at a time as a tiny state
    machine, recognising:
      - line comments:   -- ... <newline>   and   # ... <newline>
      - block comments:  /* ... */
      - string literals: '...'  and  "..."  with backslash escapes AND doubled-quote
                         escapes ('' / "")
    Only a ';' encountered in NORMAL state terminates a statement. Comments and
    strings are preserved verbatim inside the emitted statement text (the DB engine
    parses them); we just don't let their ';' characters fool the splitter.

    Returns a list of trimmed, non-empty statement strings IN ORDER.
]]

local sql = {}

local STATE_NORMAL       = 1
local STATE_LINE_COMMENT = 2 -- started by -- or #
local STATE_BLOCK_COMMENT= 3 -- started by /*
local STATE_SQUOTE       = 4 -- inside '...'
local STATE_DQUOTE       = 5 -- inside "..."

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Split raw SQL text into individual statements, ignoring ';' inside comments/strings.
---@param text string
---@return string[]
function sql.splitStatements(text)
    local statements = {}
    local buf = {}            -- current statement characters
    local state = STATE_NORMAL
    local i = 1
    local len = #text

    local function pushChar(c) buf[#buf + 1] = c end

    local function flush()
        local stmt = trim(table.concat(buf))
        -- Drop empties and statements that are only a comment (no executable tokens).
        if stmt ~= '' then
            statements[#statements + 1] = stmt
        end
        buf = {}
    end

    while i <= len do
        local c = text:sub(i, i)
        local nxt = i < len and text:sub(i + 1, i + 1) or ''

        if state == STATE_NORMAL then
            if c == '-' and nxt == '-' then
                state = STATE_LINE_COMMENT
                pushChar(c); pushChar(nxt); i = i + 2
            elseif c == '#' then
                state = STATE_LINE_COMMENT
                pushChar(c); i = i + 1
            elseif c == '/' and nxt == '*' then
                state = STATE_BLOCK_COMMENT
                pushChar(c); pushChar(nxt); i = i + 2
            elseif c == "'" then
                state = STATE_SQUOTE
                pushChar(c); i = i + 1
            elseif c == '"' then
                state = STATE_DQUOTE
                pushChar(c); i = i + 1
            elseif c == ';' then
                -- Statement terminator in normal state.
                flush()
                i = i + 1
            else
                pushChar(c); i = i + 1
            end

        elseif state == STATE_LINE_COMMENT then
            pushChar(c)
            if c == '\n' then state = STATE_NORMAL end
            i = i + 1

        elseif state == STATE_BLOCK_COMMENT then
            if c == '*' and nxt == '/' then
                pushChar(c); pushChar(nxt); i = i + 2
                state = STATE_NORMAL
            else
                pushChar(c); i = i + 1
            end

        elseif state == STATE_SQUOTE then
            if c == '\\' then
                -- Backslash escape: consume this and the next char verbatim.
                pushChar(c); pushChar(nxt); i = i + 2
            elseif c == "'" and nxt == "'" then
                -- Doubled single-quote escape inside the literal.
                pushChar(c); pushChar(nxt); i = i + 2
            elseif c == "'" then
                pushChar(c); i = i + 1
                state = STATE_NORMAL
            else
                pushChar(c); i = i + 1
            end

        elseif state == STATE_DQUOTE then
            if c == '\\' then
                pushChar(c); pushChar(nxt); i = i + 2
            elseif c == '"' and nxt == '"' then
                pushChar(c); pushChar(nxt); i = i + 2
            elseif c == '"' then
                pushChar(c); i = i + 1
                state = STATE_NORMAL
            else
                pushChar(c); i = i + 1
            end
        end
    end

    -- Trailing statement with no terminating ';'.
    flush()

    -- Final pass: discard statements that contain no executable content (pure comments).
    local cleaned = {}
    for _, stmt in ipairs(statements) do
        if sql.hasExecutable(stmt) then
            cleaned[#cleaned + 1] = stmt
        end
    end
    return cleaned
end

--- Returns true if a statement contains executable SQL (not just comments/whitespace).
--- Reuses the same scanner: strips comments and checks for any remaining non-space char.
---@param stmt string
---@return boolean
function sql.hasExecutable(stmt)
    local state = STATE_NORMAL
    local i, len = 1, #stmt
    while i <= len do
        local c = stmt:sub(i, i)
        local nxt = i < len and stmt:sub(i + 1, i + 1) or ''
        if state == STATE_NORMAL then
            if c == '-' and nxt == '-' then state = STATE_LINE_COMMENT; i = i + 2
            elseif c == '#' then state = STATE_LINE_COMMENT; i = i + 1
            elseif c == '/' and nxt == '*' then state = STATE_BLOCK_COMMENT; i = i + 2
            elseif c == "'" then state = STATE_SQUOTE; i = i + 1
            elseif c == '"' then state = STATE_DQUOTE; i = i + 1
            elseif not c:match('%s') then return true
            else i = i + 1 end
        elseif state == STATE_LINE_COMMENT then
            if c == '\n' then state = STATE_NORMAL end
            i = i + 1
        elseif state == STATE_BLOCK_COMMENT then
            if c == '*' and nxt == '/' then state = STATE_NORMAL; i = i + 2 else i = i + 1 end
        else
            -- inside a string literal => executable content present
            return true
        end
    end
    return false
end

SLCore.module('sql', sql)
