--[[
    client/main.lua — sl_admin client: the F10 admin/debug menu (Liquid Glass) + actions.

    A tiny menu ENGINE drives nested menus over sl_ui's openMenu: a stack of menu BUILDERS
    (functions that return a fresh def) so re-show always reflects live values, Escape pops one
    level (or closes at the root), and selecting a category pushes its submenu. The menu only
    OPENS for admins (checked once via callback); the SERVER re-checks the ace on every action,
    so the client gate is UX only. Noclip + debug live in their own files (Noclip / Debug).
]]

local isAdmin = false
local stack = {}          -- array of builder fns: () -> def
local handlers = {}        -- itemId -> fn (current menu)
local inputHandlers = {}   -- inputId -> fn(value)
local currentMenuId = nil
local moneyAccount = 'cash'
-- godmode intent lives on the shared Noclip table (Noclip.godmode) so noclip's exit doesn't
-- clobber it. (Noclip loads before main.lua per the manifest, so the table already exists.)

local function notify(kind, msg) exports.sl_ui:notify(kind, msg) end

local function fmt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign = ''
    if s:sub(1, 1) == '-' then sign = '-'; s = s:sub(2) end
    s = s:reverse():gsub('(%d%d%d)', '%1 '):reverse()
    return sign .. (s:gsub('^%s+', ''))
end

-- forward declarations (builders reference each other inside closures)
local buildAndShow, openMenu, reshow, back, closeAdmin
local rootMenu, moneyMenu, weaponsRootMenu, weaponsListMenu, vehiclesRootMenu, vehiclesListMenu,
      playersMenu, playerActionMenu, selfMenu, debugMenu,
      itemsMenu, itemListMenu, playersForItemMenu, devMenu, cryptoGiveMenu,
      shopsAdminMenu, shopActionMenu, shopAssignPlayers,
      dealersAdminMenu, dealerActionMenu, dealerAssignPlayers, dealerStockModels, giveVehicleMenu

-- ── menu engine ───────────────────────────────────────────────────────────────
function buildAndShow(builder)
    local def = builder()
    handlers = {}
    currentMenuId = def.id
    local ui = {}
    for _, it in ipairs(def.items) do
        if it.onSelect then handlers[it.id] = it.onSelect end
        ui[#ui + 1] = {
            id = it.id, label = it.label, icon = it.icon, value = it.value,
            description = it.description, kind = it.kind, disabled = it.disabled,
        }
    end
    exports.sl_ui:openMenu({
        id = def.id, title = def.title, subtitle = def.subtitle,
        accent = def.accent or Config.Accent, items = ui,
    })
end

function openMenu(builder)
    stack[#stack + 1] = builder
    buildAndShow(builder)
end

function reshow()
    local b = stack[#stack]
    if b then buildAndShow(b) end
end

function closeAdmin()
    stack = {}
    handlers = {}
    inputHandlers = {}
    currentMenuId = nil
    exports.sl_ui:close()
end

function back()
    stack[#stack] = nil
    local b = stack[#stack]
    if b then buildAndShow(b) else closeAdmin() end
end

-- ── client effect handlers (all server-gated upstream) ────────────────────────
RegisterNetEvent('sl_admin:notify', function(kind, msg) notify(kind, msg) end)

RegisterNetEvent('sl_admin:client:giveWeapon', function(weapon)
    GiveWeaponToPed(PlayerPedId(), GetHashKey(weapon), 250, false, true)
    notify('success', 'Arme reçue.')
end)

RegisterNetEvent('sl_admin:client:removeWeapons', function()
    RemoveAllPedWeapons(PlayerPedId(), true)
    notify('info', 'Armes retirées.')
end)

RegisterNetEvent('sl_admin:client:spawnVehicle', function(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then notify('error', 'Modèle invalide.'); return end
    RequestModel(hash)
    local w = 0
    while not HasModelLoaded(hash) and w < 8000 do Wait(50); w = w + 50 end
    if not HasModelLoaded(hash) then notify('error', 'Modèle non chargé.'); return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local veh = CreateVehicle(hash, c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehicleEngineOn(veh, true, true, false)
    SetPedIntoVehicle(ped, veh, -1)
    notify('success', 'Véhicule spawné.')
end)

RegisterNetEvent('sl_admin:client:vehAction', function(act)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then notify('warn', 'Pas dans un véhicule.'); return end
    if act == 'fix' then
        SetVehicleFixed(veh); SetVehicleDeformationFixed(veh)
        SetVehicleEngineHealth(veh, 1000.0); SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleEngineOn(veh, true, true, false)
        notify('success', 'Véhicule réparé.')
    elseif act == 'flip' then
        SetVehicleOnGroundProperly(veh); notify('info', 'Remis sur roues.')
    elseif act == 'delete' then
        SetEntityAsMissionEntity(veh, true, true); DeleteVehicle(veh); notify('info', 'Véhicule supprimé.')
    end
end)

RegisterNetEvent('sl_admin:client:self', function(act)
    local ped = PlayerPedId()
    if act == 'heal' then
        SetEntityHealth(ped, GetEntityMaxHealth(ped)); ClearPedBloodDamage(ped); notify('success', 'Soigné.')
    elseif act == 'armor' then
        SetPedArmour(ped, 100); notify('success', 'Gilet à 100.')
    elseif act == 'godmode' then
        Noclip.godmode = not Noclip.godmode
        SetPlayerInvincible(PlayerId(), Noclip.godmode); SetEntityInvincible(ped, Noclip.godmode)
        notify('info', 'Godmode ' .. (Noclip.godmode and 'activé' or 'désactivé'))
    end
end)

RegisterNetEvent('sl_admin:client:teleport', function(c)
    if not c then return end
    local ped = PlayerPedId()
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoordsNoOffset(ped, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false)
    local w = 0
    while not HasCollisionLoadedAroundEntity(ped) and w < 3000 do
        RequestCollisionAtCoord(c.x, c.y, c.z); Wait(50); w = w + 50
    end
    notify('info', 'Téléporté.')
end)

-- ── menu builders ─────────────────────────────────────────────────────────────
function rootMenu()
    return { id = 'sl_admin_root', title = 'Menu Admin', subtitle = 'SimpleLife', accent = Config.Accent, items = {
        { id = 'money',    label = 'Argent',     icon = 'cash',  description = 'Donner / retirer espèces & banque', onSelect = function() openMenu(moneyMenu) end },
        { id = 'weapons',  label = 'Armes',      icon = 'gun',   description = 'Donner des armes par catégorie',     onSelect = function() openMenu(weaponsRootMenu) end },
        { id = 'vehicles', label = 'Véhicules',  icon = 'car',   description = 'Faire spawn un véhicule',            onSelect = function() openMenu(vehiclesRootMenu) end },
        { id = 'items',    label = 'Items',      icon = 'shop',  description = 'Donner un item (toi / un joueur)',   onSelect = function() openMenu(itemsMenu) end },
        { id = 'players',  label = 'Joueurs',    icon = 'users', description = 'Se TP / ramener un joueur',          onSelect = function() openMenu(playersMenu) end },
        { id = 'self',     label = 'Moi-même',   icon = 'user',  description = 'Soin, gilet, godmode',               onSelect = function() openMenu(selfMenu) end },
        { id = 'noclip',   label = 'Noclip',     icon = 'ghost', description = 'Vol libre (style txAdmin)',          onSelect = function()
            local on = Noclip.toggle(); closeAdmin(); notify('info', 'Noclip ' .. (on and 'activé — vole avec ZQSD' or 'désactivé')) end },
        { id = 'debug',    label = 'Debug',      icon = 'bug',   description = 'Coords, inspecteur de modèles...',   onSelect = function() openMenu(debugMenu) end },
        { id = 'dev',      label = 'Dev / Test', icon = 'coins', description = 'Donner crypto, vider l\'inventaire…', onSelect = function() openMenu(devMenu) end },
    }}
end

function moneyMenu()
    local char = exports.sl_core:getLocalChar()
    local accLabel = (moneyAccount == 'bank') and 'Banque' or 'Espèces'
    local items = {
        { id = 'cash_info', label = 'Espèces', icon = 'cash', value = '$' .. fmt(char and char.cash or 0), kind = 'info' },
        { id = 'bank_info', label = 'Banque',  icon = 'bank', value = '$' .. fmt(char and char.bank or 0), kind = 'info' },
        { id = 'acc', label = 'Compte ciblé', icon = 'card', value = accLabel, description = 'Bascule espèces / banque', onSelect = function()
            moneyAccount = (moneyAccount == 'bank') and 'cash' or 'bank'; reshow() end },
    }
    for _, amt in ipairs(Config.MoneyPresets) do
        items[#items + 1] = { id = 'g_' .. amt, label = 'Donner $' .. fmt(amt), icon = 'deposit',
            onSelect = function() TriggerServerEvent('sl_admin:money', moneyAccount, amt) end }
    end
    items[#items + 1] = { id = 'custom', label = 'Montant personnalisé', icon = 'coins', onSelect = function()
        inputHandlers['sl_admin_money'] = function(v) TriggerServerEvent('sl_admin:money', moneyAccount, v) end
        exports.sl_ui:openInput({ id = 'sl_admin_money', title = 'Donner de l\'argent',
            label = 'Montant (' .. accLabel:lower() .. ')', placeholder = '0', confirmLabel = 'Donner', accent = Config.Accent })
    end }
    items[#items + 1] = { id = 'rm', label = 'Retirer $5 000', icon = 'withdraw',
        onSelect = function() TriggerServerEvent('sl_admin:money', moneyAccount, -5000) end }
    return { id = 'sl_admin_money', title = 'Argent', subtitle = accLabel, accent = Config.Accent, items = items }
end

function weaponsRootMenu()
    local items = {
        { id = 'removeall', label = 'Retirer toutes les armes', icon = 'trash',
            onSelect = function() TriggerServerEvent('sl_admin:removeWeapons') end },
    }
    for _, cat in ipairs(Config.Weapons) do
        items[#items + 1] = { id = 'cat_' .. cat.cat, label = cat.cat, icon = cat.icon or 'gun',
            onSelect = function() openMenu(function() return weaponsListMenu(cat) end) end }
    end
    return { id = 'sl_admin_weapons', title = 'Armes', subtitle = 'Catégories', accent = Config.Accent, items = items }
end

function weaponsListMenu(cat)
    local items = {}
    for _, w in ipairs(cat.list) do
        items[#items + 1] = { id = w.weapon, label = w.label, icon = 'gun',
            onSelect = function() TriggerServerEvent('sl_admin:weapon', w.weapon) end }
    end
    return { id = 'sl_admin_weaplist', title = cat.cat, subtitle = 'Armes', accent = Config.Accent, items = items }
end

function vehiclesRootMenu()
    local items = {
        { id = 'fix',  label = 'Réparer mon véhicule', icon = 'wrench', onSelect = function() TriggerServerEvent('sl_admin:vehAction', 'fix') end },
        { id = 'flip', label = 'Remettre sur roues',   icon = 'wrench', onSelect = function() TriggerServerEvent('sl_admin:vehAction', 'flip') end },
        { id = 'del',  label = 'Supprimer le véhicule', icon = 'trash', onSelect = function() TriggerServerEvent('sl_admin:vehAction', 'delete') end },
    }
    for _, cat in ipairs(Config.Vehicles) do
        items[#items + 1] = { id = 'cat_' .. cat.cat, label = cat.cat, icon = cat.icon or 'car',
            onSelect = function() openMenu(function() return vehiclesListMenu(cat) end) end }
    end
    return { id = 'sl_admin_vehicles', title = 'Véhicules', subtitle = 'Catégories', accent = Config.Accent, items = items }
end

function vehiclesListMenu(cat)
    local items = {}
    for _, v in ipairs(cat.list) do
        items[#items + 1] = { id = v.model, label = v.label, icon = 'car', value = v.model,
            onSelect = function() TriggerServerEvent('sl_admin:vehicle', v.model) end }
    end
    return { id = 'sl_admin_vehlist', title = cat.cat, subtitle = 'Modèles', accent = Config.Accent, items = items }
end

function itemsMenu()
    return { id = 'sl_admin_items', title = 'Items', subtitle = 'Inventaire', accent = Config.Accent, items = {
        { id = 'self',  label = 'Me donner un item',  icon = 'shop',  onSelect = function() openMenu(function() return itemListMenu(nil) end) end },
        { id = 'other', label = 'Donner à un joueur', icon = 'users', onSelect = function() openMenu(playersForItemMenu) end },
    }}
end

-- Build a give-item list from sl_inventory's catalogue. targetId nil = give to self.
function itemListMenu(targetId)
    local catalog = (GetResourceState('sl_inventory') == 'started') and exports.sl_inventory:getCatalog() or {}
    local items = {}
    if #catalog == 0 then
        items[1] = { id = 'none', label = 'sl_inventory indisponible', kind = 'info' }
    end
    for _, it in ipairs(catalog) do
        local name, label = it.name, it.label
        items[#items + 1] = { id = name, label = label, icon = 'shop', value = name, onSelect = function()
            inputHandlers['sl_admin_item'] = function(qty)
                if targetId then TriggerServerEvent('sl_admin:giveItemTo', targetId, name, qty)
                else TriggerServerEvent('sl_admin:giveItem', name, qty) end
            end
            exports.sl_ui:openInput({ id = 'sl_admin_item', title = 'Quantité', label = label,
                placeholder = '1', confirmLabel = 'Donner', accent = Config.Accent })
        end }
    end
    return { id = 'sl_admin_itemlist', title = targetId and ('Donner à #' .. targetId) or 'Me donner',
        subtitle = 'Items', accent = Config.Accent, items = items }
end

function playersForItemMenu()
    local players = lib.callback.await('sl_admin:getPlayers', false) or {}
    local items = {}
    if #players == 0 then items[1] = { id = 'none', label = 'Aucun joueur', kind = 'info' } end
    for _, p in ipairs(players) do
        items[#items + 1] = { id = 'p_' .. p.id, label = ('[%d] %s'):format(p.id, p.name), icon = 'user',
            onSelect = function() openMenu(function() return itemListMenu(p.id) end) end }
    end
    return { id = 'sl_admin_itemplayers', title = 'Donner à un joueur', subtitle = #players .. ' en ligne',
        accent = Config.Accent, items = items }
end

function playersMenu()
    local players = lib.callback.await('sl_admin:getPlayers', false) or {}
    local items = {}
    if #players == 0 then
        items[1] = { id = 'none', label = 'Aucun joueur', kind = 'info' }
    else
        for _, p in ipairs(players) do
            items[#items + 1] = { id = 'p_' .. p.id, label = ('[%d] %s'):format(p.id, p.name) .. (p.self and ' (moi)' or ''),
                icon = 'user', onSelect = function() openMenu(function() return playerActionMenu(p) end) end }
        end
    end
    return { id = 'sl_admin_players', title = 'Joueurs', subtitle = #players .. ' en ligne', accent = Config.Accent, items = items }
end

function playerActionMenu(p)
    return { id = 'sl_admin_player', title = p.name, subtitle = 'ID ' .. p.id, accent = Config.Accent, items = {
        { id = 'goto',  label = 'Se téléporter à lui', icon = 'pin', onSelect = function() TriggerServerEvent('sl_admin:goto', p.id) end },
        { id = 'bring', label = 'Le ramener sur moi',   icon = 'pin', onSelect = function() TriggerServerEvent('sl_admin:bring', p.id) end },
    }}
end

function selfMenu()
    return { id = 'sl_admin_self', title = 'Moi-même', subtitle = 'Joueur', accent = Config.Accent, items = {
        { id = 'heal',  label = 'Soigner (full vie)', icon = 'heart',  onSelect = function() TriggerServerEvent('sl_admin:self', 'heal') end },
        { id = 'armor', label = 'Gilet pare-balles',  icon = 'shield', onSelect = function() TriggerServerEvent('sl_admin:self', 'armor') end },
        { id = 'god',   label = 'Godmode (on/off)',   icon = 'shield', description = 'Invincibilité', onSelect = function() TriggerServerEvent('sl_admin:self', 'godmode') end },
    }}
end

function debugMenu()
    return { id = 'sl_admin_debug', title = 'Debug', subtitle = 'Outils dev', accent = Config.DebugAccent, items = {
        { id = 'coords',  label = 'Mes coordonnées',     icon = 'pin',  description = 'Imprime position + heading (F8)', onSelect = function() Debug.printCoords() end },
        { id = 'inspect', label = 'Inspecter ce que je vise', icon = 'bug', description = 'Raycast : modèle / hash / type / coords', onSelect = function() Debug.inspectAim() end },
        { id = 'veh',     label = 'Infos véhicule actuel', icon = 'car', description = 'Modèle / plaque / netId (F8)', onSelect = function() Debug.printVehicle() end },
        { id = 'heading', label = 'Mon heading',          icon = 'pin',  onSelect = function() Debug.printHeading() end },
    }}
end

-- ── dev / test tools (admin-gated; replaces chat commands like /givecrypto) ────
function devMenu()
    return { id = 'sl_admin_dev', title = 'Dev / Test', subtitle = 'Outils', accent = Config.DebugAccent, items = {
        { id = 'crypto',   label = 'Donner de la crypto',  icon = 'coins', description = 'Créditer un coin sur mon téléphone', onSelect = function() openMenu(cryptoGiveMenu) end },
        { id = 'shops',    label = 'Boutiques (LTD)',      icon = 'shop',  description = 'Assigner un proprio, cash & stock',  onSelect = function() openMenu(shopsAdminMenu) end },
        { id = 'dealers',  label = 'Concessions',          icon = 'car',   description = 'Assigner un proprio, caisse & stock', onSelect = function() openMenu(dealersAdminMenu) end },
        { id = 'givecar',  label = 'Donner un véhicule',   icon = 'car',   description = 'Me faire spawn un véhicule possédé', onSelect = function() openMenu(giveVehicleMenu) end },
        { id = 'impound',  label = 'Mes véhicules → fourrière', icon = 'trash', description = 'Envoie mes véhicules dehors à la fourrière', onSelect = function() TriggerServerEvent('sl_admin:vehImpound') end },
        { id = 'clearinv', label = 'Vider mon inventaire',  icon = 'trash', description = 'Supprime tous mes items',           onSelect = function() TriggerServerEvent('sl_admin:clearInv') end },
    }}
end

-- ── concessions admin: assign owners, top up till / stock, give vehicles ──────
function dealersAdminMenu()
    local dealers = (GetResourceState('sl_vehicles') == 'started') and lib.callback.await('sl_vehicles:adminListDealers', false) or {}
    local items = {}
    if not dealers or #dealers == 0 then items[1] = { id = 'none', label = 'sl_vehicles indisponible / aucune concession', kind = 'info' } end
    for _, d in ipairs(dealers or {}) do
        items[#items + 1] = { id = d.id, label = d.label, icon = 'car',
            value = d.owner and ('proprio #' .. tostring(d.owner)) or 'libre',
            onSelect = function() openMenu(function() return dealerActionMenu(d) end) end }
    end
    return { id = 'sl_admin_dealers', title = 'Concessions', subtitle = 'Gestion', accent = Config.DebugAccent, items = items }
end

function dealerActionMenu(dealer)
    return { id = 'sl_admin_dealeract', title = dealer.label,
        subtitle = dealer.owner and ('Proprio charId ' .. tostring(dealer.owner)) or 'Sans propriétaire',
        accent = Config.DebugAccent, items = {
        { id = 'assign', label = 'Assigner un propriétaire', icon = 'user',
            onSelect = function() openMenu(function() return dealerAssignPlayers(dealer.id) end) end },
        { id = 'clear',  label = 'Retirer le propriétaire', icon = 'trash',
            onSelect = function() TriggerServerEvent('sl_admin:dealerClear', dealer.id) end },
        { id = 'cash',   label = 'Ajouter à la caisse', icon = 'cash', onSelect = function()
            inputHandlers['sl_admin_dealercash'] = function(v) TriggerServerEvent('sl_admin:dealerCash', dealer.id, v) end
            exports.sl_ui:openInput({ id = 'sl_admin_dealercash', title = 'Caisse — ' .. dealer.label,
                label = 'Montant', placeholder = '50000', confirmLabel = 'Ajouter', accent = Config.DebugAccent })
        end },
        { id = 'stock',  label = 'Ajouter du stock (modèle)', icon = 'shop',
            onSelect = function() openMenu(function() return dealerStockModels(dealer.id) end) end },
    }}
end

function dealerAssignPlayers(dealerId)
    local players = lib.callback.await('sl_admin:getPlayers', false) or {}
    local items = {}
    if #players == 0 then items[1] = { id = 'none', label = 'Aucun joueur', kind = 'info' } end
    for _, p in ipairs(players) do
        items[#items + 1] = { id = 'p_' .. p.id, label = ('[%d] %s'):format(p.id, p.name), icon = 'user',
            onSelect = function() TriggerServerEvent('sl_admin:dealerAssign', p.id, dealerId) end }
    end
    return { id = 'sl_admin_dealerassign', title = 'Assigner proprio', subtitle = dealerId, accent = Config.DebugAccent, items = items }
end

function dealerStockModels(dealerId)
    local catalog = (GetResourceState('sl_vehicles') == 'started') and lib.callback.await('sl_vehicles:adminCatalog', false) or {}
    local items = {}
    if not catalog or #catalog == 0 then items[1] = { id = 'none', label = 'Catalogue indisponible', kind = 'info' } end
    for _, c in ipairs(catalog or {}) do
        items[#items + 1] = { id = c.model, label = c.label, icon = 'car', value = c.model, onSelect = function()
            inputHandlers['sl_admin_dealerstock'] = function(v) TriggerServerEvent('sl_admin:dealerStock', dealerId, c.model, v) end
            exports.sl_ui:openInput({ id = 'sl_admin_dealerstock', title = 'Stock — ' .. c.label,
                label = 'Quantité', placeholder = '3', confirmLabel = 'Ajouter', accent = Config.DebugAccent })
        end }
    end
    return { id = 'sl_admin_dealerstockmodels', title = 'Ajouter du stock', subtitle = dealerId, accent = Config.DebugAccent, items = items }
end

function giveVehicleMenu()
    local catalog = (GetResourceState('sl_vehicles') == 'started') and lib.callback.await('sl_vehicles:adminCatalog', false) or {}
    local items = {}
    if not catalog or #catalog == 0 then items[1] = { id = 'none', label = 'Catalogue indisponible', kind = 'info' } end
    for _, c in ipairs(catalog or {}) do
        items[#items + 1] = { id = c.model, label = c.label, icon = 'car', value = '$' .. tostring(c.price),
            onSelect = function() TriggerServerEvent('sl_admin:giveVehicle', c.model) end }
    end
    return { id = 'sl_admin_givecar', title = 'Donner un véhicule', subtitle = 'À moi', accent = Config.DebugAccent, items = items }
end

-- give crypto to SELF: pick a coin (from sl_phone's catalogue) -> amount -> server credits.
function cryptoGiveMenu()
    local coins = (GetResourceState('sl_phone') == 'started') and exports.sl_phone:getCoins() or {}
    local items = {}
    if not coins or #coins == 0 then items[1] = { id = 'none', label = 'sl_phone indisponible', kind = 'info' } end
    for _, c in ipairs(coins or {}) do
        items[#items + 1] = { id = c.id, label = c.label, icon = 'coins', value = c.symbol, onSelect = function()
            inputHandlers['sl_admin_crypto'] = function(qty) TriggerServerEvent('sl_admin:giveCrypto', c.id, qty) end
            exports.sl_ui:openInput({ id = 'sl_admin_crypto', title = 'Donner ' .. c.label,
                label = 'Montant', placeholder = '1', confirmLabel = 'Donner', accent = Config.DebugAccent })
        end }
    end
    return { id = 'sl_admin_cryptogive', title = 'Donner crypto', subtitle = 'À moi', accent = Config.DebugAccent, items = items }
end

-- ── shops admin: assign LTD owners, top up till / stock ───────────────────────
function shopsAdminMenu()
    local shops = (GetResourceState('sl_shops') == 'started') and lib.callback.await('sl_shops:adminListShops', false) or {}
    local items = {}
    if not shops or #shops == 0 then items[1] = { id = 'none', label = 'sl_shops indisponible / aucune LTD', kind = 'info' } end
    for _, s in ipairs(shops or {}) do
        items[#items + 1] = { id = s.id, label = s.label, icon = 'shop',
            value = s.owner and ('proprio #' .. tostring(s.owner)) or 'libre',
            onSelect = function() openMenu(function() return shopActionMenu(s) end) end }
    end
    return { id = 'sl_admin_shops', title = 'Boutiques (LTD)', subtitle = 'Gestion', accent = Config.DebugAccent, items = items }
end

function shopActionMenu(shop)
    return { id = 'sl_admin_shopact', title = shop.label,
        subtitle = shop.owner and ('Proprio charId ' .. tostring(shop.owner)) or 'Sans propriétaire',
        accent = Config.DebugAccent, items = {
        { id = 'assign', label = 'Assigner un propriétaire', icon = 'user',
            onSelect = function() openMenu(function() return shopAssignPlayers(shop.id) end) end },
        { id = 'clear',  label = 'Retirer le propriétaire', icon = 'trash',
            onSelect = function() TriggerServerEvent('sl_admin:shopClearOwner', shop.id) end },
        { id = 'cash',   label = 'Ajouter à la caisse', icon = 'cash', onSelect = function()
            inputHandlers['sl_admin_shopcash'] = function(v) TriggerServerEvent('sl_admin:shopCash', shop.id, v) end
            exports.sl_ui:openInput({ id = 'sl_admin_shopcash', title = 'Caisse — ' .. shop.label,
                label = 'Montant', placeholder = '1000', confirmLabel = 'Ajouter', accent = Config.DebugAccent })
        end },
        { id = 'stock',  label = 'Ajouter du stock (tout)', icon = 'shop', onSelect = function()
            inputHandlers['sl_admin_shopstock'] = function(v) TriggerServerEvent('sl_admin:shopStock', shop.id, v) end
            exports.sl_ui:openInput({ id = 'sl_admin_shopstock', title = 'Stock — ' .. shop.label,
                label = 'Quantité par article', placeholder = '20', confirmLabel = 'Ajouter', accent = Config.DebugAccent })
        end },
    }}
end

function shopAssignPlayers(shopId)
    local players = lib.callback.await('sl_admin:getPlayers', false) or {}
    local items = {}
    if #players == 0 then items[1] = { id = 'none', label = 'Aucun joueur', kind = 'info' } end
    for _, p in ipairs(players) do
        items[#items + 1] = { id = 'p_' .. p.id, label = ('[%d] %s'):format(p.id, p.name), icon = 'user',
            onSelect = function() TriggerServerEvent('sl_admin:shopAssign', p.id, shopId) end }
    end
    return { id = 'sl_admin_shopassign', title = 'Assigner proprio', subtitle = shopId, accent = Config.DebugAccent, items = items }
end

-- ── dispatch from sl_ui (menu select / close, input submit / cancel) ──────────
AddEventHandler('sl_ui:nui', function(event, data)
    if not data then return end
    if event == 'menu:select' and data.menuId == currentMenuId then
        local fn = handlers[data.itemId]
        if fn then fn() end
    elseif event == 'menu:close' and data.menuId == currentMenuId then
        back()
    elseif event == 'input:submit' and inputHandlers[data.id] then
        local fn = inputHandlers[data.id]
        inputHandlers[data.id] = nil
        fn(data.value)
        reshow()  -- back to the menu that opened the input
    elseif event == 'input:cancel' and inputHandlers[data.id] then
        inputHandlers[data.id] = nil
        reshow()
    end
end)

-- ── open key (F10) + admin check ──────────────────────────────────────────────
CreateThread(function()
    while GlobalState.slCoreReady ~= true do Wait(250) end
    Wait(500)
    local ok = lib.callback.await('sl_admin:amIAdmin', false)
    isAdmin = ok and true or false
    Config.Log('info', isAdmin and 'accès admin ACCORDÉ (F10)' or 'pas admin — menu désactivé')
end)

RegisterCommand('sl_admin_open', function()
    if not isAdmin then notify('error', 'Accès refusé.'); return end
    if #stack > 0 then closeAdmin(); return end  -- toggle off if somehow still open
    openMenu(rootMenu)
end, false)
RegisterKeyMapping('sl_admin_open', 'Ouvrir le menu admin SimpleLife', 'keyboard', Config.OpenKey)

-- Never leave admin-applied invincibility behind if the resource stops (noclip handles its own).
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Noclip.godmode = false
    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(PlayerPedId(), false)
end)
