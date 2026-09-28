--[[
    shared/config.lua — sl_bank settings (client + server read it).
]]

Config = {}

-- Standard GTA V ATM prop models that become interactable. (Fleeca banks/peds can be
-- added later as a separate target; ATMs cover the whole map for v1.)
Config.AtmModels = {
    'prop_atm_01',
    'prop_atm_02',
    'prop_atm_03',
    'prop_fleeca_atm',
}

-- ox_target prompt shown on an ATM.
Config.Target = {
    label    = 'Distributeur',
    icon     = 'fa-solid fa-money-bill-transfer',
    distance = 2.0,
}

-- Liquid Glass theme accent PER ATM MODEL: the targeted machine's model picks the colour.
-- Generic street distributeurs are red; Fleeca-branded machines are green. Any model not
-- listed in ModelAccent falls back to DefaultAccent.
Config.DefaultAccent = '#e0473b'  -- fallback -> red (the wall-recessed machine + anything unmapped)
Config.ModelAccent = {
    ['prop_fleeca_atm'] = '#46cf7c',  -- Fleeca branded standalone -> green
    ['prop_atm_01']     = '#aeb8c4',  -- freestanding pedestal (SHARK/FLEECA) -> grey (confirmed via dev log)
}

-- Server-side sanity cap on a single deposit/withdraw (anti-fat-finger / anti-overflow).
Config.MaxAmount = 10000000

---@param channel 'info'|'warn'|'error'|'debug'
---@param msg string
function Config.Log(channel, msg)
    local colour = channel == 'error' and '^1' or channel == 'warn' and '^3' or '^7'
    print(('^2[sl_bank]^7 %s%s^7'):format(colour, tostring(msg)))
end
