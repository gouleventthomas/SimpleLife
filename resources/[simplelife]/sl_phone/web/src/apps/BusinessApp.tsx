import { useEffect, useState } from 'react'
import {
  Briefcase, RefreshCw, Plus, Minus, Receipt, Wallet,
  Utensils, CupSoda, Pill, Wrench, FileText, Key, Package, Box, type LucideIcon,
} from 'lucide-react'
import { usePhone } from '../store'
import { shopsRpc } from '../lib/shopsRpc'
import { LargeHeader, ListGroup, ListRow, IconBadge, Empty } from './ui'

const CAT_ICON: Record<string, LucideIcon> = {
  food: Utensils, drink: CupSoda, medical: Pill, tool: Wrench, document: FileText, key: Key, material: Package, misc: Box,
}
const CAT_COLOR: Record<string, string> = {
  food: '#ff9500', drink: '#0a84ff', medical: '#ff375f', tool: '#8e8e93', document: '#5e9bff', key: '#ffd60a', material: '#a2845e', misc: '#8e8e93',
}
const money = (n: number) => '$' + Math.round(Number(n) || 0).toLocaleString('en-US')
const REASON: Record<string, string> = {
  NO_SHOP: 'Aucune société', NO_PERM: 'Permission refusée', NO_CUSTOMER: 'Aucun client à proximité',
  EMPTY: 'Panier vide', STOCK: 'Stock insuffisant', AMOUNT: 'Montant invalide', QTY: 'Quantité trop élevée',
  CLOSED: 'Boutique fermée', RATE: 'Trop rapide', ERROR: 'Erreur serveur',
}
const reasonMsg = (r?: string) => REASON[r || ''] || 'Action impossible'

interface Offer { item: string; label: string; category: string; weight: number; price: number; stock: number }
interface Company {
  ok: boolean; reason?: string
  shop?: { id: string; label: string }
  role?: string; perms?: string[]; offers?: Offer[]; till?: number; canBill?: boolean
}

const MOCK: Company = {
  ok: true, shop: { id: 'ltd_mirror', label: 'LTD Mirror Park' }, role: 'owner', canBill: true, till: 4250,
  offers: [
    { item: 'water', label: "Bouteille d'eau", category: 'drink', weight: 500, price: 8, stock: 42 },
    { item: 'coffee', label: 'Café', category: 'drink', weight: 300, price: 10, stock: 12 },
    { item: 'sandwich', label: 'Sandwich', category: 'food', weight: 250, price: 12, stock: 8 },
    { item: 'medkit', label: 'Medkit', category: 'medical', weight: 1000, price: 450, stock: 3 },
  ],
}

function Stepper({ qty, onAdd, onSub, canAdd }: { qty: number; onAdd: () => void; onSub: () => void; canAdd: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <button onClick={onSub} className="w-7 h-7 rounded-full bg-white/10 flex items-center justify-center active:scale-90"><Minus size={14} /></button>
      <span className="w-4 text-center text-[14px] tabular-nums">{qty}</span>
      <button onClick={onAdd} disabled={!canAdd} className="w-7 h-7 rounded-full bg-white/10 flex items-center justify-center active:scale-90 disabled:opacity-30"><Plus size={14} /></button>
    </div>
  )
}

export function BusinessApp() {
  const [data, setData] = useState<Company | null>(null)
  const [tab, setTab] = useState<'stock' | 'sell'>('stock')
  const [cart, setCart] = useState<Record<string, number>>({})
  const [sent, setSent] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const notify = usePhone((s) => s.pushNotification)

  const load = () => { shopsRpc<Company>('phone:company', {}, MOCK).then(setData) }
  useEffect(load, [])

  if (!data) return <div className="h-full flex items-center justify-center text-white/40">Chargement…</div>
  if (!data.ok || !data.shop) {
    return (
      <div className="h-full flex flex-col">
        <LargeHeader title="Société" />
        <Empty icon={<Briefcase size={40} />} label="Aucune société" hint="Vous ne faites partie d'aucune société." />
      </div>
    )
  }

  const offers = data.offers || []
  const add = (it: string, max: number) => setCart((c) => ({ ...c, [it]: Math.min((c[it] || 0) + 1, max < 0 ? 9999 : max) }))
  const sub = (it: string) => setCart((c) => { const n = (c[it] || 0) - 1; const x = { ...c }; if (n <= 0) delete x[it]; else x[it] = n; return x })
  const total = offers.reduce((t, o) => t + o.price * (cart[o.item] || 0), 0)
  const count = Object.values(cart).reduce((a, b) => a + b, 0)

  const bill = async () => {
    if (busy || count === 0) return
    setBusy(true)
    const lines = Object.entries(cart).filter(([, q]) => q > 0).map(([item, qty]) => ({ item, qty }))
    const res = await shopsRpc<{ ok: boolean; reason?: string; customer?: string }>('phone:bill', { cart: lines }, { ok: true, customer: 'Client' })
    setBusy(false)
    if (res.ok) { setSent(res.customer || 'client'); setCart({}) }
    else notify({ app: 'business', title: 'Société', body: reasonMsg(res.reason) })
  }

  return (
    <div className="h-full flex flex-col">
      <LargeHeader title={data.shop.label} right={<button onClick={load} className="active:opacity-50"><RefreshCw size={20} /></button>} />

      {data.canBill && (
        <div className="px-4 pb-2 flex gap-1.5">
          {(['stock', 'sell'] as const).map((t) => (
            <button key={t} onClick={() => setTab(t)}
              className={`flex-1 py-1.5 rounded-[10px] text-[13px] font-medium ${tab === t ? 'bg-[#5e5ce6] text-white' : 'bg-white/10 text-white/55'}`}>
              {t === 'stock' ? 'Stock' : 'Vendre'}
            </button>
          ))}
        </div>
      )}

      {tab === 'stock' && (
        <div className="flex-1 overflow-y-auto no-scrollbar pb-6">
          <ListGroup header={`Caisse · ${data.role === 'owner' ? 'Propriétaire' : 'Employé'}`}>
            <ListRow leading={<IconBadge color="#30d158"><Wallet size={16} color="#fff" /></IconBadge>} title="Solde caisse" value={money(data.till || 0)} />
          </ListGroup>
          <ListGroup header={`Stock · ${offers.length} article${offers.length > 1 ? 's' : ''}`} footer="Vue à distance du stock de la société.">
            {offers.length === 0 && <ListRow title="Aucun stock" subtitle="Réapprovisionnez chez le grossiste." />}
            {offers.map((o) => {
              const Icon = CAT_ICON[o.category] || Box
              return <ListRow key={o.item} leading={<IconBadge color={CAT_COLOR[o.category] || '#8e8e93'}><Icon size={16} color="#fff" /></IconBadge>}
                title={o.label} subtitle={`Stock ${o.stock}`} value={money(o.price)} />
            })}
          </ListGroup>
        </div>
      )}

      {tab === 'sell' && data.canBill && (
        sent ? (
          <div className="flex-1 flex flex-col items-center justify-center text-center px-10 gap-4">
            <IconBadge color="#5e5ce6"><Receipt size={20} color="#fff" /></IconBadge>
            <div className="text-white text-[17px] font-semibold">Facture envoyée à {sent}</div>
            <p className="text-white/55 text-[14px]">En attente du paiement du client.</p>
            <button onClick={() => setSent(null)} className="mt-2 px-5 py-2 rounded-full bg-[#5e5ce6] text-white text-[14px] font-medium">Nouvelle vente</button>
          </div>
        ) : (
          <>
            <div className="flex-1 overflow-y-auto no-scrollbar">
              <ListGroup header="Articles">
                {offers.length === 0 && <ListRow title="Aucun stock" subtitle="Rien à vendre." />}
                {offers.map((o) => {
                  const Icon = CAT_ICON[o.category] || Box
                  const qty = cart[o.item] || 0
                  return <ListRow key={o.item} leading={<IconBadge color={CAT_COLOR[o.category] || '#8e8e93'}><Icon size={16} color="#fff" /></IconBadge>}
                    title={o.label} subtitle={`${money(o.price)} · stock ${o.stock}`}
                    right={<Stepper qty={qty} onAdd={() => add(o.item, o.stock)} onSub={() => sub(o.item)} canAdd={o.stock === -1 || qty < o.stock} />} />
                })}
              </ListGroup>
            </div>
            <div className="shrink-0 border-t border-white/10 p-4 pb-6 space-y-3 bg-black/30">
              <div className="flex items-center justify-between">
                <span className="text-white/55 text-[13px]">{count} article{count > 1 ? 's' : ''}</span>
                <span className="text-[18px] font-bold text-white">{money(total)}</span>
              </div>
              <button onClick={bill} disabled={busy || count === 0}
                className="w-full py-2.5 rounded-[12px] font-semibold text-white bg-[#5e5ce6] disabled:opacity-30 active:scale-[0.99]">
                Facturer le client le plus proche
              </button>
            </div>
          </>
        )
      )}
    </div>
  )
}
