--[[
    server/main.lua — sl_shops authority.

    Two store kinds:
      • '247'  → NPC convenience store: clerk ped, server catalogue, infinite stock, money SINK.
      • 'ltd'  → player BUSINESS: no NPC. Sales happen via an employee-run register (POS):
                 an employee with the 'pos' permission bills the nearest customer, who confirms
                 and pays (cash/bank); items leave shop_stock, money goes to the till. The owner
                 (and permitted employees) manage stock/prices/employees/grades from a terminal,
                 and restock at the wholesale NPC paid from the company TILL.

    All prices/stock/permissions are resolved SERVER-SIDE; stock is decremented race-safely and
    every money move is atomic + fully rolled back on failure.
]]

local Core = exports.sl_core
local Inv  = exports.sl_inventory

-- ── base helpers ────────────────────────────────────────────────────────────────
local function getChar(src) return Core:getChar(src) end

local function shopRow(id)
    return Core:dbSingle('SELECT id, owner_charid, till FROM shops WHERE id = ?', { id })
end
local function ensureShopRow(id)
    Core:dbUpdate('INSERT IGNORE INTO shops (id) VALUES (?)', { id })
end

local specCache = {}
local function itemSpec(name)
    local v = specCache[name]
    if v ~= nil then return v or nil end
    local s = Inv:getItem(name)
    specCache[name] = s or false
    return s
end

local function nearCoords(src, coords, maxDist)
    if not coords then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= (maxDist or 6.0)
end

-- offers map: item -> { price, stock }. stock == -1 = infinite (NPC catalogue).
local function buildOffers(shop)
    local row = shopRow(shop.id)
    local owner = row and row.owner_charid or nil
    local offers = {}
    if owner then
        local rows = Core:dbQuery('SELECT item, qty, price FROM shop_stock WHERE shop_id = ?', { shop.id }) or {}
        for _, r in ipairs(rows) do offers[r.item] = { price = r.price, stock = r.qty } end
    else
        for _, e in ipairs(Config.Catalog(shop.catalog) or {}) do offers[e.item] = { price = e.price, stock = -1 } end
    end
    return offers, owner, (row and row.till or 0)
end

local function listOffers(shop)
    local offers, owner, till = buildOffers(shop)
    local out = {}
    for item, off in pairs(offers) do
        local sp = itemSpec(item) or { label = item, category = 'misc', weight = 0 }
        out[#out + 1] = { item = item, label = sp.label, category = sp.category, weight = sp.weight, price = off.price, stock = off.stock }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out, owner, till
end

-- LTD interaction points (caisse/stock/gestion) live in shop.points; a 247 uses its single ped.
local function pointCoords(shop, key)
    if shop.points then return shop.points[key] end
    return shop.ped and shop.ped.coords or nil
end

-- Items the player carries that the shop can stock (catalogue + items already stocked). Used by the
-- Stock point's "deposit" side.
local function depositList(src, shop)
    local seen, cand = {}, {}
    local function consider(item)
        if seen[item] then return end
        seen[item] = true
        local cnt = Inv:getGridItemCount(src, item) or 0  -- grid only (what removeItem can take)
        if cnt > 0 then
            local sp = itemSpec(item) or { label = item, category = 'misc' }
            cand[#cand + 1] = { item = item, label = sp.label, category = sp.category, carried = cnt }
        end
    end
    for _, e in ipairs(Config.Catalog(shop.catalog) or {}) do consider(e.item) end
    for _, r in ipairs(Core:dbQuery('SELECT item FROM shop_stock WHERE shop_id = ?', { shop.id }) or {}) do consider(r.item) end
    return cand
end

-- ── business: grades, employees, permissions, affiliation ───────────────────────
local ALL_PERMS = {}
for _, p in ipairs(Config.Permissions) do ALL_PERMS[p.key] = true end
local ALL_PERM_KEYS = {}
for _, p in ipairs(Config.Permissions) do ALL_PERM_KEYS[#ALL_PERM_KEYS + 1] = p.key end

local function sanitizePerms(list)
    local out = {}
    if type(list) == 'table' then
        local seen = {}
        for _, k in ipairs(list) do
            if ALL_PERMS[k] and not seen[k] then seen[k] = true; out[#out + 1] = k end
        end
    end
    return out
end

local function gradesList(shopId)
    local rows = Core:dbQuery('SELECT id, name, perms FROM shop_grades WHERE shop_id = ? ORDER BY id', { shopId }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local list = {}
        if r.perms then local ok, d = pcall(json.decode, r.perms); if ok and type(d) == 'table' then list = d end end
        out[#out + 1] = { id = r.id, name = r.name, perms = list }
    end
    return out
end

local function gradePerms(gradeId)
    if not gradeId then return {} end
    local g = Core:dbSingle('SELECT perms FROM shop_grades WHERE id = ?', { gradeId })
    if not g or not g.perms then return {} end
    local ok, list = pcall(json.decode, g.perms)
    if not ok or type(list) ~= 'table' then return {} end
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    return set
end

local function gradeBelongs(gradeId, shopId)
    if not gradeId then return false end
    return Core:dbScalar('SELECT COUNT(*) FROM shop_grades WHERE id = ? AND shop_id = ?', { gradeId, shopId }) == 1
end

-- privilege ceiling: a non-owner may only grant a grade whose permissions are a SUBSET of their
-- own — so the 'employees' permission can't be used to mint a higher role (or self-promote).
local function gradeWithinCeiling(aff, gradeId)
    if not aff then return false end
    if aff.perms == 'all' then return true end
    if not gradeId then return true end       -- no grade = no perms
    for k in pairs(gradePerms(gradeId)) do
        if not aff.perms[k] then return false end
    end
    return true
end

local function employeesOf(shopId)
    local rows = Core:dbQuery('SELECT charid, grade_id FROM shop_employees WHERE shop_id = ?', { shopId }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local nm = Core:dbSingle('SELECT firstname, lastname FROM characters WHERE id = ?', { r.charid })
        out[#out + 1] = {
            charid = r.charid, gradeId = r.grade_id,
            name = nm and (nm.firstname .. ' ' .. nm.lastname) or ('#' .. tostring(r.charid)),
        }
    end
    return out
end

-- A player is affiliated with at most ONE shop: as owner, else as employee.
local function affiliationOf(charId)
    if not charId then return nil end
    local own = Core:dbScalar('SELECT id FROM shops WHERE owner_charid = ? LIMIT 1', { charId })
    if own then return { shopId = own, role = 'owner' } end
    local row = Core:dbSingle('SELECT shop_id, grade_id FROM shop_employees WHERE charid = ? LIMIT 1', { charId })
    if row then return { shopId = row.shop_id, role = 'employee', gradeId = row.grade_id } end
    return nil
end

-- Resolve the caller's affiliation + a permission set ('all' for owner, else a {key=true} table).
local function myAff(src)
    local char = getChar(src); if not char then return nil end
    local aff = affiliationOf(char.charId)
    if not aff then return nil end
    aff.charId = char.charId
    aff.perms = (aff.role == 'owner') and 'all' or gradePerms(aff.gradeId)
    return aff
end
local function hasPerm(aff, key)
    if not aff then return false end
    if aff.perms == 'all' then return true end
    return aff.perms[key] == true
end
-- true if src has `key` permission AT shopId
local function permAt(src, shopId, key)
    local aff = myAff(src)
    if not aff or aff.shopId ~= shopId then return false, aff end
    return hasPerm(aff, key), aff
end
local function permKeys(aff)
    if not aff then return {} end
    if aff.perms == 'all' then return ALL_PERM_KEYS end
    local out = {}
    for k in pairs(aff.perms) do out[#out + 1] = k end
    return out
end

local function seedGrades(shopId)
    if (Core:dbScalar('SELECT COUNT(*) FROM shop_grades WHERE shop_id = ?', { shopId }) or 0) > 0 then return end
    Core:dbInsert('INSERT INTO shop_grades (shop_id, name, perms) VALUES (?, ?, ?)',
        { shopId, 'Gérant', json.encode({ 'pos', 'restock', 'prices', 'withdraw', 'employees', 'grades' }) })
    Core:dbInsert('INSERT INTO shop_grades (shop_id, name, perms) VALUES (?, ?, ?)',
        { shopId, 'Employé', json.encode({ 'pos' }) })
end

local function srcOfCharId(charId)
    local c = Core:getCharByCharId(charId)
    return c and c.source or nil
end

-- ── RPC methods ───────────────────────────────────────────────────────────────
local methods = {}

-- NPC 24/7 storefront (self-service from the clerk).
methods.open = function(src, p)
    local char = getChar(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    local shop = Config.Shop(p and p.shopId); if not shop then return { ok = false, reason = 'BAD_SHOP' } end
    if shop.type ~= '247' then return { ok = false, reason = 'CLOSED' } end
    if not nearCoords(src, shop.ped.coords, 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    return {
        ok = true, mode = 'buy',
        shop = { id = shop.id, label = shop.label, type = shop.type, accent = Config.Accent },
        offers = (listOffers(shop)), isOwner = false,
        balances = Core:economyBalance(src) or { cash = 0, bank = 0 },
    }
end

-- Buy from a 24/7 (NPC, money sink). Player LTDs sell via the POS, not here.
methods.buy = function(src, p)
    local char = getChar(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    local shop = Config.Shop(p and p.shopId); if not shop then return { ok = false, reason = 'BAD_SHOP' } end
    if shop.type ~= '247' then return { ok = false, reason = 'CLOSED' } end
    if not nearCoords(src, shop.ped.coords, 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local account = (p and p.account == 'bank') and 'bank' or 'cash'

    local offers = buildOffers(shop)
    local want = {}
    for _, line in ipairs(p and p.cart or {}) do
        local item = type(line) == 'table' and tostring(line.item) or nil
        local qty  = math.floor(tonumber(line and line.qty) or 0)
        if item and offers[item] and qty > 0 then want[item] = (want[item] or 0) + qty end
    end

    local total, grams, lines = 0, 0, {}
    for item, qty in pairs(want) do
        if qty > Config.Limits.maxQty then return { ok = false, reason = 'QTY' } end
        local sp = itemSpec(item); if not sp then return { ok = false, reason = 'BAD_ITEM' } end
        total = total + offers[item].price * qty
        grams = grams + (sp.weight or 0) * qty
        lines[#lines + 1] = { item = item, qty = qty }
    end
    if #lines == 0 then return { ok = false, reason = 'EMPTY' } end
    if total <= 0 or total > Config.Limits.maxTotal then return { ok = false, reason = 'AMOUNT' } end
    if not Inv:canCarryWeight(src, grams) then return { ok = false, reason = 'OVERWEIGHT' } end
    if (Core:economyBalance(src, account) or 0) < total then return { ok = false, reason = 'FUNDS' } end

    if not Core:economyTryDebit(src, account, total, 'shop_buy:' .. shop.id) then return { ok = false, reason = 'FUNDS' } end
    local given = {}
    for _, l in ipairs(lines) do
        if Inv:addItem(src, l.item, l.qty) then
            given[#given + 1] = l
        else
            for _, g in ipairs(given) do Inv:removeItem(src, g.item, g.qty) end
            if not Core:economyCredit(src, account, total, 'shop_refund:' .. shop.id) then
                Config.Log('error', ('refund FAILED src=%s shop=%s amount=%s'):format(tostring(src), shop.id, tostring(total)))
            end
            return { ok = false, reason = 'OVERWEIGHT' }
        end
    end
    return { ok = true, total = total, balances = Core:economyBalance(src) or { cash = 0, bank = 0 }, offers = (listOffers(shop)) }
end

-- ── CAISSE point: sell to customers (POS) + till (balance / withdraw) ────────────
methods['caisse:open'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'caisse'), 4.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = myAff(src); if not aff or aff.shopId ~= shop.id then return { ok = false, reason = 'NOT_STAFF' } end
    local offers, _, till = listOffers(shop)
    return {
        ok = true,
        shop = { id = shop.id, label = shop.label, type = shop.type, accent = Config.Accent },
        offers = offers, till = till, perms = permKeys(aff),
    }
end

-- ── GESTION point: prices + employees + grades/permissions ───────────────────────
methods['gestion:open'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 4.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = myAff(src); if not aff or aff.shopId ~= shop.id then return { ok = false, reason = 'NOT_STAFF' } end
    return {
        ok = true,
        shop = { id = shop.id, label = shop.label, type = shop.type, accent = Config.Accent },
        role = aff.role, perms = permKeys(aff), permList = Config.Permissions,
        offers = (listOffers(shop)), employees = employeesOf(shop.id), grades = gradesList(shop.id),
    }
end

methods['manage:setPrice'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'prices') then return { ok = false, reason = 'NO_PERM' } end
    local item  = tostring(p and p.item or '')
    local price = math.floor(tonumber(p and p.price) or 0)
    if price < 1 or price > Config.Limits.maxTotal then return { ok = false, reason = 'PRICE' } end
    local aff = Core:dbUpdate('UPDATE shop_stock SET price = ? WHERE shop_id = ? AND item = ?', { price, shop.id, item })
    if aff ~= 1 then return { ok = false, reason = 'NO_ITEM' } end
    return { ok = true, offers = (listOffers(shop)) }
end

methods['manage:withdraw'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'caisse'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'withdraw') then return { ok = false, reason = 'NO_PERM' } end
    local amount = math.floor(tonumber(p and p.amount) or 0)
    if amount < 1 then return { ok = false, reason = 'AMOUNT' } end
    local aff = Core:dbUpdate('UPDATE shops SET till = till - ? WHERE id = ? AND till >= ?', { amount, shop.id, amount })
    if aff ~= 1 then return { ok = false, reason = 'TILL' } end
    if not Core:economyCredit(src, 'bank', amount, 'shop_withdraw:' .. shop.id) then
        Core:dbUpdate('UPDATE shops SET till = till + ? WHERE id = ?', { amount, shop.id })
        return { ok = false, reason = 'TILL' }
    end
    return { ok = true, till = (shopRow(shop.id) or {}).till or 0, balances = Core:economyBalance(src) or { cash = 0, bank = 0 } }
end

-- ── grades (perm 'grades') ──────────────────────────────────────────────────────
methods['grades:create'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'grades') then return { ok = false, reason = 'NO_PERM' } end
    local name = tostring(p and p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 48)
    if name == '' then return { ok = false, reason = 'NAME' } end
    if (Core:dbScalar('SELECT COUNT(*) FROM shop_grades WHERE shop_id = ?', { shop.id }) or 0) >= 30 then return { ok = false, reason = 'LIMIT' } end
    Core:dbInsert('INSERT INTO shop_grades (shop_id, name, perms) VALUES (?, ?, ?)', { shop.id, name, json.encode(sanitizePerms(p and p.perms)) })
    return { ok = true, grades = gradesList(shop.id) }
end

methods['grades:update'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'grades') then return { ok = false, reason = 'NO_PERM' } end
    local gid = tonumber(p and p.gradeId); if not gid or not gradeBelongs(gid, shop.id) then return { ok = false, reason = 'NO_GRADE' } end
    local name = tostring(p and p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 48)
    if name == '' then return { ok = false, reason = 'NAME' } end
    Core:dbUpdate('UPDATE shop_grades SET name = ?, perms = ? WHERE id = ? AND shop_id = ?',
        { name, json.encode(sanitizePerms(p and p.perms)), gid, shop.id })
    return { ok = true, grades = gradesList(shop.id) }
end

methods['grades:delete'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'grades') then return { ok = false, reason = 'NO_PERM' } end
    local gid = tonumber(p and p.gradeId); if not gid or not gradeBelongs(gid, shop.id) then return { ok = false, reason = 'NO_GRADE' } end
    -- employees on this grade fall back to no grade (no permissions) until reassigned
    local affected = Core:dbQuery('SELECT charid FROM shop_employees WHERE shop_id = ? AND grade_id = ?', { shop.id, gid }) or {}
    Core:dbUpdate('UPDATE shop_employees SET grade_id = NULL WHERE shop_id = ? AND grade_id = ?', { shop.id, gid })
    Core:dbUpdate('DELETE FROM shop_grades WHERE id = ? AND shop_id = ?', { gid, shop.id })
    for _, r in ipairs(affected) do local s = srcOfCharId(r.charid); if s then TriggerClientEvent('sl_shops:refreshOwner', s) end end
    return { ok = true, grades = gradesList(shop.id), employees = employeesOf(shop.id) }
end

-- ── employees (perm 'employees') ────────────────────────────────────────────────
methods['employees:recruit'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local okp, me = permAt(src, shop.id, 'employees'); if not okp then return { ok = false, reason = 'NO_PERM' } end
    -- nearest player to the recruiter (within 3m)
    local rc, target, best = GetEntityCoords(GetPlayerPed(src)), nil, 3.0
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if pid ~= src then
            local d = #(GetEntityCoords(GetPlayerPed(pid)) - rc)
            if d < best then best = d; target = pid end
        end
    end
    if not target then return { ok = false, reason = 'NO_TARGET' } end
    local tchar = getChar(target); if not tchar then return { ok = false, reason = 'NO_TARGET' } end
    if affiliationOf(tchar.charId) then return { ok = false, reason = 'ALREADY' } end
    local gid = tonumber(p and p.gradeId)
    if gid and not gradeBelongs(gid, shop.id) then gid = nil end
    if not gradeWithinCeiling(me, gid) then return { ok = false, reason = 'NO_PERM' } end
    Core:dbUpdate('INSERT INTO shop_employees (shop_id, charid, grade_id) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE grade_id = VALUES(grade_id)',
        { shop.id, tchar.charId, gid })
    TriggerClientEvent('sl_shops:refreshOwner', target)
    TriggerClientEvent('sl_shops:notify', target, 'success', 'Vous avez été recruté chez ' .. shop.label .. '.')
    return { ok = true, employees = employeesOf(shop.id), recruited = (tchar.firstname .. ' ' .. tchar.lastname) }
end

methods['employees:setGrade'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local okp, me = permAt(src, shop.id, 'employees'); if not okp then return { ok = false, reason = 'NO_PERM' } end
    local charid = tonumber(p and p.charid); if not charid then return { ok = false, reason = 'NO_TARGET' } end
    if me and me.charId == charid then return { ok = false, reason = 'NO_TARGET' } end          -- no self-promotion
    local gid = tonumber(p and p.gradeId)
    if gid and not gradeBelongs(gid, shop.id) then return { ok = false, reason = 'NO_GRADE' } end
    if not gradeWithinCeiling(me, gid) then return { ok = false, reason = 'NO_PERM' } end          -- privilege ceiling
    local upd = Core:dbUpdate('UPDATE shop_employees SET grade_id = ? WHERE shop_id = ? AND charid = ?', { gid, shop.id, charid })
    if upd ~= 1 then return { ok = false, reason = 'NO_TARGET' } end
    local s = srcOfCharId(charid); if s then TriggerClientEvent('sl_shops:refreshOwner', s) end
    return { ok = true, employees = employeesOf(shop.id) }
end

methods['employees:fire'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'gestion'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'employees') then return { ok = false, reason = 'NO_PERM' } end
    local charid = tonumber(p and p.charid); if not charid then return { ok = false, reason = 'NO_TARGET' } end
    Core:dbUpdate('DELETE FROM shop_employees WHERE shop_id = ? AND charid = ?', { shop.id, charid })
    local s = srcOfCharId(charid)
    if s then TriggerClientEvent('sl_shops:refreshOwner', s); TriggerClientEvent('sl_shops:notify', s, 'info', 'Vous avez été licencié de ' .. shop.label .. '.') end
    return { ok = true, employees = employeesOf(shop.id) }
end

-- ── POS: an employee bills the nearest customer, who confirms + pays ─────────────
local pendingBills = {}
local billSeq = 0

-- Build + dispatch a bill from `src` (employee) to the nearest customer for `shop`. Shared by the
-- in-shop register (pos:bill) and the phone app (phone:bill). The caller checks the 'pos' perm.
local function issueBill(src, shop, cart)
    if not (shopRow(shop.id) or {}).owner_charid then return { ok = false, reason = 'CLOSED' } end
    local offers = buildOffers(shop)
    local want = {}
    for _, line in ipairs(cart or {}) do
        local item = type(line) == 'table' and tostring(line.item) or nil
        local qty  = math.floor(tonumber(line and line.qty) or 0)
        if item and offers[item] and qty > 0 then want[item] = (want[item] or 0) + qty end
    end
    local total, lines, items = 0, {}, {}
    for item, qty in pairs(want) do
        if qty > Config.Limits.maxQty then return { ok = false, reason = 'QTY' } end
        local off = offers[item]
        if off.stock ~= -1 and qty > off.stock then return { ok = false, reason = 'STOCK', item = item } end
        local sp = itemSpec(item) or { label = item }
        total = total + off.price * qty
        lines[#lines + 1] = { item = item, qty = qty }
        items[#items + 1] = { label = sp.label, qty = qty, price = off.price }
    end
    if #lines == 0 then return { ok = false, reason = 'EMPTY' } end
    if total <= 0 or total > Config.Limits.maxTotal then return { ok = false, reason = 'AMOUNT' } end

    -- nearest OTHER player to the employee = the customer (within 4m)
    local ec, customer, best = GetEntityCoords(GetPlayerPed(src)), nil, 4.0
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if pid ~= src then
            local d = #(GetEntityCoords(GetPlayerPed(pid)) - ec)
            if d < best then best = d; customer = pid end
        end
    end
    if not customer then return { ok = false, reason = 'NO_CUSTOMER' } end

    -- one live bill per (shop, customer): supersede any earlier unpaid bill to this customer
    for id, b in pairs(pendingBills) do
        if b.shop == shop.id and b.customer == customer then
            if b.employee and b.employee ~= src then TriggerClientEvent('sl_shops:posResult', b.employee, { ok = false, reason = 'SUPERSEDED' }) end
            pendingBills[id] = nil
        end
    end

    billSeq = billSeq + 1
    local billId = billSeq
    pendingBills[billId] = { shop = shop.id, employee = src, customer = customer, lines = lines, total = total, at = GetGameTimer() }
    TriggerClientEvent('sl_shops:bill', customer, { billId = billId, shopLabel = shop.label, total = total, items = items })
    return { ok = true, customer = GetPlayerName(customer) or 'client', total = total }
end

-- ── STOCK point: deposit items into / withdraw items from the company stock ───────
methods['stock:open'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'stock'), 4.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = myAff(src); if not aff or aff.shopId ~= shop.id then return { ok = false, reason = 'NOT_STAFF' } end
    return {
        ok = true,
        shop = { id = shop.id, label = shop.label, type = shop.type, accent = Config.Accent },
        offers = (listOffers(shop)), deposit = depositList(src, shop), canManage = hasPerm(aff, 'restock'),
    }
end

methods['stock:deposit'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'stock'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'restock') then return { ok = false, reason = 'NO_PERM' } end
    if not (shopRow(shop.id) or {}).owner_charid then return { ok = false, reason = 'CLOSED' } end
    local item = tostring(p and p.item or '')
    local qty  = math.floor(tonumber(p and p.qty) or 0)
    if qty <= 0 or qty > Config.Limits.maxQty then return { ok = false, reason = 'QTY' } end
    if not itemSpec(item) then return { ok = false, reason = 'BAD_ITEM' } end
    if (Inv:getGridItemCount(src, item) or 0) < qty then return { ok = false, reason = 'NOT_ENOUGH' } end
    if not Inv:removeItem(src, item, qty) then return { ok = false, reason = 'NOT_ENOUGH' } end
    local dprice = 1
    for _, e in ipairs(Config.Catalog(shop.catalog) or {}) do if e.item == item then dprice = e.price; break end end
    Core:dbUpdate('INSERT INTO shop_stock (shop_id, item, qty, price) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)',
        { shop.id, item, qty, dprice })
    return { ok = true, offers = (listOffers(shop)), deposit = depositList(src, shop) }
end

methods['stock:withdraw'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'stock'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'restock') then return { ok = false, reason = 'NO_PERM' } end
    local item = tostring(p and p.item or '')
    local qty  = math.floor(tonumber(p and p.qty) or 0)
    if qty <= 0 or qty > Config.Limits.maxQty then return { ok = false, reason = 'QTY' } end
    local sp = itemSpec(item); if not sp then return { ok = false, reason = 'BAD_ITEM' } end
    if not Inv:canCarryWeight(src, (sp.weight or 0) * qty) then return { ok = false, reason = 'OVERWEIGHT' } end
    local a = Core:dbUpdate('UPDATE shop_stock SET qty = qty - ? WHERE shop_id = ? AND item = ? AND qty >= ?', { qty, shop.id, item, qty })
    if a ~= 1 then return { ok = false, reason = 'STOCK' } end
    if not Inv:addItem(src, item, qty) then
        Core:dbUpdate('UPDATE shop_stock SET qty = qty + ? WHERE shop_id = ? AND item = ?', { qty, shop.id, item })  -- rollback
        return { ok = false, reason = 'OVERWEIGHT' }
    end
    return { ok = true, offers = (listOffers(shop)), deposit = depositList(src, shop) }
end

methods['pos:bill'] = function(src, p)
    local shop = Config.Shop(p and p.shopId); if not shop or shop.type ~= 'ltd' then return { ok = false, reason = 'BAD_SHOP' } end
    if not nearCoords(src, pointCoords(shop, 'caisse'), 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, shop.id, 'pos') then return { ok = false, reason = 'NO_PERM' } end
    return issueBill(src, shop, p and p.cart)
end

-- ── phone app (remote): an affiliated employee views the stock + bills a customer ─
methods['phone:company'] = function(src, _)
    local aff = myAff(src); if not aff then return { ok = false, reason = 'NO_SHOP' } end
    local shop = Config.Shop(aff.shopId); if not shop then return { ok = false, reason = 'NO_SHOP' } end
    local offers, _, till = listOffers(shop)
    return {
        ok = true, shop = { id = shop.id, label = shop.label }, role = aff.role,
        perms = permKeys(aff), offers = offers, till = till, canBill = hasPerm(aff, 'pos'),
    }
end

methods['phone:bill'] = function(src, p)
    local aff = myAff(src); if not aff then return { ok = false, reason = 'NO_SHOP' } end
    if not hasPerm(aff, 'pos') then return { ok = false, reason = 'NO_PERM' } end
    local shop = Config.Shop(aff.shopId); if not shop then return { ok = false, reason = 'NO_SHOP' } end
    return issueBill(src, shop, p and p.cart)
end

methods['bill:decline'] = function(src, p)
    local bill = pendingBills[tonumber(p and p.billId)]
    if bill and bill.customer == src then
        pendingBills[tonumber(p.billId)] = nil
        if bill.employee then TriggerClientEvent('sl_shops:posResult', bill.employee, { ok = false, reason = 'DECLINED' }) end
    end
    return { ok = true }
end

methods['bill:pay'] = function(src, p)
    local billId = tonumber(p and p.billId)
    local bill = pendingBills[billId]
    if not bill or bill.customer ~= src then return { ok = false, reason = 'NO_BILL' } end
    if GetGameTimer() - bill.at > Config.Limits.billTtlMs then
        if bill.employee then TriggerClientEvent('sl_shops:posResult', bill.employee, { ok = false, reason = 'EXPIRED' }) end
        pendingBills[billId] = nil
        return { ok = false, reason = 'EXPIRED' }
    end
    local shop = Config.Shop(bill.shop); if not shop then pendingBills[billId] = nil; return { ok = false, reason = 'BAD_SHOP' } end
    local account = (p and p.account == 'bank') and 'bank' or 'cash'

    -- re-resolve price/stock NOW (server truth)
    local offers = buildOffers(shop)
    local total, grams, lines = 0, 0, {}
    for _, l in ipairs(bill.lines) do
        local off = offers[l.item]
        if not off then pendingBills[billId] = nil; return { ok = false, reason = 'STOCK', item = l.item } end
        if off.stock ~= -1 and l.qty > off.stock then pendingBills[billId] = nil; return { ok = false, reason = 'STOCK', item = l.item } end
        local sp = itemSpec(l.item); if not sp then pendingBills[billId] = nil; return { ok = false, reason = 'BAD_ITEM' } end
        total = total + off.price * l.qty
        grams = grams + (sp.weight or 0) * l.qty
        lines[#lines + 1] = { item = l.item, qty = l.qty }
    end
    if total <= 0 or total > Config.Limits.maxTotal then pendingBills[billId] = nil; return { ok = false, reason = 'AMOUNT' } end
    if not Inv:canCarryWeight(src, grams) then return { ok = false, reason = 'OVERWEIGHT' } end
    if (Core:economyBalance(src, account) or 0) < total then return { ok = false, reason = 'FUNDS' } end

    local decremented = {}
    local function restoreStock()
        for _, d in ipairs(decremented) do Core:dbUpdate('UPDATE shop_stock SET qty = qty + ? WHERE shop_id = ? AND item = ?', { d.qty, shop.id, d.item }) end
    end
    for _, l in ipairs(lines) do
        local a = Core:dbUpdate('UPDATE shop_stock SET qty = qty - ? WHERE shop_id = ? AND item = ? AND qty >= ?', { l.qty, shop.id, l.item, l.qty })
        if a ~= 1 then restoreStock(); pendingBills[billId] = nil; return { ok = false, reason = 'STOCK', item = l.item } end
        decremented[#decremented + 1] = l
    end
    if not Core:economyTryDebit(src, account, total, 'shop_pos:' .. shop.id) then restoreStock(); return { ok = false, reason = 'FUNDS' } end

    local given = {}
    for _, l in ipairs(lines) do
        if Inv:addItem(src, l.item, l.qty) then
            given[#given + 1] = l
        else
            for _, g in ipairs(given) do Inv:removeItem(src, g.item, g.qty) end
            if not Core:economyCredit(src, account, total, 'shop_pos_refund:' .. shop.id) then
                Config.Log('error', ('POS refund FAILED src=%s shop=%s amount=%s'):format(tostring(src), shop.id, tostring(total)))
            end
            restoreStock()
            return { ok = false, reason = 'OVERWEIGHT' }
        end
    end
    Core:dbUpdate('UPDATE shops SET till = till + ? WHERE id = ?', { total, shop.id })
    pendingBills[billId] = nil
    if bill.employee then TriggerClientEvent('sl_shops:posResult', bill.employee, { ok = true, total = total }) end
    return { ok = true, total = total, balances = Core:economyBalance(src) or { cash = 0, bank = 0 } }
end

-- ── wholesale (grossiste): restock the company stock, paid from the TILL ─────────
local function wholesaleState(aff)
    local shop = Config.Shop(aff.shopId)
    local offers = {}
    for _, w in ipairs(Config.Wholesale) do
        local sp = itemSpec(w.item) or { label = w.item, category = 'misc' }
        offers[#offers + 1] = { item = w.item, label = sp.label, category = sp.category, price = w.price, defaultPrice = w.defaultPrice }
    end
    return { shopId = aff.shopId, shopLabel = (shop and shop.label) or aff.shopId, offers = offers, till = (shopRow(aff.shopId) or {}).till or 0 }
end

methods['wholesale:open'] = function(src, _)
    if not nearCoords(src, Config.Wholesaler.ped.coords, 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = myAff(src); if not aff then return { ok = false, reason = 'NO_SHOP' } end
    if not hasPerm(aff, 'restock') then return { ok = false, reason = 'NO_PERM' } end
    return { ok = true, shop = wholesaleState(aff) }
end

methods['wholesale:buy'] = function(src, p)
    if not nearCoords(src, Config.Wholesaler.ped.coords, 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = myAff(src); if not aff then return { ok = false, reason = 'NO_SHOP' } end
    if not hasPerm(aff, 'restock') then return { ok = false, reason = 'NO_PERM' } end
    local shopId = aff.shopId

    local wmap = {}
    for _, w in ipairs(Config.Wholesale) do wmap[w.item] = w end
    local want = {}
    for _, line in ipairs(p and p.cart or {}) do
        local item = type(line) == 'table' and tostring(line.item) or nil
        local qty  = math.floor(tonumber(line and line.qty) or 0)
        if item and wmap[item] and qty > 0 then want[item] = (want[item] or 0) + qty end
    end
    local total, lines = 0, {}
    for item, qty in pairs(want) do
        if qty > Config.Limits.maxQty then return { ok = false, reason = 'QTY' } end
        total = total + wmap[item].price * qty
        lines[#lines + 1] = { item = item, qty = qty, dprice = wmap[item].defaultPrice }
    end
    if #lines == 0 then return { ok = false, reason = 'EMPTY' } end
    if total <= 0 or total > Config.Limits.maxTotal then return { ok = false, reason = 'AMOUNT' } end

    -- pay from the company till (race-safe conditional debit)
    local aff2 = Core:dbUpdate('UPDATE shops SET till = till - ? WHERE id = ? AND till >= ?', { total, shopId, total })
    if aff2 ~= 1 then return { ok = false, reason = 'TILL' } end
    for _, l in ipairs(lines) do
        Core:dbUpdate(
            'INSERT INTO shop_stock (shop_id, item, qty, price) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)',
            { shopId, l.item, l.qty, l.dprice })
    end
    return { ok = true, total = total, shop = wholesaleState(aff) }
end

-- ── callback bridge ─────────────────────────────────────────────────────────────
local RATE = {
    ['buy'] = true, ['wholesale:buy'] = true, ['manage:setPrice'] = true, ['manage:withdraw'] = true,
    ['pos:bill'] = true, ['phone:bill'] = true, ['bill:pay'] = true, ['grades:create'] = true, ['grades:update'] = true,
    ['grades:delete'] = true, ['employees:recruit'] = true, ['employees:setGrade'] = true, ['employees:fire'] = true,
    ['stock:deposit'] = true, ['stock:withdraw'] = true,
}
local LOCK = { ['buy'] = true, ['wholesale:buy'] = true, ['bill:pay'] = true, ['stock:withdraw'] = true }  -- single-flight per player
local lastCall, inFlight = {}, {}

lib.callback.register('sl_shops:rpc', function(src, payload)
    local method = payload and payload.method
    local fn = method and methods[method]
    if not fn then return { ok = false, reason = 'BAD_METHOD' } end
    if RATE[method] then
        local key, now = src .. ':' .. method, GetGameTimer()
        if lastCall[key] and (now - lastCall[key]) < Config.Limits.rpcIntervalMs then return { ok = false, reason = 'RATE' } end
        lastCall[key] = now
    end
    if LOCK[method] then
        if inFlight[src] then return { ok = false, reason = 'RATE' } end
        inFlight[src] = true
        local ok, res = pcall(fn, src, payload.params or {})
        inFlight[src] = nil
        if not ok then Config.Log('error', ('rpc %s error: %s'):format(method, tostring(res))); return { ok = false, reason = 'ERROR' } end
        return res
    end
    return fn(src, payload.params or {})
end)

-- the shop a player is affiliated with (owner or employee), for client-side target gating
lib.callback.register('sl_shops:myShop', function(src)
    local aff = myAff(src)
    return aff and aff.shopId or nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    for k in pairs(lastCall) do if k:sub(1, #tostring(src) + 1) == (src .. ':') then lastCall[k] = nil end end
    inFlight[src] = nil
    for id, b in pairs(pendingBills) do if b.customer == src or b.employee == src then pendingBills[id] = nil end end
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        for id, b in pairs(pendingBills) do
            if now - b.at > Config.Limits.billTtlMs then
                if b.employee then TriggerClientEvent('sl_shops:posResult', b.employee, { ok = false, reason = 'EXPIRED' }) end
                if b.customer then TriggerClientEvent('sl_shops:billClosed', b.customer) end
                pendingBills[id] = nil
            end
        end
    end
end)

-- ── admin exports (called by sl_admin F10; admin-gated there) ────────────────────
local function ownableShops()
    local out = {}
    for _, s in ipairs(Config.Shops) do
        if s.type == 'ltd' then
            local row = shopRow(s.id)
            out[#out + 1] = { id = s.id, label = s.label, owner = (row and row.owner_charid) or nil }
        end
    end
    return out
end
exports('getOwnableShops', function() return ownableShops() end)

lib.callback.register('sl_shops:adminListShops', function(src)
    if not IsPlayerAceAllowed(src, 'sl.admin') then return {} end
    return ownableShops()
end)

exports('setShopOwner', function(targetSrc, shopId)
    local shop = Config.Shop(shopId); if not shop or shop.type ~= 'ltd' then return false end
    local char = getChar(targetSrc); if not char then return false end
    ensureShopRow(shopId)
    seedGrades(shopId)
    -- one affiliation per player: release any shop they owned, and remove them as an employee
    Core:dbUpdate('UPDATE shops SET owner_charid = NULL WHERE owner_charid = ?', { char.charId })
    Core:dbUpdate('DELETE FROM shop_employees WHERE charid = ?', { char.charId })
    Core:dbUpdate('UPDATE shops SET owner_charid = ? WHERE id = ?', { char.charId, shopId })
    -- verify the write actually landed (idempotent-safe: re-read instead of trusting affectedRows).
    -- If the `shops` table doesn't exist (sl_core migrations not applied), this stays nil → honest fail.
    local check = Core:dbScalar('SELECT owner_charid FROM shops WHERE id = ?', { shopId })
    if tonumber(check) ~= tonumber(char.charId) then
        Config.Log('error', ('assignation NON enregistrée (%s) — la table `shops` existe-t-elle ? redémarre sl_core (migrations 010/011).'):format(shopId))
        return false
    end
    TriggerClientEvent('sl_shops:refreshOwner', targetSrc)
    Config.Log('info', ('shop %s -> charId %s (src %s)'):format(shopId, tostring(char.charId), tostring(targetSrc)))
    return true
end)

exports('clearShopOwner', function(shopId)
    if not Config.Shop(shopId) then return false end
    local row = shopRow(shopId)
    Core:dbUpdate('UPDATE shops SET owner_charid = NULL WHERE id = ?', { shopId })
    if row and row.owner_charid then local s = srcOfCharId(row.owner_charid); if s then TriggerClientEvent('sl_shops:refreshOwner', s) end end
    return true
end)

exports('addShopCash', function(shopId, amount)
    if not Config.Shop(shopId) then return false end
    amount = math.floor(tonumber(amount) or 0)
    ensureShopRow(shopId)
    Core:dbUpdate('UPDATE shops SET till = GREATEST(0, till + ?) WHERE id = ?', { amount, shopId })
    return true
end)

exports('addShopStock', function(shopId, qty)
    if not Config.Shop(shopId) then return false end
    qty = math.floor(tonumber(qty) or 0); if qty <= 0 then return false end
    ensureShopRow(shopId)
    for _, w in ipairs(Config.Wholesale) do
        Core:dbUpdate(
            'INSERT INTO shop_stock (shop_id, item, qty, price) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)',
            { shopId, w.item, qty, w.defaultPrice })
    end
    return true
end)

-- Startup sanity: the shops tables come from sl_core migrations 010/011. If you only restarted
-- sl_shops, they won't exist yet → every affiliation check fails ("pas employé"). This logs which.
CreateThread(function()
    Wait(3000)
    local ok, n = pcall(function() return Core:dbScalar('SELECT COUNT(*) FROM shops') end)
    if not ok or n == nil then
        Config.Log('error', 'Table `shops` INTROUVABLE — redémarre sl_core pour appliquer les migrations 010/011.')
    else
        Config.Log('info', ('base prête — %d ligne(s) dans `shops`'):format(tonumber(n) or 0))
    end
end)

exports('getPlayerShops', function(targetSrc)
    local char = getChar(targetSrc); if not char then return {} end
    local rows = Core:dbQuery('SELECT id, till FROM shops WHERE owner_charid = ?', { char.charId }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local s = Config.Shop(r.id)
        out[#out + 1] = { id = r.id, label = (s and s.label) or r.id, cash = r.till or 0 }
    end
    return out
end)
