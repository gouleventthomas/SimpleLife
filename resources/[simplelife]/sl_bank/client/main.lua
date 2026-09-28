--[[
    client/main.lua — sl_bank client: the ATM, rendered with the SimpleLife Liquid Glass
    menu (sl_ui), not ox_lib. Flow:
      target an ATM (sl_interact/ox_target) -> openAtm() fetches balances + opens the glass
      MENU (Espèces/Banque info + Déposer/Retirer) -> selecting an action opens the glass
      INPUT for the amount -> the amount round-trips to the server callback -> we reopen the
      menu with fresh balances. Menu/input results arrive on the 'sl_ui:nui' dispatch bus.

    The client holds NO authority — all money math is server-side (sl_core economy). ox_lib is
    still used for the request/response callbacks (balances / deposit / withdraw).
]]

local ATM = 'sl_bank_atm'      -- menu id
local DEPOSIT = 'sl_bank_deposit'
local WITHDRAW = 'sl_bank_withdraw'

-- Per-model Liquid Glass accent: model HASH -> colour (+ HASH -> name for dev logging).
local accentByHash, nameByHash = {}, {}
for _, name in ipairs(Config.AtmModels) do
    local h = GetHashKey(name)
    accentByHash[h] = (Config.ModelAccent and Config.ModelAccent[name]) or Config.DefaultAccent
    nameByHash[h] = name
end
-- The accent of the ATM currently being used (set on target; reused for the input + reopen).
local currentAccent = Config.DefaultAccent

local function notify(kind, msg) exports.sl_ui:notify(kind, msg) end

-- "1234567" -> "1 234 567" (French grouping). Defensive against nil.
local function fmt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign = ''
    if s:sub(1, 1) == '-' then sign = '-'; s = s:sub(2) end
    s = s:reverse():gsub('(%d%d%d)', '%1 '):reverse()
    return sign .. (s:gsub('^%s+', ''))
end

local REASONS = {
    BAD_AMOUNT         = 'Montant invalide.',
    INSUFFICIENT_FUNDS = 'Fonds insuffisants.',
    NO_CHAR            = 'Personnage non chargé.',
    NO_ACCOUNT         = 'Compte introuvable.',
}
local function reasonText(r) return REASONS[r] or ('Opération refusée (%s).'):format(tostring(r)) end

-- Open the ATM menu with fresh, authoritative balances.
local function openAtm()
    local b = lib.callback.await('sl_bank:balances', false)
    if not b then
        notify('error', 'Aucun personnage chargé — reconnecte-toi puis réessaie.')
        exports.sl_ui:close()  -- never leave the player focus-locked on a failed open
        return
    end
    exports.sl_ui:openMenu({
        id = ATM,
        title = 'Distributeur',
        subtitle = 'Banque',
        accent = currentAccent,
        items = {
            { id = 'cash', label = 'Espèces',         icon = 'cash', value = '$' .. fmt(b.cash), kind = 'info' },
            { id = 'bank', label = 'Compte bancaire', icon = 'bank', value = '$' .. fmt(b.bank), kind = 'info' },
            { id = 'deposit',  label = 'Déposer', icon = 'deposit',  description = 'Déposez vos espèces vers votre compte bancaire.' },
            { id = 'withdraw', label = 'Retirer', icon = 'withdraw', description = 'Retirez de l\'argent de votre compte bancaire.' },
        },
    })
end

-- Run a deposit/withdraw amount through the server, toast the result, reopen the menu.
local function applyOp(kind, amount)
    local res = lib.callback.await('sl_bank:' .. kind, false, amount)
    if res and res.ok then
        if kind == 'deposit' then
            notify('success', ('Déposé $%s — Banque : $%s'):format(fmt(amount), fmt(res.balances and res.balances.bank)))
        else
            notify('success', ('Retiré $%s — Espèces : $%s'):format(fmt(amount), fmt(res.balances and res.balances.cash)))
        end
    else
        notify('error', reasonText(res and res.reason))
    end
    openAtm()  -- back to the menu with updated balances
end

-- Menu / input results come back through the sl_ui dispatch bus.
AddEventHandler('sl_ui:nui', function(event, data)
    if not data then return end

    if event == 'menu:select' and data.menuId == ATM then
        if data.itemId == 'deposit' then
            exports.sl_ui:openInput({ id = DEPOSIT, title = 'Déposer', label = 'Montant (espèces → banque)', placeholder = '0', confirmLabel = 'Déposer', accent = currentAccent })
        elseif data.itemId == 'withdraw' then
            exports.sl_ui:openInput({ id = WITHDRAW, title = 'Retirer', label = 'Montant (banque → espèces)', placeholder = '0', confirmLabel = 'Retirer', accent = currentAccent })
        end

    elseif event == 'menu:close' and data.menuId == ATM then
        exports.sl_ui:close()

    elseif event == 'input:submit' and (data.id == DEPOSIT or data.id == WITHDRAW) then
        applyOp(data.id == DEPOSIT and 'deposit' or 'withdraw', data.value)

    elseif event == 'input:cancel' and (data.id == DEPOSIT or data.id == WITHDRAW) then
        openAtm()  -- Esc on the amount prompt goes BACK to the menu (not a full close)
    end
end)

-- Wire the ATM target once sl_interact (which depends on ox_target) is up.
CreateThread(function()
    local tries = 0
    while GetResourceState('sl_interact') ~= 'started' and tries < 100 do Wait(100); tries = tries + 1 end
    if GetResourceState('sl_interact') ~= 'started' then
        Config.Log('error', 'sl_interact not started — ATM targets NOT registered')
        return
    end
    exports.sl_interact:addModel(Config.AtmModels, {
        {
            label    = Config.Target.label,
            icon     = Config.Target.icon,
            distance = Config.Target.distance,
            onSelect = function(data)
                -- pick the Liquid Glass colour from the TARGETED machine's model
                local ent = data and data.entity
                local hash = (ent and ent ~= 0 and DoesEntityExist(ent)) and GetEntityModel(ent) or nil
                currentAccent = (hash and accentByHash[hash]) or Config.DefaultAccent
                if GlobalState.slCoreEnv == 'dev' and hash then
                    Config.Log('debug', ('ATM model=%s (hash=%s) -> accent=%s')
                        :format(nameByHash[hash] or '?', hash, currentAccent))
                end
                openAtm()
            end,
        },
    })
    Config.Log('info', ('ATM targets registered on %d models'):format(#Config.AtmModels))
end)

-- DEV convenience: open the ATM menu directly, without hunting for a prop to target.
RegisterCommand('atm', function()
    if GlobalState.slCoreEnv ~= 'dev' then return end
    openAtm()
end, false)
CreateThread(function()
    Wait(800)
    TriggerEvent('chat:addSuggestion', '/atm', 'DEV — ouvre le distributeur (test banque)')
end)
