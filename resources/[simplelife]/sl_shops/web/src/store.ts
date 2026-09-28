import { create } from 'zustand'
import { rpc } from './lib/rpc'
import { fetchNui } from './lib/fetchNui'
import type {
  OpenData, WholesaleData, Offer, WholesaleOffer, Balances, ShopMeta, Account,
  CaisseData, StockData, GestionData, DepositItem, BillData, Grade, Employee, PermDef,
} from './types'

type Screen = 'buy' | 'wholesale' | 'caisse' | 'stock' | 'gestion' | 'bill'

const REASON: Record<string, string> = {
  FUNDS: 'Fonds insuffisants', OVERWEIGHT: 'Inventaire plein', STOCK: 'Stock insuffisant',
  EMPTY: 'Panier vide', TOO_FAR: 'Trop loin', NOT_OWNER: 'Pas le propriétaire',
  TILL: 'Caisse insuffisante', NO_SHOP: 'Aucune boutique', PRICE: 'Prix invalide',
  AMOUNT: 'Montant invalide', QTY: 'Quantité trop élevée', RATE: 'Trop rapide',
  NO_ITEM: 'Article introuvable', NO_PERM: 'Permission refusée', NOT_STAFF: 'Vous ne travaillez pas ici',
  NO_CUSTOMER: 'Aucun client à proximité', NO_TARGET: 'Aucun joueur à proximité', NOT_ENOUGH: "Vous n'avez pas assez de cet item",
  ALREADY: 'Ce joueur est déjà dans une société', NAME: 'Nom invalide', NO_GRADE: 'Grade introuvable',
  NO_BILL: 'Facture introuvable', EXPIRED: 'Facture expirée', CLOSED: 'Boutique fermée', ERROR: 'Erreur serveur',
}
const reasonMsg = (r?: string) => REASON[r || ''] || 'Action impossible'

interface ShopStore {
  open: boolean
  screen: Screen
  busy: boolean
  toast: { kind: 'ok' | 'err'; msg: string } | null
  cart: Record<string, number>
  account: Account

  // 24/7 buy
  shop: ShopMeta | null
  offers: Offer[]
  balances: Balances

  // wholesale
  wholesale: WholesaleOffer[]
  wTill: number
  wShopLabel: string

  // management (gestion) + caisse
  role: 'owner' | 'employee'
  perms: string[]
  permList: PermDef[]
  till: number
  employees: Employee[]
  grades: Grade[]

  // stock point
  deposit: DepositItem[]
  canManage: boolean

  // pos / bill
  billing: string | null
  bill: BillData | null

  openShop: (d: OpenData) => void
  openWholesale: (d: WholesaleData) => void
  openCaisse: (d: CaisseData) => void
  openStock: (d: StockData) => void
  openGestion: (d: GestionData) => void
  openBill: (d: BillData) => void
  close: () => void
  setAccount: (a: Account) => void
  add: (item: string) => void
  sub: (item: string) => void
  flash: (kind: 'ok' | 'err', msg: string) => void

  buy: () => Promise<void>
  wholesaleBuy: () => Promise<void>
  setPrice: (item: string, price: number) => Promise<void>
  withdraw: (amount: number) => Promise<void>
  gradeSave: (name: string, perms: string[], id?: number) => Promise<void>
  gradeDelete: (id: number) => Promise<void>
  recruit: (gradeId: number | null) => Promise<void>
  fire: (charid: number) => Promise<void>
  setGrade: (charid: number, gradeId: number | null) => Promise<void>
  stockDeposit: (item: string, qty: number) => Promise<void>
  stockWithdraw: (item: string, qty: number) => Promise<void>
  posBill: () => Promise<void>
  handlePosResult: (d: { ok?: boolean }) => void
  billPay: (account: Account) => Promise<void>
  billDecline: () => Promise<void>
}

let toastTimer: ReturnType<typeof setTimeout> | undefined

export const useShop = create<ShopStore>((set, get) => ({
  open: false,
  screen: 'buy',
  busy: false,
  toast: null,
  cart: {},
  account: 'cash',
  shop: null,
  offers: [],
  balances: { cash: 0, bank: 0 },
  wholesale: [],
  wTill: 0,
  wShopLabel: '',
  role: 'employee',
  perms: [],
  permList: [],
  till: 0,
  employees: [],
  grades: [],
  deposit: [],
  canManage: false,
  billing: null,
  bill: null,

  openShop: (d) =>
    set({ open: true, screen: 'buy', shop: d.shop, offers: d.offers || [], balances: d.balances || { cash: 0, bank: 0 }, account: 'cash', cart: {}, toast: null }),

  openWholesale: (d) =>
    set({ open: true, screen: 'wholesale', wholesale: d.shop.offers || [], wTill: d.shop.till || 0, wShopLabel: d.shop.shopLabel, cart: {}, toast: null }),

  openCaisse: (d) =>
    set({ open: true, screen: 'caisse', shop: d.shop, offers: d.offers || [], till: d.till || 0, perms: d.perms || [], role: 'employee', cart: {}, billing: null, toast: null }),

  openStock: (d) =>
    set({ open: true, screen: 'stock', shop: d.shop, offers: d.offers || [], deposit: d.deposit || [], canManage: !!d.canManage, toast: null }),

  openGestion: (d) =>
    set({
      open: true, screen: 'gestion', shop: d.shop, role: d.role, perms: d.perms || [], permList: d.permList || [],
      offers: d.offers || [], employees: d.employees || [], grades: d.grades || [], toast: null,
    }),

  openBill: (d) => set({ open: true, screen: 'bill', bill: d, toast: null }),

  close: () => set({ open: false, cart: {}, bill: null, billing: null, toast: null }),
  setAccount: (a) => set({ account: a }),
  add: (item) => set((s) => ({ cart: { ...s.cart, [item]: (s.cart[item] || 0) + 1 } })),
  sub: (item) =>
    set((s) => {
      const n = (s.cart[item] || 0) - 1
      const cart = { ...s.cart }
      if (n <= 0) delete cart[item]
      else cart[item] = n
      return { cart }
    }),
  flash: (kind, msg) => {
    set({ toast: { kind, msg } })
    if (toastTimer) clearTimeout(toastTimer)
    toastTimer = setTimeout(() => set({ toast: null }), 2600)
  },

  buy: async () => {
    const { cart, account, shop, busy } = get()
    if (busy || !shop) return
    const lines = Object.entries(cart).filter(([, q]) => q > 0).map(([item, qty]) => ({ item, qty }))
    if (!lines.length) return
    set({ busy: true })
    const res = await rpc<{ ok: boolean; reason?: string; balances?: Balances; offers?: Offer[] }>('buy', { shopId: shop.id, cart: lines, account }, { ok: true })
    set({ busy: false })
    if (res.ok) { set({ cart: {}, balances: res.balances ?? get().balances, offers: res.offers ?? get().offers }); get().flash('ok', 'Achat effectué') }
    else get().flash('err', reasonMsg(res.reason))
  },

  wholesaleBuy: async () => {
    const { cart, busy } = get()
    if (busy) return
    const lines = Object.entries(cart).filter(([, q]) => q > 0).map(([item, qty]) => ({ item, qty }))
    if (!lines.length) return
    set({ busy: true })
    const res = await rpc<{ ok: boolean; reason?: string; shop?: WholesaleData['shop'] }>('wholesale:buy', { cart: lines }, { ok: true })
    set({ busy: false })
    if (res.ok) { set({ cart: {}, wholesale: res.shop?.offers ?? get().wholesale, wTill: res.shop?.till ?? get().wTill }); get().flash('ok', 'Réappro effectué') }
    else get().flash('err', reasonMsg(res.reason))
  },

  setPrice: async (item, price) => {
    const { shop } = get()
    if (!shop || !Number.isFinite(price) || price < 1) return
    const res = await rpc<{ ok: boolean; reason?: string; offers?: Offer[] }>('manage:setPrice', { shopId: shop.id, item, price: Math.round(price) }, { ok: true })
    if (res.ok) { set({ offers: res.offers ?? get().offers }); get().flash('ok', 'Prix mis à jour') }
    else get().flash('err', reasonMsg(res.reason))
  },

  withdraw: async (amount) => {
    const { shop, busy } = get()
    if (busy || !shop || !Number.isFinite(amount) || amount < 1) return
    set({ busy: true })
    const res = await rpc<{ ok: boolean; reason?: string; till?: number }>('manage:withdraw', { shopId: shop.id, amount: Math.round(amount) }, { ok: true, till: Math.max(0, get().till - Math.round(amount)) })
    set({ busy: false })
    if (res.ok) { set({ till: res.till ?? 0 }); get().flash('ok', 'Retrait effectué') }
    else get().flash('err', reasonMsg(res.reason))
  },

  gradeSave: async (name, perms, id) => {
    const { shop } = get()
    if (!shop || !name.trim()) return
    const method = id ? 'grades:update' : 'grades:create'
    const params = id ? { shopId: shop.id, gradeId: id, name, perms } : { shopId: shop.id, name, perms }
    const res = await rpc<{ ok: boolean; reason?: string; grades?: Grade[] }>(method, params, { ok: true, grades: get().grades })
    if (res.ok) { set({ grades: res.grades ?? get().grades }); get().flash('ok', id ? 'Grade modifié' : 'Grade créé') }
    else get().flash('err', reasonMsg(res.reason))
  },

  gradeDelete: async (id) => {
    const { shop } = get()
    if (!shop) return
    const res = await rpc<{ ok: boolean; reason?: string; grades?: Grade[]; employees?: Employee[] }>('grades:delete', { shopId: shop.id, gradeId: id }, { ok: true, grades: get().grades.filter((g) => g.id !== id) })
    if (res.ok) { set({ grades: res.grades ?? get().grades, employees: res.employees ?? get().employees }); get().flash('ok', 'Grade supprimé') }
    else get().flash('err', reasonMsg(res.reason))
  },

  recruit: async (gradeId) => {
    const { shop } = get()
    if (!shop) return
    const res = await rpc<{ ok: boolean; reason?: string; employees?: Employee[]; recruited?: string }>('employees:recruit', { shopId: shop.id, gradeId }, { ok: true, employees: get().employees })
    if (res.ok) { set({ employees: res.employees ?? get().employees }); get().flash('ok', 'Recruté : ' + (res.recruited || '')) }
    else get().flash('err', reasonMsg(res.reason))
  },

  fire: async (charid) => {
    const { shop } = get()
    if (!shop) return
    const res = await rpc<{ ok: boolean; reason?: string; employees?: Employee[] }>('employees:fire', { shopId: shop.id, charid }, { ok: true, employees: get().employees.filter((e) => e.charid !== charid) })
    if (res.ok) { set({ employees: res.employees ?? get().employees }); get().flash('ok', 'Employé licencié') }
    else get().flash('err', reasonMsg(res.reason))
  },

  setGrade: async (charid, gradeId) => {
    const { shop } = get()
    if (!shop) return
    const res = await rpc<{ ok: boolean; reason?: string; employees?: Employee[] }>('employees:setGrade', { shopId: shop.id, charid, gradeId }, { ok: true, employees: get().employees.map((e) => (e.charid === charid ? { ...e, gradeId } : e)) })
    if (res.ok) { set({ employees: res.employees ?? get().employees }); get().flash('ok', 'Grade attribué') }
    else get().flash('err', reasonMsg(res.reason))
  },

  stockDeposit: async (item, qty) => {
    const { shop, busy } = get()
    if (busy || !shop || qty <= 0) return
    set({ busy: true })
    const res = await rpc<{ ok: boolean; reason?: string; offers?: Offer[]; deposit?: DepositItem[] }>('stock:deposit', { shopId: shop.id, item, qty }, { ok: true })
    set({ busy: false })
    if (res.ok) { set({ offers: res.offers ?? get().offers, deposit: res.deposit ?? get().deposit }); get().flash('ok', 'Déposé dans le stock') }
    else get().flash('err', reasonMsg(res.reason))
  },

  stockWithdraw: async (item, qty) => {
    const { shop, busy } = get()
    if (busy || !shop || qty <= 0) return
    set({ busy: true })
    const res = await rpc<{ ok: boolean; reason?: string; offers?: Offer[]; deposit?: DepositItem[] }>('stock:withdraw', { shopId: shop.id, item, qty }, { ok: true })
    set({ busy: false })
    if (res.ok) { set({ offers: res.offers ?? get().offers, deposit: res.deposit ?? get().deposit }); get().flash('ok', 'Retiré du stock') }
    else get().flash('err', reasonMsg(res.reason))
  },

  posBill: async () => {
    const { cart, shop, busy } = get()
    if (busy || !shop) return
    const lines = Object.entries(cart).filter(([, q]) => q > 0).map(([item, qty]) => ({ item, qty }))
    if (!lines.length) return
    set({ busy: true })
    const res = await rpc<{ ok: boolean; reason?: string; customer?: string }>('pos:bill', { shopId: shop.id, cart: lines }, { ok: true, customer: 'Client' })
    set({ busy: false })
    if (res.ok) { set({ billing: res.customer || 'Client' }); get().flash('ok', 'Facture envoyée à ' + (res.customer || 'client')) }
    else get().flash('err', reasonMsg(res.reason))
  },

  handlePosResult: (d) => {
    if (d && d.ok) set({ cart: {}, billing: null })
    else set({ billing: null })
  },

  billPay: async (account) => {
    const { bill, busy } = get()
    if (busy || !bill) return
    set({ busy: true })
    const res = await rpc<{ ok: boolean; reason?: string }>('bill:pay', { billId: bill.billId, account }, { ok: true })
    set({ busy: false })
    if (res.ok) { get().flash('ok', 'Payé'); fetchNui('close', {}); setTimeout(() => get().close(), 300) }
    else {
      get().flash('err', reasonMsg(res.reason))
      if (res.reason === 'EXPIRED' || res.reason === 'NO_BILL') { fetchNui('close', {}); setTimeout(() => get().close(), 300) }
    }
  },

  billDecline: async () => {
    const { bill } = get()
    if (bill) await rpc('bill:decline', { billId: bill.billId }, { ok: true })
    fetchNui('close', {})
    get().close()
  },
}))

// Right-click / Escape close (and tell Lua to release focus). For a pending bill, treat it as decline.
export function wireCloseKeys() {
  const dismiss = () => {
    const st = useShop.getState()
    if (!st.open) return
    if (st.screen === 'bill') { st.billDecline(); return }
    fetchNui('close', {})
    st.close()
  }
  window.addEventListener('keydown', (e) => { if (e.key === 'Escape') dismiss() })
  window.addEventListener('contextmenu', (e) => { if (useShop.getState().open) { e.preventDefault(); dismiss() } })
}
