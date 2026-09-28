--[[
    server/economy.lua — thin economy services on top of the players registry.

    players.lua already owns the write-through money primitives (addMoney/
    removeMoney/transfer). economy.lua adds:
      * bank/cash convenience helpers,
      * the service-registry providers ('economy.tryDebit', 'economy.credit',
        'economy.balance', 'economy.transfer') so features call money operations
        through the registry envelope instead of hard exports.

    No DB access here — everything routes through players (single owner).
]]

local economy = {}

local function players() return SLCore.require('players') end
local function registry() return SLCore.require('registry') end

--- Attempt to debit an account; returns ok + reason. Never goes negative.
---@param src integer
---@param account 'cash'|'bank'
---@param amount integer
---@param reason? string
---@return boolean ok, any detail
function economy.tryDebit(src, account, amount, reason)
    return players().removeMoney(src, account, amount, reason or 'debit')
end

--- Credit an account.
---@param src integer
---@param account 'cash'|'bank'
---@param amount integer
---@param reason? string
---@return boolean ok, any detail
function economy.credit(src, account, amount, reason)
    return players().addMoney(src, account, amount, reason or 'credit')
end

--- Read a balance for an account, or both as a table.
---@param src integer
---@param account? 'cash'|'bank'
---@return integer|table?
function economy.balance(src, account)
    local char = players().getChar(src)
    if not char then return nil end
    if account == 'cash' or account == 'bank' then
        return char[account]
    end
    return { cash = char.cash, bank = char.bank }
end

--- Transfer between two players.
---@param fromSrc integer
---@param toSrc integer
---@param account 'cash'|'bank'
---@param amount integer
---@param reason? string
---@return boolean ok, any detail
function economy.transfer(fromSrc, toSrc, account, amount, reason)
    return players().transfer(fromSrc, toSrc, account, amount, reason)
end

--- Deposit: move `amount` from the SAME player's cash to their bank. Atomic at the
--- in-memory level (debits cash first; rolls the debit back if the credit fails). On
--- success returns the new {cash, bank}; on failure returns the reason.
---@param src integer
---@param amount integer
---@return boolean ok, any detail   -- detail = {cash,bank} on success, reason string on failure
function economy.deposit(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'BAD_AMOUNT' end
    local okDebit, d1 = players().removeMoney(src, 'cash', amount, 'bank:deposit')
    if not okDebit then return false, d1 end
    local okCredit, d2 = players().addMoney(src, 'bank', amount, 'bank:deposit')
    if not okCredit then
        players().addMoney(src, 'cash', amount, 'bank:deposit:rollback')  -- undo the debit
        return false, d2
    end
    return true, economy.balance(src)
end

--- Withdraw: move `amount` from the SAME player's bank to their cash. Atomic (rolls back
--- the bank debit if the cash credit fails). Returns the new {cash, bank} on success.
---@param src integer
---@param amount integer
---@return boolean ok, any detail
function economy.withdraw(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'BAD_AMOUNT' end
    local okDebit, d1 = players().removeMoney(src, 'bank', amount, 'bank:withdraw')
    if not okDebit then return false, d1 end
    local okCredit, d2 = players().addMoney(src, 'cash', amount, 'bank:withdraw')
    if not okCredit then
        players().addMoney(src, 'bank', amount, 'bank:withdraw:rollback')  -- undo the debit
        return false, d2
    end
    return true, economy.balance(src)
end

SLCore.module('economy', economy)

-- Register the services. Done at load; resolution is live at call time anyway.
local reg = registry()
reg.provide('economy.tryDebit', economy.tryDebit)
reg.provide('economy.credit', economy.credit)
reg.provide('economy.balance', economy.balance)
reg.provide('economy.transfer', economy.transfer)
reg.provide('economy.deposit', economy.deposit)
reg.provide('economy.withdraw', economy.withdraw)

-- Cross-resource convenience exports. Call with COLON: exports.sl_core:economyCredit(src, ...).
exports('economyTryDebit', function(src, account, amount, reason) return economy.tryDebit(src, account, amount, reason) end)
exports('economyCredit', function(src, account, amount, reason) return economy.credit(src, account, amount, reason) end)
exports('economyBalance', function(src, account) return economy.balance(src, account) end)
exports('economyDeposit', function(src, amount) return economy.deposit(src, amount) end)
exports('economyWithdraw', function(src, amount) return economy.withdraw(src, amount) end)
exports('economyTransfer', function(fromSrc, toSrc, account, amount, reason) return economy.transfer(fromSrc, toSrc, account, amount, reason) end)
