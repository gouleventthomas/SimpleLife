export interface Balances {
  cash: number
  bank: number
}

export interface ShopMeta {
  id: string
  label: string
  type: string
  accent: string
}

// stock === -1 means infinite (NPC store).
export interface Offer {
  item: string
  label: string
  category: string
  weight: number
  price: number
  stock: number
}

export interface OpenData {
  ok: boolean
  mode: 'buy' | 'manage'
  shop: ShopMeta
  offers: Offer[]
  isOwner: boolean
  till?: number
  balances: Balances
}

export interface WholesaleOffer {
  item: string
  label: string
  category: string
  price: number
  defaultPrice: number
}

export interface WholesaleState {
  shopId: string
  shopLabel: string
  offers: WholesaleOffer[]
  till: number
}

export interface WholesaleData {
  ok: boolean
  shop: WholesaleState
}

export type Account = 'cash' | 'bank'

// ── business (player LTD) ───────────────────────────────────────────────────────
export interface PermDef {
  key: string
  label: string
}

export interface Grade {
  id: number
  name: string
  perms: string[]
}

export interface Employee {
  charid: number
  gradeId: number | null
  name: string
}

export interface TerminalData {
  ok: boolean
  shop: ShopMeta
  role: 'owner' | 'employee'
  perms: string[]
  permList: PermDef[]
  offers: Offer[]
  till: number
  employees: Employee[]
  grades: Grade[]
}

export interface PosData {
  ok: boolean
  shop: ShopMeta
  offers: Offer[]
}

export interface BillItem {
  label: string
  qty: number
  price: number
}

export interface BillData {
  billId: number
  shopLabel: string
  total: number
  items: BillItem[]
}

// ── 3 LTD points ────────────────────────────────────────────────────────────────
export interface DepositItem {
  item: string
  label: string
  category: string
  carried: number
}

export interface CaisseData {
  ok: boolean
  shop: ShopMeta
  offers: Offer[]
  till: number
  perms: string[]
}

export interface StockData {
  ok: boolean
  shop: ShopMeta
  offers: Offer[]
  deposit: DepositItem[]
  canManage: boolean
}

export interface GestionData {
  ok: boolean
  shop: ShopMeta
  role: 'owner' | 'employee'
  perms: string[]
  permList: PermDef[]
  offers: Offer[]
  employees: Employee[]
  grades: Grade[]
}
