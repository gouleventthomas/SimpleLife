import type { OpenData, WholesaleData, CaisseData, StockData, GestionData, BillData } from './types'

const STOCK = [
  { item: 'water', label: "Bouteille d'eau", category: 'drink', weight: 500, price: 8, stock: 42 },
  { item: 'cola', label: 'Cola', category: 'drink', weight: 350, price: 8, stock: 30 },
  { item: 'coffee', label: 'Café', category: 'drink', weight: 300, price: 10, stock: 12 },
  { item: 'sandwich', label: 'Sandwich', category: 'food', weight: 250, price: 12, stock: 8 },
  { item: 'bandage', label: 'Bandage', category: 'medical', weight: 100, price: 35, stock: 20 },
  { item: 'medkit', label: 'Medkit', category: 'medical', weight: 1000, price: 450, stock: 3 },
]

const PERM_LIST = [
  { key: 'pos', label: 'Tenir la caisse (vendre)' },
  { key: 'restock', label: 'Commander le stock (grossiste)' },
  { key: 'prices', label: 'Modifier les prix de vente' },
  { key: 'withdraw', label: 'Retirer de la caisse' },
  { key: 'employees', label: 'Gérer les employés' },
  { key: 'grades', label: 'Gérer les grades & permissions' },
]
const ALL = PERM_LIST.map((p) => p.key)
const SHOP = { id: 'ltd_morningwood', label: 'LTD Morningwood', type: 'ltd', accent: '#46d39a' }

export const MOCK_BUY: OpenData = {
  ok: true, mode: 'buy',
  shop: { id: 's247_strawberry', label: '24/7 Strawberry', type: '247', accent: '#46d39a' },
  isOwner: false, balances: { cash: 320, bank: 18400 },
  offers: STOCK.map((s) => ({ ...s, stock: -1 })),
}

export const MOCK_CAISSE: CaisseData = { ok: true, shop: SHOP, offers: STOCK, till: 4250, perms: ALL }

export const MOCK_STOCK: StockData = {
  ok: true, shop: SHOP, offers: STOCK, canManage: true,
  deposit: [
    { item: 'water', label: "Bouteille d'eau", category: 'drink', carried: 24 },
    { item: 'medkit', label: 'Medkit', category: 'medical', carried: 2 },
  ],
}

export const MOCK_GESTION: GestionData = {
  ok: true, shop: SHOP, role: 'owner', perms: ALL, permList: PERM_LIST, offers: STOCK,
  employees: [
    { charid: 12, gradeId: 1, name: 'John Doe' },
    { charid: 34, gradeId: 2, name: 'Jane Roe' },
  ],
  grades: [
    { id: 1, name: 'Gérant', perms: ['pos', 'restock', 'prices', 'withdraw', 'employees', 'grades'] },
    { id: 2, name: 'Employé', perms: ['pos'] },
  ],
}

export const MOCK_BILL: BillData = {
  billId: 1, shopLabel: 'LTD Morningwood', total: 28,
  items: [
    { label: "Bouteille d'eau", qty: 2, price: 8 },
    { label: 'Café', qty: 1, price: 10 },
  ],
}

export const MOCK_WHOLESALE: WholesaleData = {
  ok: true,
  shop: {
    shopId: 'ltd_morningwood', shopLabel: 'LTD Morningwood', till: 4250,
    offers: [
      { item: 'water', label: "Bouteille d'eau", category: 'drink', price: 3, defaultPrice: 8 },
      { item: 'cola', label: 'Cola', category: 'drink', price: 3, defaultPrice: 8 },
      { item: 'coffee', label: 'Café', category: 'drink', price: 4, defaultPrice: 10 },
      { item: 'medkit', label: 'Medkit', category: 'medical', price: 200, defaultPrice: 450 },
    ],
  },
}
