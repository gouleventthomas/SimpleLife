import { useEffect, useState, type ReactNode } from 'react'
import {
  X, Plus, Minus, Banknote, Wallet, Store, Truck, Briefcase, Receipt, ShoppingCart, Tag,
  PiggyBank, Users, ShieldCheck, Trash2, Pencil, UserPlus, Boxes, ArrowUpFromLine, ArrowDownToLine,
} from 'lucide-react'
import { useShop, wireCloseKeys } from './store'
import { useNuiEvent } from './lib/nui'
import { glass, type Glass } from './lib/glass'
import { catIcon } from './lib/icons'
import { money } from './lib/format'
import { fetchNui, inGame } from './lib/fetchNui'
import { MOCK_BUY, MOCK_CAISSE, MOCK_STOCK, MOCK_GESTION, MOCK_BILL, MOCK_WHOLESALE } from './dev'
import type { OpenData, CaisseData, StockData, GestionData, BillData, WholesaleData } from './types'

function closeUI() {
  fetchNui('close', {})
  useShop.getState().close()
}

function useCan() {
  const role = useShop((s) => s.role)
  const perms = useShop((s) => s.perms)
  return (k: string) => role === 'owner' || perms.includes(k)
}

function Stepper({ qty, onAdd, onSub, canAdd }: { qty: number; onAdd: () => void; onSub: () => void; canAdd: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <button onClick={onSub} className="w-7 h-7 rounded-full bg-white/10 flex items-center justify-center active:scale-90"><Minus size={15} /></button>
      <span className="w-5 text-center text-[14px] tabular-nums">{qty}</span>
      <button onClick={onAdd} disabled={!canAdd} className="w-7 h-7 rounded-full bg-white/10 flex items-center justify-center active:scale-90 disabled:opacity-30"><Plus size={15} /></button>
    </div>
  )
}

function AccountToggle({ g }: { g: Glass }) {
  const account = useShop((s) => s.account)
  const setAccount = useShop((s) => s.setAccount)
  const bal = useShop((s) => s.balances)
  return (
    <div className="flex items-center gap-1 p-1 rounded-full bg-black/30">
      {(['cash', 'bank'] as const).map((a) => (
        <button key={a} onClick={() => setAccount(a)} style={account === a ? g.confirm : undefined}
          className={`px-3 py-1 rounded-full text-[12px] flex items-center gap-1.5 ${account === a ? 'text-white' : 'text-white/55'}`}>
          {a === 'cash' ? <Banknote size={14} /> : <Wallet size={14} />}
          {a === 'cash' ? 'Espèces' : 'Banque'}
          <span className="opacity-70">{money(a === 'cash' ? bal.cash : bal.bank)}</span>
        </button>
      ))}
    </div>
  )
}

function HeaderBar({ icon, title, subtitle, right }: { icon: ReactNode; title: string; subtitle?: string; right?: ReactNode }) {
  return (
    <div className="h-16 shrink-0 px-5 flex items-center gap-3 border-b border-white/10">
      <div className="w-10 h-10 rounded-[11px] bg-white/10 flex items-center justify-center">{icon}</div>
      <div className="min-w-0">
        <div className="text-[17px] font-semibold leading-tight truncate">{title}</div>
        {subtitle && <div className="text-[12px] text-white/50 truncate">{subtitle}</div>}
      </div>
      <div className="ml-auto flex items-center gap-3">
        {right}
        <button onClick={closeUI} className="w-8 h-8 rounded-full bg-white/10 flex items-center justify-center active:scale-90"><X size={18} /></button>
      </div>
    </div>
  )
}

function Badge({ category, size = 40 }: { category: string; size?: number }) {
  const Icon = catIcon(category)
  return <div className="rounded-[10px] bg-white/10 flex items-center justify-center shrink-0" style={{ width: size, height: size }}><Icon size={Math.round(size * 0.5)} /></div>
}

function ItemTile({ category, label, sub, price, qty, onAdd, onSub, canAdd, g }: {
  category: string; label: string; sub: string; price: number; qty: number
  onAdd: () => void; onSub: () => void; canAdd: boolean; g: Glass
}) {
  return (
    <div className="rounded-[14px] p-3 flex flex-col gap-2 bg-white/[0.05] border border-white/10">
      <div className="flex items-center gap-2.5">
        <Badge category={category} />
        <div className="min-w-0">
          <div className="text-[14px] font-medium truncate">{label}</div>
          <div className="text-[12px] text-white/45 truncate">{sub}</div>
        </div>
      </div>
      <div className="flex items-center justify-between mt-auto pt-1">
        <div className="text-[15px] font-semibold">{money(price)}</div>
        {qty > 0 ? <Stepper qty={qty} onAdd={onAdd} onSub={onSub} canAdd={canAdd} />
          : <button onClick={onAdd} disabled={!canAdd} style={g.confirm} className="px-3 py-1 rounded-full text-[13px] disabled:opacity-30">Ajouter</button>}
      </div>
    </div>
  )
}

function CartList({ rows }: { rows: { label: string; qty: number; total: number }[] }) {
  return (
    <div className="flex-1 overflow-y-auto no-scrollbar px-4 space-y-2">
      {rows.length === 0 && <div className="text-white/35 text-[13px] py-8 text-center">Panier vide</div>}
      {rows.map((r, i) => (
        <div key={i} className="flex items-center justify-between text-[13px]">
          <span className="truncate text-white/80">{r.qty}× {r.label}</span>
          <span className="text-white/90 tabular-nums">{money(r.total)}</span>
        </div>
      ))}
    </div>
  )
}

function Toast() {
  const toast = useShop((s) => s.toast)
  if (!toast) return null
  return (
    <div className="absolute bottom-6 left-1/2 -translate-x-1/2 px-4 py-2 rounded-full text-[13px] font-medium shadow-lg z-50"
      style={{ background: toast.kind === 'ok' ? 'rgba(48,209,88,0.95)' : 'rgba(255,69,58,0.95)' }}>
      {toast.msg}
    </div>
  )
}

// reusable: cart grid + side cart used by Buy / Wholesale / POS
function CartGrid({ kind, g }: { kind: 'buy' | 'wholesale' | 'pos'; g: Glass }) {
  const offers = useShop((s) => (kind === 'wholesale' ? s.wholesale : s.offers))
  const cart = useShop((s) => s.cart)
  const add = useShop((s) => s.add); const sub = useShop((s) => s.sub)
  const busy = useShop((s) => s.busy); const billing = useShop((s) => s.billing)
  const buy = useShop((s) => s.buy); const wbuy = useShop((s) => s.wholesaleBuy); const posBill = useShop((s) => s.posBill)
  const wTill = useShop((s) => s.wTill)
  const total = offers.reduce((t, o) => t + o.price * (cart[o.item] || 0), 0)
  const count = Object.values(cart).reduce((a, b) => a + b, 0)
  const title = kind === 'pos' ? 'Ticket' : kind === 'wholesale' ? 'Commande' : 'Panier'

  return (
    <div className="flex-1 flex min-h-0">
      <div className="flex-1 overflow-y-auto no-scrollbar p-4 grid grid-cols-3 gap-3 content-start">
        {offers.map((o) => {
          const stock = (o as { stock?: number }).stock
          const qty = cart[o.item] || 0
          const canAdd = stock === undefined || stock === -1 || qty < stock
          const sub2 = kind === 'wholesale' ? `Revente ~ ${money((o as { defaultPrice?: number }).defaultPrice || 0)}`
            : stock === -1 || stock === undefined ? 'En stock' : `Stock ${stock}`
          return <ItemTile key={o.item} category={o.category} label={o.label} sub={sub2} price={o.price} qty={qty}
            onAdd={() => add(o.item)} onSub={() => sub(o.item)} canAdd={canAdd} g={g} />
        })}
        {offers.length === 0 && <div className="col-span-3 text-center text-white/40 py-16">Aucun article.</div>}
      </div>
      <div className="w-[300px] shrink-0 border-l border-white/10 flex flex-col">
        <div className="px-4 py-3 text-[13px] uppercase tracking-wide text-white/45 flex items-center gap-2"><ShoppingCart size={15} /> {title}</div>
        <CartList rows={offers.filter((o) => cart[o.item]).map((o) => ({ label: o.label, qty: cart[o.item], total: o.price * cart[o.item] }))} />
        <div className="shrink-0 border-t border-white/10 p-4 space-y-3">
          {kind === 'buy' && <AccountToggle g={g} />}
          {kind === 'wholesale' && <div className="flex items-center justify-between text-[13px]"><span className="text-white/55">Caisse société</span><span className="font-semibold">{money(wTill)}</span></div>}
          <div className="flex items-center justify-between"><span className="text-white/55 text-[13px]">{count} article{count > 1 ? 's' : ''}</span><span className="text-[18px] font-bold">{money(total)}</span></div>
          {kind === 'pos'
            ? (billing
              ? <div className="w-full py-2.5 rounded-[12px] text-center text-[13px] text-white/70 bg-white/5">Facture envoyée à {billing}…</div>
              : <button onClick={posBill} disabled={busy || count === 0} style={g.confirm} className="w-full py-2.5 rounded-[12px] font-semibold disabled:opacity-30 active:scale-[0.99]">Facturer le client le plus proche</button>)
            : kind === 'wholesale'
              ? <button onClick={wbuy} disabled={busy || count === 0 || total > wTill} style={g.confirm} className="w-full py-2.5 rounded-[12px] font-semibold disabled:opacity-30 active:scale-[0.99]">{total > wTill ? 'Caisse insuffisante' : 'Commander (caisse)'}</button>
              : <button onClick={buy} disabled={busy || count === 0} style={g.confirm} className="w-full py-2.5 rounded-[12px] font-semibold disabled:opacity-30 active:scale-[0.99]">Acheter</button>}
        </div>
      </div>
    </div>
  )
}

// ── 24/7 buy & wholesale ──────────────────────────────────────────────────────────
function BuyScreen({ g }: { g: Glass }) {
  const shop = useShop((s) => s.shop)
  return <><HeaderBar icon={<Store size={20} style={{ color: g.accent }} />} title={shop?.label || 'Boutique'} subtitle="24/7" /><CartGrid kind="buy" g={g} /></>
}
function WholesaleScreen({ g }: { g: Glass }) {
  const label = useShop((s) => s.wShopLabel)
  return <><HeaderBar icon={<Truck size={20} style={{ color: g.accent }} />} title="Grossiste" subtitle={`Réappro · ${label}`} /><CartGrid kind="wholesale" g={g} /></>
}

// ── Caisse point: Vendre (POS) + Argent (till) ─────────────────────────────────────
function CaisseScreen({ g }: { g: Glass }) {
  const shop = useShop((s) => s.shop)
  const can = useCan()
  const [tab, setTab] = useState<'vendre' | 'argent'>(can('pos') ? 'vendre' : 'argent')
  return (
    <>
      <HeaderBar icon={<Receipt size={20} style={{ color: g.accent }} />} title={shop?.label || 'Caisse'} subtitle="Caisse" />
      <div className="px-3 pt-3 flex gap-1.5">
        {([['vendre', 'Vendre', Receipt], ['argent', 'Argent', PiggyBank]] as const).map(([id, lbl, Icon]) => (
          <button key={id} onClick={() => setTab(id)} style={tab === id ? g.confirm : undefined}
            className={`flex-1 py-2 rounded-[10px] text-[13px] font-medium flex items-center justify-center gap-1.5 ${tab === id ? 'text-white' : 'text-white/55 bg-white/5'}`}>
            <Icon size={15} /> {lbl}
          </button>
        ))}
      </div>
      {tab === 'vendre'
        ? (can('pos') ? <CartGrid kind="pos" g={g} /> : <div className="flex-1 flex items-center justify-center text-white/40 text-[14px]">Vous n'avez pas la permission de vendre.</div>)
        : <div className="flex-1 overflow-y-auto no-scrollbar p-4"><CaisseArgent g={g} /></div>}
    </>
  )
}

function CaisseArgent({ g }: { g: Glass }) {
  const till = useShop((s) => s.till); const withdraw = useShop((s) => s.withdraw); const busy = useShop((s) => s.busy)
  const can = useCan(); const editable = can('withdraw')
  const [amt, setAmt] = useState('')
  return (
    <div className="rounded-[14px] p-5 border border-white/10" style={g.panel}>
      <div className="text-[12px] uppercase tracking-wide text-white/45">Caisse</div>
      <div className="text-[30px] font-bold mb-4">{money(till)}</div>
      {editable ? (
        <div className="flex items-end gap-2">
          <div className="flex-1">
            <div className="text-[11px] text-white/40 mb-1">Retirer vers la banque</div>
            <input value={amt} onChange={(e) => setAmt(e.target.value.replace(/[^0-9]/g, ''))} placeholder={String(till)}
              className="w-full bg-black/30 rounded-[8px] px-2 py-1.5 text-[14px] text-right outline-none border border-white/10 focus:border-white/30" />
          </div>
          <button onClick={() => { const n = parseInt(amt || String(till), 10); if (n > 0) { withdraw(n); setAmt('') } }} disabled={busy} style={g.confirm} className="px-4 py-1.5 rounded-[8px] text-[14px] font-medium active:scale-95">Retirer</button>
        </div>
      ) : <div className="text-[13px] text-white/40">Vous n'avez pas la permission de retirer.</div>}
    </div>
  )
}

// ── Stock point: retirer / déposer des items ───────────────────────────────────────
function StockRow({ category, label, sub, max, actionLabel, ActionIcon, onAction, enabled, g }: {
  category: string; label: string; sub: string; max: number; actionLabel: string
  ActionIcon: typeof Plus; onAction: (qty: number) => void; enabled: boolean; g: Glass
}) {
  const [q, setQ] = useState(1)
  const cap = Math.max(1, max)
  return (
    <div className="flex items-center gap-3 px-3 py-2.5 rounded-[12px] bg-white/[0.04] border border-white/10">
      <Badge category={category} size={36} />
      <div className="min-w-0 flex-1"><div className="text-[14px] truncate">{label}</div><div className="text-[12px] text-white/45">{sub}</div></div>
      {enabled && max > 0 && <>
        <Stepper qty={Math.min(q, cap)} onAdd={() => setQ((v) => Math.min(v + 1, cap))} onSub={() => setQ((v) => Math.max(1, v - 1))} canAdd={q < cap} />
        <button onClick={() => onAction(Math.min(q, cap))} style={g.confirm} className="px-2.5 py-1.5 rounded-[8px] text-[12px] font-medium flex items-center gap-1 active:scale-95">
          <ActionIcon size={13} /> {actionLabel}
        </button>
      </>}
    </div>
  )
}

function StockScreen({ g }: { g: Glass }) {
  const shop = useShop((s) => s.shop); const offers = useShop((s) => s.offers); const deposit = useShop((s) => s.deposit)
  const canManage = useShop((s) => s.canManage)
  const stockWithdraw = useShop((s) => s.stockWithdraw); const stockDeposit = useShop((s) => s.stockDeposit)
  return (
    <>
      <HeaderBar icon={<Boxes size={20} style={{ color: g.accent }} />} title={shop?.label || 'Stock'} subtitle={canManage ? 'Entrer / sortir des items' : 'Stock (lecture seule)'} />
      <div className="flex-1 flex min-h-0">
        <div className="flex-1 overflow-y-auto no-scrollbar p-4 border-r border-white/10">
          <div className="text-[12px] uppercase tracking-wide text-white/45 mb-2 flex items-center gap-2"><ArrowUpFromLine size={14} /> Sortir du stock</div>
          <div className="space-y-2">
            {offers.length === 0 && <div className="text-white/40 text-[14px] text-center py-8">Stock vide.</div>}
            {offers.map((o) => (
              <StockRow key={o.item} category={o.category} label={o.label} sub={`En stock : ${o.stock}`} max={o.stock} actionLabel="Sortir"
                ActionIcon={ArrowUpFromLine} onAction={(q) => stockWithdraw(o.item, q)} enabled={canManage} g={g} />
            ))}
          </div>
        </div>
        <div className="w-[380px] shrink-0 overflow-y-auto no-scrollbar p-4">
          <div className="text-[12px] uppercase tracking-wide text-white/45 mb-2 flex items-center gap-2"><ArrowDownToLine size={14} /> Déposer (vos items)</div>
          {!canManage && <div className="text-white/40 text-[13px] py-4">Permission requise pour modifier le stock.</div>}
          <div className="space-y-2">
            {canManage && deposit.length === 0 && <div className="text-white/40 text-[14px] text-center py-8">Vous ne portez aucun item vendable.</div>}
            {deposit.map((d) => (
              <StockRow key={d.item} category={d.category} label={d.label} sub={`Vous : ${d.carried}`} max={d.carried} actionLabel="Déposer"
                ActionIcon={ArrowDownToLine} onAction={(q) => stockDeposit(d.item, q)} enabled={canManage} g={g} />
            ))}
          </div>
        </div>
      </div>
    </>
  )
}

// ── Gestion point: Prix + Employés + Grades ────────────────────────────────────────
function PriceRow({ item, label, category, stock, price, editable, g }: {
  item: string; label: string; category: string; stock: number; price: number; editable: boolean; g: Glass
}) {
  const setPrice = useShop((s) => s.setPrice)
  const [val, setVal] = useState(String(price))
  useEffect(() => setVal(String(price)), [price])
  const dirty = String(price) !== val.trim() && val.trim() !== ''
  return (
    <div className="flex items-center gap-3 px-3 py-2.5 rounded-[12px] bg-white/[0.04] border border-white/10">
      <Badge category={category} size={36} />
      <div className="min-w-0 flex-1"><div className="text-[14px] truncate">{label}</div><div className="text-[12px] text-white/45">Stock {stock}</div></div>
      <div className="flex items-center gap-1.5">
        <span className="text-white/40 text-[14px]">$</span>
        <input value={val} disabled={!editable} onChange={(e) => setVal(e.target.value.replace(/[^0-9]/g, ''))}
          className="w-20 bg-black/30 rounded-[8px] px-2 py-1 text-[14px] text-right outline-none border border-white/10 focus:border-white/30 disabled:opacity-50" />
        {editable && <button onClick={() => dirty && setPrice(item, parseInt(val, 10))} disabled={!dirty} style={dirty ? g.confirm : undefined} className="px-3 py-1 rounded-[8px] text-[13px] disabled:opacity-30">OK</button>}
      </div>
    </div>
  )
}

function GradeEditor({ initialName, initialPerms, onSave, onCancel, g }: {
  initialName: string; initialPerms: string[]; onSave: (name: string, perms: string[]) => void; onCancel: () => void; g: Glass
}) {
  const permList = useShop((s) => s.permList)
  const [name, setName] = useState(initialName)
  const [perms, setPerms] = useState<string[]>(initialPerms)
  const toggle = (k: string) => setPerms((p) => (p.includes(k) ? p.filter((x) => x !== k) : [...p, k]))
  return (
    <div className="rounded-[12px] p-3 bg-white/[0.04] border border-white/15 space-y-3">
      <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Nom du grade"
        className="w-full bg-black/30 rounded-[8px] px-3 py-2 text-[14px] outline-none border border-white/10 focus:border-white/30" />
      <div className="grid grid-cols-2 gap-1.5">
        {permList.map((p) => {
          const on = perms.includes(p.key)
          return (
            <button key={p.key} onClick={() => toggle(p.key)}
              className={`flex items-center gap-2 px-2.5 py-2 rounded-[9px] text-left text-[12.5px] border ${on ? 'border-white/30 bg-white/10' : 'border-white/10 bg-black/20 text-white/60'}`}>
              <span className="w-4 h-4 rounded-[5px] flex items-center justify-center shrink-0" style={on ? g.bar : { background: 'rgba(255,255,255,0.1)' }}>{on && <span className="text-black text-[10px] font-bold">✓</span>}</span>
              {p.label}
            </button>
          )
        })}
      </div>
      <div className="flex gap-2">
        <button onClick={() => name.trim() && onSave(name.trim(), perms)} disabled={!name.trim()} style={g.confirm} className="flex-1 py-2 rounded-[10px] text-[14px] font-medium disabled:opacity-30">Enregistrer</button>
        <button onClick={onCancel} className="px-4 py-2 rounded-[10px] text-[14px] text-white/60 bg-white/5">Annuler</button>
      </div>
    </div>
  )
}

function GradesTab({ g }: { g: Glass }) {
  const grades = useShop((s) => s.grades); const permList = useShop((s) => s.permList)
  const gradeSave = useShop((s) => s.gradeSave); const gradeDelete = useShop((s) => s.gradeDelete)
  const can = useCan(); const editable = can('grades')
  const [editing, setEditing] = useState<number | 'new' | null>(null)
  const labelOf = (k: string) => permList.find((p) => p.key === k)?.label || k
  return (
    <div className="space-y-2.5">
      {grades.map((gr) => editing === gr.id ? (
        <GradeEditor key={gr.id} initialName={gr.name} initialPerms={gr.perms} g={g}
          onSave={(n, pm) => { gradeSave(n, pm, gr.id); setEditing(null) }} onCancel={() => setEditing(null)} />
      ) : (
        <div key={gr.id} className="rounded-[12px] p-3 bg-white/[0.04] border border-white/10">
          <div className="flex items-center gap-2">
            <div className="text-[14px] font-semibold flex-1 truncate">{gr.name}</div>
            {editable && <>
              <button onClick={() => setEditing(gr.id)} className="w-7 h-7 rounded-lg bg-white/10 flex items-center justify-center active:scale-90"><Pencil size={14} /></button>
              <button onClick={() => gradeDelete(gr.id)} className="w-7 h-7 rounded-lg bg-white/10 flex items-center justify-center active:scale-90 text-[#ff453a]"><Trash2 size={14} /></button>
            </>}
          </div>
          <div className="flex flex-wrap gap-1.5 mt-2">
            {gr.perms.length === 0 && <span className="text-[12px] text-white/35">Aucune permission</span>}
            {gr.perms.map((k) => <span key={k} className="text-[11px] px-2 py-0.5 rounded-full bg-white/10 text-white/75">{labelOf(k)}</span>)}
          </div>
        </div>
      ))}
      {editable && (editing === 'new'
        ? <GradeEditor initialName="" initialPerms={[]} g={g} onSave={(n, pm) => { gradeSave(n, pm); setEditing(null) }} onCancel={() => setEditing(null)} />
        : <button onClick={() => setEditing('new')} style={g.confirm} className="w-full py-2.5 rounded-[12px] text-[14px] font-medium flex items-center justify-center gap-2"><Plus size={16} /> Nouveau grade</button>)}
    </div>
  )
}

function EmployeesTab({ g }: { g: Glass }) {
  const employees = useShop((s) => s.employees); const grades = useShop((s) => s.grades)
  const recruit = useShop((s) => s.recruit); const fire = useShop((s) => s.fire); const setGrade = useShop((s) => s.setGrade)
  const can = useCan(); const editable = can('employees')
  const [rg, setRg] = useState<string>('')
  const gradeName = (id: number | null) => grades.find((x) => x.id === id)?.name || '—'
  return (
    <div className="space-y-3">
      {editable && (
        <div className="rounded-[12px] p-3 bg-white/[0.04] border border-white/10 flex items-center gap-2">
          <UserPlus size={18} className="text-white/60 shrink-0" />
          <select value={rg} onChange={(e) => setRg(e.target.value)} className="flex-1 bg-black/30 rounded-[8px] px-2 py-1.5 text-[13px] outline-none border border-white/10">
            <option value="">Grade…</option>
            {grades.map((gr) => <option key={gr.id} value={gr.id}>{gr.name}</option>)}
          </select>
          <button onClick={() => recruit(rg ? parseInt(rg, 10) : null)} style={g.confirm} className="px-3 py-1.5 rounded-[8px] text-[13px] font-medium">Recruter le + proche</button>
        </div>
      )}
      {employees.length === 0 && <div className="text-white/40 text-[14px] text-center py-8">Aucun employé.</div>}
      {employees.map((e) => (
        <div key={e.charid} className="flex items-center gap-3 px-3 py-2.5 rounded-[12px] bg-white/[0.04] border border-white/10">
          <div className="w-9 h-9 rounded-full bg-white/10 flex items-center justify-center shrink-0 text-[13px] font-semibold">{e.name.slice(0, 1)}</div>
          <div className="min-w-0 flex-1"><div className="text-[14px] truncate">{e.name}</div><div className="text-[12px] text-white/45">{gradeName(e.gradeId)}</div></div>
          {editable ? <>
            <select value={e.gradeId ?? ''} onChange={(ev) => setGrade(e.charid, ev.target.value ? parseInt(ev.target.value, 10) : null)} className="bg-black/30 rounded-[8px] px-2 py-1 text-[13px] outline-none border border-white/10">
              <option value="">—</option>
              {grades.map((gr) => <option key={gr.id} value={gr.id}>{gr.name}</option>)}
            </select>
            <button onClick={() => fire(e.charid)} className="w-7 h-7 rounded-lg bg-white/10 flex items-center justify-center active:scale-90 text-[#ff453a]"><Trash2 size={14} /></button>
          </> : <span className="text-[12px] text-white/45">{gradeName(e.gradeId)}</span>}
        </div>
      ))}
    </div>
  )
}

const GTABS = [
  { id: 'prix', label: 'Prix', icon: Tag },
  { id: 'employes', label: 'Employés', icon: Users },
  { id: 'grades', label: 'Grades', icon: ShieldCheck },
] as const

function GestionScreen({ g }: { g: Glass }) {
  const shop = useShop((s) => s.shop); const offers = useShop((s) => s.offers); const role = useShop((s) => s.role)
  const can = useCan()
  const [tab, setTab] = useState<(typeof GTABS)[number]['id']>('prix')
  return (
    <>
      <HeaderBar icon={<Briefcase size={20} style={{ color: g.accent }} />} title={shop?.label || 'Société'} subtitle={role === 'owner' ? 'Propriétaire' : 'Employé'} />
      <div className="px-3 pt-3 flex gap-1.5">
        {GTABS.map((t) => {
          const Icon = t.icon
          return (
            <button key={t.id} onClick={() => setTab(t.id)} style={tab === t.id ? g.confirm : undefined}
              className={`flex-1 py-2 rounded-[10px] text-[13px] font-medium flex items-center justify-center gap-1.5 ${tab === t.id ? 'text-white' : 'text-white/55 bg-white/5'}`}>
              <Icon size={15} /> {t.label}
            </button>
          )
        })}
      </div>
      <div className="flex-1 overflow-y-auto no-scrollbar p-4">
        {tab === 'prix' && (
          <div className="space-y-2">
            {offers.length === 0 && <div className="text-white/40 text-[14px] text-center py-10 leading-relaxed">Aucun stock.<br />Approvisionne au point <span className="text-white/70">Stock</span> ou chez le grossiste.</div>}
            {offers.map((o) => <PriceRow key={o.item} item={o.item} label={o.label} category={o.category} stock={o.stock} price={o.price} editable={can('prices')} g={g} />)}
          </div>
        )}
        {tab === 'employes' && <EmployeesTab g={g} />}
        {tab === 'grades' && <GradesTab g={g} />}
      </div>
    </>
  )
}

// ── Customer bill prompt ──────────────────────────────────────────────────────────
function BillPrompt() {
  const bill = useShop((s) => s.bill); const billPay = useShop((s) => s.billPay)
  const billDecline = useShop((s) => s.billDecline); const busy = useShop((s) => s.busy)
  const g = glass('#46d39a')
  if (!bill) return null
  return (
    <div className="fixed inset-0 flex items-center justify-center">
      <div className="w-[380px] rounded-[20px] p-5 border border-white/12" style={{ ...g.panel, animation: 'shop-in 200ms ease-out' }}>
        <div className="text-center">
          <div className="text-[12px] uppercase tracking-wide text-white/45">{bill.shopLabel}</div>
          <div className="text-[16px] font-semibold mt-0.5">Facture</div>
        </div>
        <div className="my-4 space-y-1.5 max-h-52 overflow-y-auto no-scrollbar">
          {bill.items.map((it, i) => (
            <div key={i} className="flex justify-between text-[14px]"><span className="text-white/80 truncate">{it.qty}× {it.label}</span><span className="tabular-nums">{money(it.price * it.qty)}</span></div>
          ))}
        </div>
        <div className="flex justify-between text-[18px] font-bold border-t border-white/10 pt-3"><span>Total</span><span>{money(bill.total)}</span></div>
        <div className="grid grid-cols-2 gap-2 mt-4">
          <button onClick={() => billPay('cash')} disabled={busy} style={g.confirm} className="py-2.5 rounded-[12px] font-semibold flex items-center justify-center gap-1.5 disabled:opacity-40"><Banknote size={16} /> Espèces</button>
          <button onClick={() => billPay('bank')} disabled={busy} style={g.confirm} className="py-2.5 rounded-[12px] font-semibold flex items-center justify-center gap-1.5 disabled:opacity-40"><Wallet size={16} /> Banque</button>
        </div>
        <button onClick={billDecline} className="w-full mt-2 py-2 rounded-[12px] text-[14px] text-white/60 bg-white/5">Refuser</button>
      </div>
      <Toast />
    </div>
  )
}

export default function App() {
  const open = useShop((s) => s.open)
  const screen = useShop((s) => s.screen)
  const shop = useShop((s) => s.shop)

  useNuiEvent<OpenData>('shop:open', (d) => useShop.getState().openShop(d))
  useNuiEvent<WholesaleData>('shop:wholesale', (d) => useShop.getState().openWholesale(d))
  useNuiEvent<CaisseData>('shop:caisse', (d) => useShop.getState().openCaisse(d))
  useNuiEvent<StockData>('shop:stock', (d) => useShop.getState().openStock(d))
  useNuiEvent<GestionData>('shop:gestion', (d) => useShop.getState().openGestion(d))
  useNuiEvent<BillData>('shop:bill', (d) => useShop.getState().openBill(d))
  useNuiEvent<{ ok?: boolean }>('shop:posResult', (d) => useShop.getState().handlePosResult(d))
  useNuiEvent('shop:close', () => useShop.getState().close())

  useEffect(() => {
    wireCloseKeys()
    if (!inGame()) useShop.getState().openShop(MOCK_BUY)
  }, [])

  if (!open) return inGame() ? null : <DevBar />
  if (screen === 'bill') return (<>{!inGame() && <DevBar />}<BillPrompt /></>)

  const g = glass(shop?.accent || '#46d39a')
  return (
    <div className="fixed inset-0 flex items-center justify-center">
      {!inGame() && <DevBar />}
      <div className="relative w-[min(960px,93vw)] h-[min(620px,88vh)] rounded-[22px] overflow-hidden flex flex-col border border-white/12" style={{ ...g.panel, animation: 'shop-in 220ms ease-out' }}>
        {screen === 'wholesale' ? <WholesaleScreen g={g} />
          : screen === 'caisse' ? <CaisseScreen g={g} />
          : screen === 'stock' ? <StockScreen g={g} />
          : screen === 'gestion' ? <GestionScreen g={g} />
          : <BuyScreen g={g} />}
        <Toast />
      </div>
    </div>
  )
}

function DevBar() {
  if (inGame()) return null
  const s = useShop.getState()
  return (
    <div className="fixed top-2 left-2 z-50 flex gap-2 text-[12px]">
      <button className="px-2 py-1 rounded bg-white/15" onClick={() => s.openShop(MOCK_BUY)}>buy</button>
      <button className="px-2 py-1 rounded bg-white/15" onClick={() => s.openCaisse(MOCK_CAISSE)}>caisse</button>
      <button className="px-2 py-1 rounded bg-white/15" onClick={() => s.openStock(MOCK_STOCK)}>stock</button>
      <button className="px-2 py-1 rounded bg-white/15" onClick={() => s.openGestion(MOCK_GESTION)}>gestion</button>
      <button className="px-2 py-1 rounded bg-white/15" onClick={() => s.openBill(MOCK_BILL)}>bill</button>
      <button className="px-2 py-1 rounded bg-white/15" onClick={() => s.openWholesale(MOCK_WHOLESALE)}>wholesale</button>
    </div>
  )
}
