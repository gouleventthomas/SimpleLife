--[[
    server/dealership.lua — player-run dealerships (modeled on sl_shops LTD).

    Two interaction points: VENTE (employee sells a car to the nearest customer via a bill the
    customer confirms + pays; the car is created + delivered + key handed over; the seller earns a
    grade commission, the rest goes to the till) and GESTION (stock/import orders, prices within a
    margin band, employees, custom grades with commission + salary, till withdraw, showroom expo,
    contact-form leads). Restock is the import/convoy loop (server/convoy.lua).
]]

SLV.methods = SLV.methods or {}
local M = SLV.methods

-- ── rows / stock ──────────────────────────────────────────────────────────────────
local function dealRow(id) return SLV.single('SELECT id, owner_charid, till FROM dealerships WHERE id = ?', { id }) end
function SLV.ensureDealRow(id) SLV.update('INSERT IGNORE INTO dealerships (id) VALUES (?)', { id }) end
function SLV.dealTill(id) return (dealRow(id) or {}).till or 0 end

-- retail price for a model at a dealer (stored owner price, clamped to the margin band, else default)
local function retailPrice(dealerId, model)
    local spec = Config.CatalogModel(model); if not spec then return 0 end
    local r = SLV.single('SELECT price FROM dealership_stock WHERE dealer_id = ? AND model = ?', { dealerId, model })
    local floorP = math.floor(spec.price * (1 + Config.Limits.marginMinPct / 100))
    local ceilP  = math.floor(spec.price * (1 + Config.Limits.marginMaxPct / 100))
    local p = r and tonumber(r.price) or 0
    if p <= 0 then return floorP end
    return math.max(floorP, math.min(ceilP, p))
end

-- full sellable list for a dealer (its categories) with stock qty/price/display
local function listStock(dealer)
    local stockRows = {}
    for _, r in ipairs(SLV.query('SELECT model, qty, price, display FROM dealership_stock WHERE dealer_id = ?', { dealer.id }) or {}) do
        stockRows[r.model] = r
    end
    local out = {}
    for _, e in ipairs(Config.CatalogFor(dealer.categories)) do
        local sr = stockRows[e.model]
        out[#out + 1] = {
            model = e.model, label = e.label, brand = e.brand, category = e.category,
            seats = e.seats, trunk = e.trunk, stats = e.stats,
            import = e.price, price = retailPrice(dealer.id, e.model),
            qty = sr and sr.qty or 0, display = sr and sr.display == 1 or false,
        }
    end
    table.sort(out, function(a, b) return a.price < b.price end)
    return out
end
SLV.dealerStock = listStock

-- ── grades / employees / affiliation (one dealership affiliation per character) ─────
local ALLP = {}
for _, k in ipairs(Config.Permissions) do ALLP[k] = true end

local function sanitizePerms(list)
    local out, seen = {}, {}
    if type(list) == 'table' then
        for _, k in ipairs(list) do if ALLP[k] and not seen[k] then seen[k] = true; out[#out + 1] = k end end
    end
    return out
end

local function gradesList(dealerId)
    local out = {}
    for _, r in ipairs(SLV.query('SELECT id, name, perms, commission, salary FROM dealership_grades WHERE dealer_id = ? ORDER BY id', { dealerId }) or {}) do
        local list = SLV.decode(r.perms) or {}
        out[#out + 1] = { id = r.id, name = r.name, perms = list, commission = r.commission or 0, salary = r.salary or 0 }
    end
    return out
end

local function gradeRow(gid) return gid and SLV.single('SELECT * FROM dealership_grades WHERE id = ?', { gid }) end
local function gradePerms(gid)
    local g = gradeRow(gid); if not g or not g.perms then return {} end
    local set, list = {}, SLV.decode(g.perms) or {}
    for _, k in ipairs(list) do set[k] = true end
    return set
end
local function gradeBelongs(gid, dealerId)
    return gid and SLV.scalar('SELECT COUNT(*) FROM dealership_grades WHERE id = ? AND dealer_id = ?', { gid, dealerId }) == 1
end

local function affiliationOf(charId)
    if not charId then return nil end
    local own = SLV.scalar('SELECT id FROM dealerships WHERE owner_charid = ? LIMIT 1', { charId })
    if own then return { dealerId = own, role = 'owner' } end
    local row = SLV.single('SELECT dealer_id, grade_id FROM dealership_employees WHERE charid = ? LIMIT 1', { charId })
    if row then return { dealerId = row.dealer_id, role = 'employee', gradeId = row.grade_id } end
    return nil
end
SLV.dealAffiliationOf = affiliationOf

local function myAff(src)
    local char = SLV.char(src); if not char then return nil end
    local aff = affiliationOf(char.charId); if not aff then return nil end
    aff.charId = char.charId
    aff.perms = (aff.role == 'owner') and 'all' or gradePerms(aff.gradeId)
    return aff
end
local function hasPerm(aff, key)
    if not aff then return false end
    if aff.perms == 'all' then return true end
    return aff.perms[key] == true
end
local function permAt(src, dealerId, key)
    local aff = myAff(src)
    if not aff or aff.dealerId ~= dealerId then return false, aff end
    return hasPerm(aff, key), aff
end
local function permKeys(aff)
    if not aff then return {} end
    if aff.perms == 'all' then return Config.Permissions end
    local out = {}; for k in pairs(aff.perms) do out[#out + 1] = k end; return out
end
local function gradeWithinCeiling(aff, gid)
    if not aff then return false end
    if aff.perms == 'all' then return true end
    if not gid then return true end
    for k in pairs(gradePerms(gid)) do if not aff.perms[k] then return false end end
    return true
end
local function gradeCommission(gid)
    local g = gradeRow(gid)
    return g and tonumber(g.commission) or 0
end

local function employeesOf(dealerId)
    local out = {}
    for _, r in ipairs(SLV.query('SELECT charid, grade_id FROM dealership_employees WHERE dealer_id = ?', { dealerId }) or {}) do
        out[#out + 1] = { charid = r.charid, gradeId = r.grade_id, name = SLV.charName(r.charid) or ('#' .. r.charid) }
    end
    return out
end

function SLV.seedDealerGrades(dealerId)
    if (SLV.scalar('SELECT COUNT(*) FROM dealership_grades WHERE dealer_id = ?', { dealerId }) or 0) > 0 then return end
    SLV.insert('INSERT INTO dealership_grades (dealer_id, name, perms, commission, salary) VALUES (?,?,?,?,?)',
        { dealerId, 'Directeur', SLV.encode({ 'vente', 'import', 'prix', 'caisse', 'employes', 'grades', 'expo', 'leads' }), 10, 0 })
    SLV.insert('INSERT INTO dealership_grades (dealer_id, name, perms, commission, salary) VALUES (?,?,?,?,?)',
        { dealerId, 'Vendeur', SLV.encode({ 'vente', 'import', 'leads' }), Config.Limits.commissionDefault, 500 })
end

local function near(src, dealer, key, d) return SLV.near(src, dealer.points[key], d or 4.0) end

-- ── leads (used in gestion view; full API in server/leads.lua) ──────────────────────
function SLV.leadsFor(dealerId)
    local out = {}
    for _, r in ipairs(SLV.query([[SELECT id, client_charid, client_name, client_number, subject, message, status, created
                                   FROM company_leads WHERE company_id = ? AND status = 'open' ORDER BY id DESC LIMIT 50]], { dealerId }) or {}) do
        out[#out + 1] = { id = r.id, name = r.client_name, number = r.client_number, subject = r.subject, message = r.message, created = tostring(r.created) }
    end
    return out
end

-- ── VENTE point ─────────────────────────────────────────────────────────────────────
M['vente:open'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'vente', 4.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = myAff(src); if not aff or aff.dealerId ~= dealer.id then return { ok = false, reason = 'NOT_STAFF' } end
    if not hasPerm(aff, 'vente') then return { ok = false, reason = 'NO_PERM' } end
    return {
        ok = true,
        dealer = { id = dealer.id, label = dealer.label, accent = Config.Accent, categories = dealer.categories,
                   catNames = Config.Categories },
        stock = listStock(dealer), perms = permKeys(aff),
    }
end

local pendingBills = {}
local billSeq = 0

-- An employee bills the nearest customer for ONE vehicle model.
M['vente:bill'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'vente', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local okp = permAt(src, dealer.id, 'vente'); if not okp then return { ok = false, reason = 'NO_PERM' } end
    if not (dealRow(dealer.id) or {}).owner_charid then return { ok = false, reason = 'CLOSED' } end
    local model = tostring(p and p.model or '')
    local spec = Config.CatalogModel(model); if not spec then return { ok = false, reason = 'BAD_MODEL' } end
    local sr = SLV.single('SELECT qty FROM dealership_stock WHERE dealer_id = ? AND model = ?', { dealer.id, model })
    if not sr or (sr.qty or 0) < 1 then return { ok = false, reason = 'STOCK' } end
    local price = retailPrice(dealer.id, model)

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

    for id, b in pairs(pendingBills) do
        if b.customer == customer then
            if b.employee and b.employee ~= src then TriggerClientEvent('sl_vehicles:posResult', b.employee, { ok = false, reason = 'SUPERSEDED' }) end
            pendingBills[id] = nil
        end
    end
    billSeq = billSeq + 1
    pendingBills[billSeq] = { dealer = dealer.id, employee = src, customer = customer, model = model, price = price, at = GetGameTimer() }
    TriggerClientEvent('sl_vehicles:bill', customer, {
        billId = billSeq, dealerLabel = dealer.label, label = spec.label, brand = spec.brand,
        model = model, price = price,
    })
    return { ok = true, customer = GetPlayerName(customer) or 'client', price = price }
end

M['bill:decline'] = function(src, p)
    local b = pendingBills[tonumber(p and p.billId)]
    if b and b.customer == src then
        pendingBills[tonumber(p.billId)] = nil
        if b.employee then TriggerClientEvent('sl_vehicles:posResult', b.employee, { ok = false, reason = 'DECLINED' }) end
    end
    return { ok = true }
end

M['bill:pay'] = function(src, p)
    local billId = tonumber(p and p.billId)
    local bill = pendingBills[billId]
    if not bill or bill.customer ~= src then return { ok = false, reason = 'NO_BILL' } end
    if GetGameTimer() - bill.at > 60000 then
        if bill.employee then TriggerClientEvent('sl_vehicles:posResult', bill.employee, { ok = false, reason = 'EXPIRED' }) end
        pendingBills[billId] = nil
        return { ok = false, reason = 'EXPIRED' }
    end
    local dealer = Config.Dealership(bill.dealer); if not dealer then pendingBills[billId] = nil; return { ok = false, reason = 'BAD_DEALER' } end
    local spec = Config.CatalogModel(bill.model); if not spec then pendingBills[billId] = nil; return { ok = false, reason = 'BAD_MODEL' } end
    local account = (p and p.account == 'bank') and 'bank' or 'cash'

    -- plafond
    local char = SLV.char(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    if SLV.countOwned(char.charId) >= Config.Limits.maxOwned then return { ok = false, reason = 'MAX_OWNED' } end

    local price = retailPrice(dealer.id, bill.model)
    if price <= 0 then pendingBills[billId] = nil; return { ok = false, reason = 'PRICE' } end
    if (SLV.balance(src, account) or 0) < price then return { ok = false, reason = 'FUNDS' } end

    -- decrement stock race-safe
    local a = SLV.update('UPDATE dealership_stock SET qty = qty - 1 WHERE dealer_id = ? AND model = ? AND qty >= 1', { dealer.id, bill.model })
    if a ~= 1 then pendingBills[billId] = nil; return { ok = false, reason = 'STOCK' } end

    if not SLV.tryDebit(src, account, price, 'vehicle_buy:' .. dealer.id) then
        SLV.update('UPDATE dealership_stock SET qty = qty + 1 WHERE dealer_id = ? AND model = ?', { dealer.id, bill.model })
        return { ok = false, reason = 'FUNDS' }
    end

    -- create the owned vehicle + deliver it in front of the dealership
    local veh = SLV.createVehicle(char.charId, bill.model, { category = spec.category, status = 'out', fuel = 100 })
    local pose = dealer.saleSpawn
    SLV.spawnOwned(veh.id, { x = pose.x, y = pose.y, z = pose.z, w = pose.w })

    -- pay commission to the seller, rest to the till. Money is CONSERVED: the till only loses the
    -- commission that was actually credited (if the credit fails — e.g. seller offline — the whole
    -- price goes to the till instead of vanishing).
    local commissionPct = (bill.employee and bill.employee ~= src) and gradeCommission((myAff(bill.employee) or {}).gradeId) or 0
    local commission = math.floor(price * commissionPct / 100)
    local paidCommission = 0
    if commission > 0 and bill.employee then
        if SLV.credit(bill.employee, 'bank', commission, 'vehicle_commission:' .. dealer.id) then paidCommission = commission end
    end
    SLV.update('UPDATE dealerships SET till = till + ? WHERE id = ?', { price - paidCommission, dealer.id })

    pendingBills[billId] = nil
    if bill.employee then
        TriggerClientEvent('sl_vehicles:posResult', bill.employee, { ok = true, price = price, commission = paidCommission })
    end
    SLV.notify(src, 'success', ('Achat : %s (%s) — livré devant la concession.'):format(spec.label, veh.plate))
    return { ok = true, price = price, plate = veh.plate, balances = SLV.balance(src) or { cash = 0, bank = 0 } }
end

-- ── RESALE (reprise) — owner sells their CURRENT vehicle at the dealership for ~50% ──
M['vente:resell'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'vente', 8.0) then return { ok = false, reason = 'TOO_FAR' } end
    local netId = p and p.netId
    local dbId = netId and SLV.dbIdOfNet(netId)
    if not dbId then return { ok = false, reason = 'NO_VEHICLE' } end
    local char = SLV.char(src); if not char then return { ok = false, reason = 'NO_CHAR' } end
    if tonumber(SLV.ownerOf(dbId)) ~= tonumber(char.charId) then return { ok = false, reason = 'NOT_OWNER' } end
    local row = SLV.getVehicleRow(dbId)
    local spec = Config.CatalogModel(row.model)
    -- only models this dealer trades
    local ok = false
    for _, c in ipairs(dealer.categories) do if spec and spec.category == c then ok = true break end end
    if not ok then return { ok = false, reason = 'WRONG_DEALER' } end
    local payout = math.floor((spec and spec.price or 0) * Config.Limits.resalePct / 100)
    SLV.deleteVehicle(dbId)
    SLV.credit(src, 'bank', payout, 'vehicle_resale:' .. dealer.id)
    SLV.notify(src, 'success', ('Véhicule revendu pour $%d (virés sur la banque).'):format(payout))
    return { ok = true, payout = payout, balances = SLV.balance(src) or { cash = 0, bank = 0 } }
end

-- ── GESTION point ─────────────────────────────────────────────────────────────────
M['gestion:open'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 4.0) then return { ok = false, reason = 'TOO_FAR' } end
    local aff = myAff(src); if not aff or aff.dealerId ~= dealer.id then return { ok = false, reason = 'NOT_STAFF' } end
    return {
        ok = true,
        dealer = { id = dealer.id, label = dealer.label, accent = Config.Accent, categories = dealer.categories, catNames = Config.Categories },
        role = aff.role, perms = permKeys(aff), permList = Config.Permissions,
        stock = listStock(dealer), employees = employeesOf(dealer.id), grades = gradesList(dealer.id),
        till = SLV.dealTill(dealer.id), orders = SLV.ordersFor and SLV.ordersFor(dealer.id) or {},
        leads = SLV.leadsFor(dealer.id),
        margin = { min = Config.Limits.marginMinPct, max = Config.Limits.marginMaxPct },
        import = { normal = Config.Import.normalDelay, priority = Config.Import.priorityDelay, fee = Config.Import.priorityFee },
    }
end

M['manage:setPrice'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'prix') then return { ok = false, reason = 'NO_PERM' } end
    local model = tostring(p and p.model or '')
    local spec = Config.CatalogModel(model); if not spec then return { ok = false, reason = 'BAD_MODEL' } end
    local price = math.floor(tonumber(p and p.price) or 0)
    local floorP = math.floor(spec.price * (1 + Config.Limits.marginMinPct / 100))
    local ceilP  = math.floor(spec.price * (1 + Config.Limits.marginMaxPct / 100))
    if price < floorP or price > ceilP then return { ok = false, reason = 'MARGIN', floor = floorP, ceil = ceilP } end
    SLV.update('INSERT INTO dealership_stock (dealer_id, model, qty, price) VALUES (?,?,0,?) ON DUPLICATE KEY UPDATE price = VALUES(price)',
        { dealer.id, model, price })
    return { ok = true, stock = listStock(dealer) }
end

-- public: the models a dealer displays in its showroom (for the client expo spawns)
M['expo:list'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    local out = {}
    for _, r in ipairs(SLV.query('SELECT model, price FROM dealership_stock WHERE dealer_id = ? AND display = 1', { dealer.id }) or {}) do
        local spec = Config.CatalogModel(r.model)
        if spec then out[#out + 1] = { model = r.model, label = spec.label, price = retailPrice(dealer.id, r.model) } end
    end
    return { ok = true, models = out }
end

M['expo:set'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'expo') then return { ok = false, reason = 'NO_PERM' } end
    local model = tostring(p and p.model or ''); if not Config.CatalogModel(model) then return { ok = false, reason = 'BAD_MODEL' } end
    local display = p and p.display and 1 or 0
    -- cap displayed models to the number of expo spots
    if display == 1 then
        local n = tonumber(SLV.scalar('SELECT COUNT(*) FROM dealership_stock WHERE dealer_id = ? AND display = 1', { dealer.id })) or 0
        if n >= #(dealer.expo or {}) then return { ok = false, reason = 'EXPO_FULL' } end
    end
    SLV.update('INSERT INTO dealership_stock (dealer_id, model, qty, display) VALUES (?,?,0,?) ON DUPLICATE KEY UPDATE display = VALUES(display)',
        { dealer.id, model, display })
    TriggerClientEvent('sl_vehicles:refreshExpo', -1, dealer.id)
    return { ok = true, stock = listStock(dealer) }
end

-- Deposit personal money INTO the company till (so a new dealership can fund its first imports).
M['manage:deposit'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'caisse') then return { ok = false, reason = 'NO_PERM' } end
    local amount = math.floor(tonumber(p and p.amount) or 0)
    if amount < 1 then return { ok = false, reason = 'AMOUNT' } end
    local account = (p and p.account == 'cash') and 'cash' or 'bank'
    if (SLV.balance(src, account) or 0) < amount then return { ok = false, reason = 'FUNDS' } end
    if not SLV.tryDebit(src, account, amount, 'dealer_deposit:' .. dealer.id) then return { ok = false, reason = 'FUNDS' } end
    SLV.update('UPDATE dealerships SET till = till + ? WHERE id = ?', { amount, dealer.id })
    return { ok = true, till = SLV.dealTill(dealer.id), balances = SLV.balance(src) or { cash = 0, bank = 0 } }
end

M['manage:withdraw'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'caisse') then return { ok = false, reason = 'NO_PERM' } end
    local amount = math.floor(tonumber(p and p.amount) or 0)
    if amount < 1 then return { ok = false, reason = 'AMOUNT' } end
    local a = SLV.update('UPDATE dealerships SET till = till - ? WHERE id = ? AND till >= ?', { amount, dealer.id, amount })
    if a ~= 1 then return { ok = false, reason = 'TILL' } end
    if not SLV.credit(src, 'bank', amount, 'dealer_withdraw:' .. dealer.id) then
        SLV.update('UPDATE dealerships SET till = till + ? WHERE id = ?', { amount, dealer.id })
        return { ok = false, reason = 'TILL' }
    end
    return { ok = true, till = SLV.dealTill(dealer.id), balances = SLV.balance(src) or { cash = 0, bank = 0 } }
end

-- ── grades ──────────────────────────────────────────────────────────────────────────
local function clampPct(v) v = math.floor(tonumber(v) or 0); return math.max(0, math.min(100, v)) end
local function clampSalary(v) v = math.floor(tonumber(v) or 0); return math.max(0, math.min(100000, v)) end

M['grades:create'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'grades') then return { ok = false, reason = 'NO_PERM' } end
    local name = tostring(p and p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 48)
    if name == '' then return { ok = false, reason = 'NAME' } end
    if (SLV.scalar('SELECT COUNT(*) FROM dealership_grades WHERE dealer_id = ?', { dealer.id }) or 0) >= 30 then return { ok = false, reason = 'LIMIT' } end
    SLV.insert('INSERT INTO dealership_grades (dealer_id, name, perms, commission, salary) VALUES (?,?,?,?,?)',
        { dealer.id, name, SLV.encode(sanitizePerms(p and p.perms)), clampPct(p and p.commission), clampSalary(p and p.salary) })
    return { ok = true, grades = gradesList(dealer.id) }
end

M['grades:update'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'grades') then return { ok = false, reason = 'NO_PERM' } end
    local gid = tonumber(p and p.gradeId); if not gradeBelongs(gid, dealer.id) then return { ok = false, reason = 'NO_GRADE' } end
    local name = tostring(p and p.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 48)
    if name == '' then return { ok = false, reason = 'NAME' } end
    SLV.update('UPDATE dealership_grades SET name = ?, perms = ?, commission = ?, salary = ? WHERE id = ? AND dealer_id = ?',
        { name, SLV.encode(sanitizePerms(p and p.perms)), clampPct(p and p.commission), clampSalary(p and p.salary), gid, dealer.id })
    return { ok = true, grades = gradesList(dealer.id) }
end

M['grades:delete'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'grades') then return { ok = false, reason = 'NO_PERM' } end
    local gid = tonumber(p and p.gradeId); if not gradeBelongs(gid, dealer.id) then return { ok = false, reason = 'NO_GRADE' } end
    local affected = SLV.query('SELECT charid FROM dealership_employees WHERE dealer_id = ? AND grade_id = ?', { dealer.id, gid }) or {}
    SLV.update('UPDATE dealership_employees SET grade_id = NULL WHERE dealer_id = ? AND grade_id = ?', { dealer.id, gid })
    SLV.update('DELETE FROM dealership_grades WHERE id = ? AND dealer_id = ?', { gid, dealer.id })
    for _, r in ipairs(affected) do local s = SLV.sourceOfChar(r.charid); if s then TriggerClientEvent('sl_vehicles:refreshAff', s) end end
    return { ok = true, grades = gradesList(dealer.id), employees = employeesOf(dealer.id) }
end

-- ── employees ─────────────────────────────────────────────────────────────────────
M['employees:recruit'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local okp, me = permAt(src, dealer.id, 'employes'); if not okp then return { ok = false, reason = 'NO_PERM' } end
    local rc, target, best = GetEntityCoords(GetPlayerPed(src)), nil, 3.0
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        if pid ~= src then
            local d = #(GetEntityCoords(GetPlayerPed(pid)) - rc)
            if d < best then best = d; target = pid end
        end
    end
    if not target then return { ok = false, reason = 'NO_TARGET' } end
    local tchar = SLV.char(target); if not tchar then return { ok = false, reason = 'NO_TARGET' } end
    if affiliationOf(tchar.charId) then return { ok = false, reason = 'ALREADY' } end
    local gid = tonumber(p and p.gradeId)
    if gid and not gradeBelongs(gid, dealer.id) then gid = nil end
    if not gradeWithinCeiling(me, gid) then return { ok = false, reason = 'NO_PERM' } end
    SLV.update('INSERT INTO dealership_employees (dealer_id, charid, grade_id) VALUES (?,?,?) ON DUPLICATE KEY UPDATE grade_id = VALUES(grade_id)',
        { dealer.id, tchar.charId, gid })
    TriggerClientEvent('sl_vehicles:refreshAff', target)
    SLV.notify(target, 'success', 'Vous avez été recruté chez ' .. dealer.label .. '.')
    return { ok = true, employees = employeesOf(dealer.id), recruited = (tchar.firstname .. ' ' .. tchar.lastname) }
end

M['employees:setGrade'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    local okp, me = permAt(src, dealer.id, 'employes'); if not okp then return { ok = false, reason = 'NO_PERM' } end
    local charid = tonumber(p and p.charid); if not charid then return { ok = false, reason = 'NO_TARGET' } end
    if me and me.charId == charid then return { ok = false, reason = 'NO_TARGET' } end
    local gid = tonumber(p and p.gradeId)
    if gid and not gradeBelongs(gid, dealer.id) then return { ok = false, reason = 'NO_GRADE' } end
    if not gradeWithinCeiling(me, gid) then return { ok = false, reason = 'NO_PERM' } end
    local upd = SLV.update('UPDATE dealership_employees SET grade_id = ? WHERE dealer_id = ? AND charid = ?', { gid, dealer.id, charid })
    if upd ~= 1 then return { ok = false, reason = 'NO_TARGET' } end
    local s = SLV.sourceOfChar(charid); if s then TriggerClientEvent('sl_vehicles:refreshAff', s) end
    return { ok = true, employees = employeesOf(dealer.id) }
end

M['employees:fire'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not near(src, dealer, 'gestion', 6.0) then return { ok = false, reason = 'TOO_FAR' } end
    if not permAt(src, dealer.id, 'employes') then return { ok = false, reason = 'NO_PERM' } end
    local charid = tonumber(p and p.charid); if not charid then return { ok = false, reason = 'NO_TARGET' } end
    SLV.update('DELETE FROM dealership_employees WHERE dealer_id = ? AND charid = ?', { dealer.id, charid })
    local s = SLV.sourceOfChar(charid)
    if s then TriggerClientEvent('sl_vehicles:refreshAff', s); SLV.notify(s, 'inform', 'Vous avez été licencié de ' .. dealer.label .. '.') end
    return { ok = true, employees = employeesOf(dealer.id) }
end

-- ── leads management (perm 'leads') ─────────────────────────────────────────────────
M['leads:handle'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not permAt(src, dealer.id, 'leads') then return { ok = false, reason = 'NO_PERM' } end
    local id = tonumber(p and p.leadId); if not id then return { ok = false, reason = 'BAD' } end
    SLV.update("UPDATE company_leads SET status = 'handled' WHERE id = ? AND company_id = ?", { id, dealer.id })
    return { ok = true, leads = SLV.leadsFor(dealer.id) }
end

M['leads:call'] = function(src, p)
    local dealer = Config.Dealership(p and p.dealerId); if not dealer then return { ok = false, reason = 'BAD_DEALER' } end
    if not permAt(src, dealer.id, 'leads') then return { ok = false, reason = 'NO_PERM' } end
    local id = tonumber(p and p.leadId); if not id then return { ok = false, reason = 'BAD' } end
    local row = SLV.single('SELECT client_number FROM company_leads WHERE id = ? AND company_id = ?', { id, dealer.id })
    if not row or not row.client_number then return { ok = false, reason = 'NO_NUMBER' } end
    return { ok = true, number = row.client_number }
end

-- ── auto salaries (per-minute presence accrual, paid from the till) ──────────────────
local accrued = {}   -- src -> minutes accrued
CreateThread(function()
    while true do
        Wait(60000)
        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            local aff = myAff(pid)
            if aff and aff.role == 'employee' and aff.gradeId then
                accrued[pid] = (accrued[pid] or 0) + 1
                if accrued[pid] >= Config.Limits.salaryIntervalMin then
                    accrued[pid] = 0
                    local g = gradeRow(aff.gradeId)
                    local salary = g and tonumber(g.salary) or 0
                    if salary > 0 then
                        local a = SLV.update('UPDATE dealerships SET till = till - ? WHERE id = ? AND till >= ?', { salary, aff.dealerId, salary })
                        if a == 1 then
                            SLV.credit(pid, 'bank', salary, 'dealer_salary:' .. aff.dealerId)
                            SLV.notify(pid, 'success', ('Salaire versé : $%d'):format(salary))
                        else
                            SLV.notify(pid, 'warning', 'Salaire impayé : caisse de la concession vide.')
                        end
                    end
                end
            end
        end
    end
end)
AddEventHandler('playerDropped', function() accrued[source] = nil; pendingBills[source] = nil end)

-- ── affiliation for client gating + cleanup ─────────────────────────────────────────
function SLV.dealerOf(src)
    local aff = myAff(src)
    return aff and aff.dealerId or nil
end

-- expose pendingBills cleanup of a customer to other modules (e.g. on disconnect handled above)
CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        for id, b in pairs(pendingBills) do
            if now - b.at > 60000 then
                if b.employee then TriggerClientEvent('sl_vehicles:posResult', b.employee, { ok = false, reason = 'EXPIRED' }) end
                if b.customer then TriggerClientEvent('sl_vehicles:billClosed', b.customer) end
                pendingBills[id] = nil
            end
        end
    end
end)

Config.Log('info', 'dealership ready')
