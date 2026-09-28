--[[
    server/main.lua — sl_bank authoritative endpoints.

    The client can ONLY ask for a balance read or a deposit/withdraw of an amount; the
    server validates the amount and routes the money math through sl_core's economy
    (atomic cash<->bank with rollback). A crafted client call can never produce money:
    economy.deposit debits cash before crediting bank (and vice-versa), so the worst a
    bad actor can do is move their OWN money between their OWN accounts.

    All three endpoints are ox_lib callbacks (request/response); `source` is trusted
    (server-provided), the amount is not (clamped here).
]]

-- Clamp an incoming amount: positive integer within the sanity cap, else nil.
local function clampAmount(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return nil end
    if amount > (Config.MaxAmount or 10000000) then return nil end
    return amount
end

-- Current {cash, bank} for the caller (authoritative, from sl_core).
lib.callback.register('sl_bank:balances', function(src)
    local bal = exports.sl_core:economyBalance(src)  -- {cash=…, bank=…} or nil if no char
    if not bal then
        Config.Log('warn', ('balances: AUCUN perso chargé pour src=%s — sl_core:getChar(src) est nil '
            .. '(perso pas (re)chargé côté serveur, ex: après restart sl_core sans reconnexion)'):format(tostring(src)))
    end
    return bal
end)

-- Deposit cash -> bank. Returns { ok, balances }|{ ok=false, reason }.
lib.callback.register('sl_bank:deposit', function(src, amount)
    amount = clampAmount(amount)
    if not amount then return { ok = false, reason = 'BAD_AMOUNT' } end
    local ok, detail = exports.sl_core:economyDeposit(src, amount)
    if ok then
        Config.Log('info', ('deposit src=%d amount=%d'):format(src, amount))
        return { ok = true, balances = detail }
    end
    return { ok = false, reason = tostring(detail) }
end)

-- Withdraw bank -> cash. Returns { ok, balances }|{ ok=false, reason }.
lib.callback.register('sl_bank:withdraw', function(src, amount)
    amount = clampAmount(amount)
    if not amount then return { ok = false, reason = 'BAD_AMOUNT' } end
    local ok, detail = exports.sl_core:economyWithdraw(src, amount)
    if ok then
        Config.Log('info', ('withdraw src=%d amount=%d'):format(src, amount))
        return { ok = true, balances = detail }
    end
    return { ok = false, reason = tostring(detail) }
end)

Config.Log('info', 'banking endpoints ready (balances / deposit / withdraw)')
