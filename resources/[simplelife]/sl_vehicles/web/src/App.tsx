import { useEffect, useMemo, useState } from 'react'
import {
  Car, X, Search, Gauge, Package, Users, Tag, Wallet, Inbox, Truck, Plus, Minus,
  Trash2, Check, Phone, Star, Eye, EyeOff, ShieldCheck, BadgeDollarSign,
} from 'lucide-react'
import { useStore } from './store'
import { useNuiEvent } from './lib/nui'
import { fetchNui, inGame } from './lib/fetchNui'
import { glass } from './lib/glass'
import { cn, money } from './lib/cn'
import { PERM_LABELS, type VenteData, type GestionData, type BillData, type ImpoundData, type StockItem, type Grade } from './types'

// ── shared bits ──────────────────────────────────────────────────────────────────
function Btn({ children, onClick, g, kind = 'ghost', className, disabled }: any) {
  const style = kind === 'confirm' ? g.confirm : kind === 'panel' ? g.selected : undefined
  return (
    <button
      disabled={disabled}
      onClick={onClick}
      style={style}
      className={cn(
        'rounded-xl px-3.5 py-2 text-sm font-medium transition active:scale-[0.97] disabled:opacity-40',
        kind === 'ghost' && 'bg-white/5 hover:bg-white/10 border border-white/10',
        className,
      )}
    >
      {children}
    </button>
  )
}

function StatBar({ label, value, g }: { label: string; value: number; g: any }) {
  return (
    <div className="flex items-center gap-2">
      <span className="w-16 text-[11px] uppercase tracking-wide text-white/55">{label}</span>
      <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10">
        <div className="h-full rounded-full" style={{ width: `${Math.max(3, Math.min(100, value))}%`, ...g.bar }} />
      </div>
    </div>
  )
}

function Header({ title, sub, g, onClose }: any) {
  return (
    <div className="flex items-center justify-between border-b border-white/10 px-6 py-4">
      <div className="flex items-center gap-3">
        <div className="grid h-10 w-10 place-items-center rounded-xl" style={g.selected}>
          <Car size={20} style={{ color: g.accent }} />
        </div>
        <div>
          <div className="text-lg font-semibold leading-tight">{title}</div>
          {sub && <div className="text-xs text-white/50">{sub}</div>}
        </div>
      </div>
      <button onClick={onClose} className="grid h-9 w-9 place-items-center rounded-full bg-white/5 hover:bg-white/15">
        <X size={18} />
      </button>
    </div>
  )
}

// ── VENTE (catalogue + POS) ────────────────────────────────────────────────────────
function VenteScreen({ data }: { data: VenteData }) {
  const g = glass(data.dealer.accent)
  const call = useStore((s) => s.call)
  const close = useStore((s) => s.close)
  const posResult = useStore((s) => s.posResult)
  const setPosResult = useStore((s) => s.setPosResult)
  const [cat, setCat] = useState('all')
  const [q, setQ] = useState('')
  const [sel, setSel] = useState<StockItem | null>(null)
  const [pending, setPending] = useState(false)

  const cats = ['all', ...data.dealer.categories]
  const list = useMemo(
    () => data.stock.filter((s) =>
      (cat === 'all' || s.category === cat) &&
      (q === '' || (s.label + ' ' + (s.brand || '')).toLowerCase().includes(q.toLowerCase()))),
    [data.stock, cat, q],
  )

  useEffect(() => {
    if (posResult) {
      setPending(false)
      const t = setTimeout(() => setPosResult(null), 2800)
      return () => clearTimeout(t)
    }
  }, [posResult, setPosResult])

  const bill = async () => {
    if (!sel) return
    setPending(true)
    const res: any = await call('vente:bill', { model: sel.model })
    if (!res?.ok) { setPending(false); setPosResult({ ok: false, reason: res?.reason }) }
  }

  return (
    <div className="veh-in flex h-[78vh] w-[1040px] flex-col overflow-hidden rounded-3xl text-white" style={g.panel}>
      <Header title={data.dealer.label} sub="Espace vente — facturer un client" g={g} onClose={close} />
      <div className="flex min-h-0 flex-1">
        {/* catalogue */}
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="flex items-center gap-2 px-6 py-3">
            <div className="flex items-center gap-2 rounded-xl bg-white/5 px-3 py-2">
              <Search size={15} className="text-white/40" />
              <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Rechercher…"
                className="w-44 bg-transparent text-sm outline-none placeholder:text-white/30" />
            </div>
            <div className="flex flex-wrap gap-1.5">
              {cats.map((c) => (
                <button key={c} onClick={() => setCat(c)}
                  style={cat === c ? g.selected : undefined}
                  className={cn('rounded-lg px-3 py-1.5 text-xs', cat !== c && 'bg-white/5 hover:bg-white/10')}>
                  {c === 'all' ? 'Tous' : data.dealer.catNames[c] || c}
                </button>
              ))}
            </div>
          </div>
          <div className="no-scrollbar grid grid-cols-3 content-start gap-3 overflow-y-auto px-6 pb-6">
            {list.map((s) => (
              <button key={s.model} onClick={() => setSel(s)}
                style={sel?.model === s.model ? g.selected : undefined}
                className={cn('rounded-2xl p-4 text-left transition', sel?.model !== s.model && 'bg-white/5 hover:bg-white/[0.08] border border-white/10')}>
                <div className="flex items-center justify-between">
                  <span className="text-[10px] uppercase tracking-wider text-white/40">{s.brand}</span>
                  <span className={cn('rounded-md px-1.5 py-0.5 text-[10px]', s.qty > 0 ? 'bg-emerald-400/15 text-emerald-300' : 'bg-white/10 text-white/40')}>
                    {s.qty > 0 ? `${s.qty} en stock` : 'rupture'}
                  </span>
                </div>
                <div className="mt-1 truncate text-[15px] font-semibold">{s.label}</div>
                <div className="mt-1 text-lg font-bold" style={{ color: g.accent }}>{money(s.price)}</div>
              </button>
            ))}
            {list.length === 0 && <div className="col-span-3 py-16 text-center text-white/40">Aucun véhicule.</div>}
          </div>
        </div>
        {/* detail */}
        <div className="w-[330px] shrink-0 border-l border-white/10 p-5">
          {!sel ? (
            <div className="grid h-full place-items-center text-center text-white/35">
              <div><Car size={40} className="mx-auto mb-2 opacity-50" />Sélectionne un modèle</div>
            </div>
          ) : (
            <div className="flex h-full flex-col">
              <div className="text-[11px] uppercase tracking-wider text-white/40">{sel.brand}</div>
              <div className="text-2xl font-bold">{sel.label}</div>
              <div className="mt-1 text-3xl font-extrabold" style={{ color: g.accent }}>{money(sel.price)}</div>
              <div className="mt-5 space-y-2.5">
                <StatBar label="Vitesse" value={sel.stats?.speed ?? 0} g={g} />
                <StatBar label="Accél." value={sel.stats?.accel ?? 0} g={g} />
                <StatBar label="Freins" value={sel.stats?.braking ?? 0} g={g} />
                <StatBar label="Tenue" value={sel.stats?.handling ?? 0} g={g} />
              </div>
              <div className="mt-4 flex gap-4 text-sm text-white/60">
                <span className="flex items-center gap-1"><Users size={14} /> {sel.seats ?? '—'} places</span>
                <span className="flex items-center gap-1"><Package size={14} /> {Math.round((sel.trunk ?? 0) / 1000)} kg</span>
              </div>
              <div className="mt-auto">
                {pending ? (
                  <div className="rounded-xl bg-white/5 px-4 py-3 text-center text-sm text-white/70">Facture envoyée au client…</div>
                ) : (
                  <Btn g={g} kind="confirm" disabled={sel.qty <= 0} onClick={bill} className="w-full">
                    Facturer le client le plus proche
                  </Btn>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
      {posResult && (
        <div className={cn('absolute bottom-5 left-1/2 -translate-x-1/2 rounded-xl px-5 py-2.5 text-sm font-medium',
          posResult.ok ? 'bg-emerald-500/90' : 'bg-red-500/90')}>
          {posResult.ok ? `Vente conclue ✓ (+${money(posResult.commission || 0)} commission)` : 'Vente échouée / refusée'}
        </div>
      )}
    </div>
  )
}

// ── GESTION (tabs) ──────────────────────────────────────────────────────────────────
const TABS = [
  { id: 'stock', label: 'Stock & Import', icon: Truck, perm: 'import' },
  { id: 'prix', label: 'Prix & Expo', icon: Tag, perm: 'prix' },
  { id: 'emp', label: 'Employés', icon: Users, perm: 'employes' },
  { id: 'grades', label: 'Grades', icon: ShieldCheck, perm: 'grades' },
  { id: 'caisse', label: 'Caisse', icon: Wallet, perm: 'caisse' },
  { id: 'leads', label: 'Demandes', icon: Inbox, perm: 'leads' },
]

function GestionScreen({ data }: { data: GestionData }) {
  const g = glass(data.dealer.accent)
  const close = useStore((s) => s.close)
  const call = useStore((s) => s.call)
  const setGestion = useStore((s) => s.setGestion)
  const has = (p: string) => data.perms.includes(p)
  const avail = TABS.filter((t) => has(t.perm))
  const [tab, setTab] = useState(avail[0]?.id || 'stock')
  const merge = (patch: Partial<GestionData>) => setGestion({ ...data, ...patch })

  return (
    <div className="veh-in flex h-[80vh] w-[1080px] overflow-hidden rounded-3xl text-white" style={g.panel}>
      {/* rail */}
      <div className="flex w-[220px] shrink-0 flex-col border-r border-white/10 p-3">
        <div className="px-3 py-3">
          <div className="text-base font-semibold">{data.dealer.label}</div>
          <div className="text-xs text-white/45">Gestion · {data.role === 'owner' ? 'Propriétaire' : 'Employé'}</div>
        </div>
        <div className="mt-1 space-y-1">
          {avail.map((t) => {
            const I = t.icon
            return (
              <button key={t.id} onClick={() => setTab(t.id)} style={tab === t.id ? g.selected : undefined}
                className={cn('flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm', tab !== t.id && 'hover:bg-white/5')}>
                <I size={17} style={{ color: tab === t.id ? g.accent : undefined }} /> {t.label}
              </button>
            )
          })}
        </div>
        <div className="mt-auto rounded-xl bg-white/5 px-3 py-2.5">
          <div className="text-[11px] uppercase tracking-wide text-white/40">Caisse</div>
          <div className="text-lg font-bold" style={{ color: g.accent }}>{money(data.till)}</div>
        </div>
        <button onClick={close} className="mt-3 flex items-center justify-center gap-2 rounded-xl bg-white/5 py-2 text-sm hover:bg-white/10">
          <X size={16} /> Fermer
        </button>
      </div>
      {/* content */}
      <div className="min-w-0 flex-1 overflow-hidden p-6">
        {tab === 'stock' && <StockTab data={data} g={g} call={call} merge={merge} />}
        {tab === 'prix' && <PrixTab data={data} g={g} call={call} merge={merge} />}
        {tab === 'emp' && <EmpTab data={data} g={g} call={call} merge={merge} />}
        {tab === 'grades' && <GradesTab data={data} g={g} call={call} merge={merge} />}
        {tab === 'caisse' && <CaisseTab data={data} g={g} call={call} merge={merge} />}
        {tab === 'leads' && <LeadsTab data={data} g={g} call={call} merge={merge} />}
      </div>
    </div>
  )
}

function StockTab({ data, g, call, merge }: any) {
  const [cart, setCart] = useState<Record<string, number>>({})
  const [priority, setPriority] = useState(false)
  const add = (m: string, d: number) => setCart((c) => { const n = Math.max(0, (c[m] || 0) + d); const x = { ...c }; if (n === 0) delete x[m]; else x[m] = n; return x })
  const units = Object.values(cart).reduce((a, b) => a + b, 0)
  const cost = data.stock.reduce((sum: number, s: StockItem) => sum + (cart[s.model] || 0) * s.import, 0) + (priority ? data.import.fee : 0)

  const order = async () => {
    const orders = Object.entries(cart).map(([model, qty]) => ({ model, qty }))
    if (!orders.length) return
    const res: any = await call('import:order', { orders, priority })
    if (res?.ok) { merge({ orders: res.orders, till: res.till }); setCart({}) }
    else {
      const why: Record<string, string> = {
        TILL: 'caisse insuffisante (dépose de l\'argent dans l\'onglet Caisse)', NO_PERM: 'permission « import » manquante',
        NOT_STAFF: 'pas employé de cette concession', TOO_FAR: 'trop loin du terminal', TOO_MANY: 'max 12 véhicules par commande',
        EMPTY: 'panier vide', CLOSED: 'concession sans propriétaire',
      }
      alert('Commande impossible : ' + (why[res?.reason] || res?.reason || 'erreur'))
    }
  }

  return (
    <div className="flex h-full gap-5">
      <div className="flex min-w-0 flex-1 flex-col">
        <div className="mb-2 text-sm font-semibold text-white/70">Commander à l'import</div>
        <div className="no-scrollbar flex-1 space-y-1.5 overflow-y-auto pr-1">
          {data.stock.map((s: StockItem) => (
            <div key={s.model} className="flex items-center gap-3 rounded-xl bg-white/5 px-3 py-2">
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-medium">{s.label} <span className="text-white/35">· {s.brand}</span></div>
                <div className="text-xs text-white/45">Import {money(s.import)} · stock {s.qty}</div>
              </div>
              <button onClick={() => add(s.model, -1)} className="grid h-7 w-7 place-items-center rounded-lg bg-white/5 hover:bg-white/10"><Minus size={14} /></button>
              <span className="w-6 text-center text-sm">{cart[s.model] || 0}</span>
              <button onClick={() => add(s.model, 1)} className="grid h-7 w-7 place-items-center rounded-lg bg-white/5 hover:bg-white/10"><Plus size={14} /></button>
            </div>
          ))}
        </div>
        <div className="mt-3 flex items-center gap-3">
          <label className="flex items-center gap-2 text-sm text-white/70">
            <input type="checkbox" checked={priority} onChange={(e) => setPriority(e.target.checked)} />
            Livraison prioritaire (+{money(data.import.fee)}, {Math.round(data.import.priority / 60)} min)
          </label>
          <div className="ml-auto text-sm text-white/60">{units} véh. · <b style={{ color: g.accent }}>{money(cost)}</b></div>
          <Btn g={g} kind="confirm" disabled={units === 0} onClick={order}>Commander</Btn>
        </div>
      </div>
      <div className="w-[300px] shrink-0 border-l border-white/10 pl-5">
        <div className="mb-2 text-sm font-semibold text-white/70">Commandes en cours</div>
        <div className="no-scrollbar space-y-1.5 overflow-y-auto" style={{ maxHeight: '100%' }}>
          {(data.orders || []).map((o: any) => (
            <div key={o.id} className="rounded-xl bg-white/5 px-3 py-2 text-sm">
              <div className="flex justify-between"><span>{o.label} ×{o.remaining}</span>
                {o.priority && <Star size={13} className="text-amber-300" />}</div>
              <div className="text-xs text-white/45">{o.status === 'ready' ? 'Prêt au port' : `Prêt dans ${Math.ceil(o.eta / 60)} min`}</div>
            </div>
          ))}
          {(!data.orders || data.orders.length === 0) && <div className="py-8 text-center text-sm text-white/35">Aucune commande.</div>}
        </div>
      </div>
    </div>
  )
}

function PrixTab({ data, g, call, merge }: any) {
  const [draft, setDraft] = useState<Record<string, string>>({})
  const setPrice = async (m: string) => {
    const price = parseInt(draft[m] || '0', 10)
    if (!price) return
    const res: any = await call('manage:setPrice', { model: m, price })
    if (res?.ok) merge({ stock: res.stock })
    else if (res?.reason === 'MARGIN') alert(`Prix hors marge (${money(res.floor)} – ${money(res.ceil)})`)
  }
  const expo = async (m: string, display: boolean) => {
    const res: any = await call('expo:set', { model: m, display })
    if (res?.ok) merge({ stock: res.stock })
  }
  return (
    <div className="flex h-full flex-col">
      <div className="mb-2 text-sm font-semibold text-white/70">Prix de vente (marge {data.margin.min}–{data.margin.max}%) & exposition</div>
      <div className="no-scrollbar flex-1 space-y-1.5 overflow-y-auto pr-1">
        {data.stock.map((s: StockItem) => (
          <div key={s.model} className="flex items-center gap-3 rounded-xl bg-white/5 px-3 py-2">
            <div className="min-w-0 flex-1">
              <div className="truncate text-sm font-medium">{s.label}</div>
              <div className="text-xs text-white/45">Coût {money(s.import)} · actuel {money(s.price)}</div>
            </div>
            <input defaultValue={s.price} onChange={(e) => setDraft((d) => ({ ...d, [s.model]: e.target.value }))}
              className="w-24 rounded-lg bg-black/30 px-2 py-1 text-right text-sm outline-none" />
            <Btn g={g} onClick={() => setPrice(s.model)}><Check size={14} /></Btn>
            <button onClick={() => expo(s.model, !s.display)} title="Exposer dans le showroom"
              className={cn('grid h-8 w-8 place-items-center rounded-lg', s.display ? 'bg-emerald-400/20 text-emerald-300' : 'bg-white/5 text-white/40')}>
              {s.display ? <Eye size={15} /> : <EyeOff size={15} />}
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}

function EmpTab({ data, g, call, merge }: any) {
  const recruit = async () => { const r: any = await call('employees:recruit', {}); if (r?.ok) merge({ employees: r.employees }) }
  const setGrade = async (charid: number, gradeId: number) => { const r: any = await call('employees:setGrade', { charid, gradeId }); if (r?.ok) merge({ employees: r.employees }) }
  const fire = async (charid: number) => { const r: any = await call('employees:fire', { charid }); if (r?.ok) merge({ employees: r.employees }) }
  return (
    <div className="flex h-full flex-col">
      <div className="mb-2 flex items-center justify-between">
        <div className="text-sm font-semibold text-white/70">Employés ({data.employees.length})</div>
        <Btn g={g} kind="confirm" onClick={recruit}><Plus size={14} className="mr-1 inline" />Recruter le + proche</Btn>
      </div>
      <div className="no-scrollbar flex-1 space-y-1.5 overflow-y-auto pr-1">
        {data.employees.map((e: any) => (
          <div key={e.charid} className="flex items-center gap-3 rounded-xl bg-white/5 px-3 py-2">
            <div className="min-w-0 flex-1 truncate text-sm font-medium">{e.name}</div>
            <select value={e.gradeId ?? ''} onChange={(ev) => setGrade(e.charid, parseInt(ev.target.value, 10))}
              className="rounded-lg bg-black/30 px-2 py-1 text-sm outline-none">
              <option value="">— sans grade —</option>
              {data.grades.map((gr: Grade) => <option key={gr.id} value={gr.id}>{gr.name}</option>)}
            </select>
            <button onClick={() => fire(e.charid)} className="grid h-8 w-8 place-items-center rounded-lg bg-red-500/15 text-red-300 hover:bg-red-500/25"><Trash2 size={15} /></button>
          </div>
        ))}
        {data.employees.length === 0 && <div className="py-8 text-center text-sm text-white/35">Aucun employé.</div>}
      </div>
    </div>
  )
}

function GradesTab({ data, g, call, merge }: any) {
  const empty = { name: '', perms: [] as string[], commission: data.import ? 5 : 5, salary: 0 }
  const [edit, setEdit] = useState<any>(null)
  const start = (gr?: Grade) => setEdit(gr ? { ...gr } : { ...empty })
  const togglePerm = (p: string) => setEdit((e: any) => ({ ...e, perms: e.perms.includes(p) ? e.perms.filter((x: string) => x !== p) : [...e.perms, p] }))
  const save = async () => {
    const payload = { name: edit.name, perms: edit.perms, commission: edit.commission, salary: edit.salary }
    const res: any = edit.id ? await call('grades:update', { gradeId: edit.id, ...payload }) : await call('grades:create', payload)
    if (res?.ok) { merge({ grades: res.grades }); setEdit(null) }
  }
  const del = async (id: number) => { const r: any = await call('grades:delete', { gradeId: id }); if (r?.ok) merge({ grades: r.grades, employees: r.employees }) }

  return (
    <div className="flex h-full gap-5">
      <div className="flex w-[300px] shrink-0 flex-col border-r border-white/10 pr-5">
        <div className="mb-2 flex items-center justify-between">
          <div className="text-sm font-semibold text-white/70">Grades</div>
          <Btn g={g} onClick={() => start()}><Plus size={14} /></Btn>
        </div>
        <div className="no-scrollbar flex-1 space-y-1.5 overflow-y-auto">
          {data.grades.map((gr: Grade) => (
            <div key={gr.id} className="flex items-center gap-2 rounded-xl bg-white/5 px-3 py-2">
              <button onClick={() => start(gr)} className="min-w-0 flex-1 text-left">
                <div className="truncate text-sm font-medium">{gr.name}</div>
                <div className="text-xs text-white/45">{gr.commission}% comm · {money(gr.salary)}/paie</div>
              </button>
              <button onClick={() => del(gr.id)} className="grid h-7 w-7 place-items-center rounded-lg bg-red-500/15 text-red-300"><Trash2 size={14} /></button>
            </div>
          ))}
        </div>
      </div>
      <div className="min-w-0 flex-1">
        {!edit ? (
          <div className="grid h-full place-items-center text-center text-white/35">Choisis ou crée un grade</div>
        ) : (
          <div className="flex h-full flex-col">
            <input value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} placeholder="Nom du grade"
              className="rounded-xl bg-black/30 px-3 py-2.5 text-lg font-semibold outline-none" />
            <div className="mt-4 grid grid-cols-2 gap-2">
              {data.permList.map((p: string) => (
                <button key={p} onClick={() => togglePerm(p)} style={edit.perms.includes(p) ? g.selected : undefined}
                  className={cn('flex items-center gap-2 rounded-xl px-3 py-2 text-sm', !edit.perms.includes(p) && 'bg-white/5')}>
                  <span className={cn('grid h-4 w-4 place-items-center rounded', edit.perms.includes(p) ? 'bg-white/30' : 'bg-white/10')}>
                    {edit.perms.includes(p) && <Check size={12} />}
                  </span>
                  {PERM_LABELS[p] || p}
                </button>
              ))}
            </div>
            <div className="mt-4 flex gap-4">
              <label className="flex-1 text-sm text-white/60">Commission (%)
                <input type="number" value={edit.commission} onChange={(e) => setEdit({ ...edit, commission: parseInt(e.target.value || '0', 10) })}
                  className="mt-1 w-full rounded-lg bg-black/30 px-2 py-1.5 text-white outline-none" /></label>
              <label className="flex-1 text-sm text-white/60">Salaire / paie ($)
                <input type="number" value={edit.salary} onChange={(e) => setEdit({ ...edit, salary: parseInt(e.target.value || '0', 10) })}
                  className="mt-1 w-full rounded-lg bg-black/30 px-2 py-1.5 text-white outline-none" /></label>
            </div>
            <div className="mt-auto flex gap-2">
              <Btn g={g} onClick={() => setEdit(null)} className="flex-1">Annuler</Btn>
              <Btn g={g} kind="confirm" onClick={save} disabled={!edit.name} className="flex-1">Enregistrer</Btn>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function CaisseTab({ data, g, call, merge }: any) {
  const [wAmt, setWAmt] = useState('')
  const [dAmt, setDAmt] = useState('')
  const [acct, setAcct] = useState('bank')
  const withdraw = async () => {
    const amount = parseInt(wAmt || '0', 10); if (!amount) return
    const res: any = await call('manage:withdraw', { amount })
    if (res?.ok) { merge({ till: res.till }); setWAmt('') }
    else alert('Retrait impossible (' + (res?.reason || '?') + ')')
  }
  const deposit = async () => {
    const amount = parseInt(dAmt || '0', 10); if (!amount) return
    const res: any = await call('manage:deposit', { amount, account: acct })
    if (res?.ok) { merge({ till: res.till }); setDAmt('') }
    else alert('Dépôt impossible (' + (res?.reason === 'FUNDS' ? 'fonds insuffisants' : res?.reason || '?') + ')')
  }
  return (
    <div className="mx-auto max-w-md pt-6">
      <div className="rounded-2xl p-6 text-center" style={g.selected}>
        <div className="text-xs uppercase tracking-wide text-white/50">Caisse de la société</div>
        <div className="mt-1 text-4xl font-extrabold" style={{ color: g.accent }}>{money(data.till)}</div>
      </div>
      <div className="mt-5">
        <div className="mb-2 flex items-center gap-2 text-sm text-white/70"><BadgeDollarSign size={16} /> Déposer dans la caisse</div>
        <div className="flex gap-2">
          <input value={dAmt} onChange={(e) => setDAmt(e.target.value)} placeholder="Montant"
            className="flex-1 rounded-xl bg-black/30 px-3 py-2.5 outline-none" />
          <select value={acct} onChange={(e) => setAcct(e.target.value)} className="rounded-xl bg-black/40 px-2 py-2.5 text-sm outline-none">
            <option value="bank">Banque</option>
            <option value="cash">Espèces</option>
          </select>
          <Btn g={g} kind="confirm" onClick={deposit}>Déposer</Btn>
        </div>
        <div className="mt-1 text-xs text-white/40">Finance les imports de la concession (la caisse paie le stock).</div>
      </div>
      <div className="mt-5">
        <div className="mb-2 flex items-center gap-2 text-sm text-white/70"><BadgeDollarSign size={16} /> Retirer vers ma banque</div>
        <div className="flex gap-2">
          <input value={wAmt} onChange={(e) => setWAmt(e.target.value)} placeholder="Montant"
            className="flex-1 rounded-xl bg-black/30 px-3 py-2.5 outline-none" />
          <Btn g={g} kind="confirm" onClick={withdraw}>Retirer</Btn>
        </div>
        <div className="mt-2 text-xs text-white/40">Les salaires sont prélevés automatiquement sur la caisse.</div>
      </div>
    </div>
  )
}

function LeadsTab({ data, g, call, merge }: any) {
  const handle = async (leadId: number) => { const r: any = await call('leads:handle', { leadId }); if (r?.ok) merge({ leads: r.leads }) }
  const callClient = async (leadId: number) => { const r: any = await call('leads:call', { leadId }); if (r?.ok) alert('Numéro du client : ' + r.number) }
  return (
    <div className="flex h-full flex-col">
      <div className="mb-2 text-sm font-semibold text-white/70">Demandes de contact ({data.leads.length})</div>
      <div className="no-scrollbar flex-1 space-y-2 overflow-y-auto pr-1">
        {data.leads.map((l: any) => (
          <div key={l.id} className="rounded-xl bg-white/5 px-4 py-3">
            <div className="flex items-center justify-between">
              <div className="font-medium">{l.name} {l.number && <span className="text-white/45">· {l.number}</span>}</div>
              <div className="flex gap-1.5">
                {l.number && <button onClick={() => callClient(l.id)} className="grid h-8 w-8 place-items-center rounded-lg bg-emerald-400/15 text-emerald-300"><Phone size={15} /></button>}
                <button onClick={() => handle(l.id)} className="grid h-8 w-8 place-items-center rounded-lg bg-white/5"><Check size={15} /></button>
              </div>
            </div>
            {l.subject && <div className="mt-1 text-sm text-white/70">{l.subject}</div>}
            {l.message && <div className="mt-0.5 text-sm text-white/50">{l.message}</div>}
          </div>
        ))}
        {data.leads.length === 0 && <div className="py-10 text-center text-sm text-white/35">Aucune demande.</div>}
      </div>
    </div>
  )
}

// ── BILL (customer) ──────────────────────────────────────────────────────────────────
function BillPrompt({ data }: { data: BillData }) {
  const g = glass('#3ba9e0')
  const close = useStore((s) => s.close)
  const call = useStore((s) => s.call)
  const pay = async (account: string) => {
    const res: any = await call('bill:pay', { billId: data.billId, account })
    if (res?.ok) close()
    else alert('Paiement impossible (' + (res?.reason || '?') + ')')
  }
  const decline = async () => { await call('bill:decline', { billId: data.billId }); close() }
  return (
    <div className="veh-in w-[420px] overflow-hidden rounded-3xl text-white" style={g.panel}>
      <div className="px-6 pt-6 text-center">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl" style={g.selected}><Car size={26} style={{ color: g.accent }} /></div>
        <div className="mt-3 text-xs uppercase tracking-wide text-white/45">{data.dealerLabel}</div>
        <div className="text-2xl font-bold">{data.label}</div>
        {data.brand && <div className="text-sm text-white/50">{data.brand}</div>}
        <div className="mt-2 text-4xl font-extrabold" style={{ color: g.accent }}>{money(data.price)}</div>
      </div>
      <div className="grid grid-cols-2 gap-2 p-5">
        <Btn g={g} kind="confirm" onClick={() => pay('cash')}>Payer espèces</Btn>
        <Btn g={g} kind="confirm" onClick={() => pay('bank')}>Payer banque</Btn>
        <button onClick={decline} className="col-span-2 rounded-xl bg-white/5 py-2.5 text-sm text-white/60 hover:bg-white/10">Refuser</button>
      </div>
    </div>
  )
}

// ── IMPOUND ──────────────────────────────────────────────────────────────────────────
function ImpoundScreen({ data }: { data: ImpoundData }) {
  const g = glass(data.lot.accent)
  const close = useStore((s) => s.close)
  const call = useStore((s) => s.call)
  const setImpound = useStore((s) => s.setImpound)
  const retrieve = async (dbId: number, account: string) => {
    const res: any = await call('impound:retrieve', { lotId: data.lot.id, dbId, account })
    if (res?.ok) {
      const left = data.vehicles.filter((v) => v.id !== dbId)
      setImpound({ ...data, vehicles: left, balances: res.balances })
      if (left.length === 0) close()
    } else alert('Échec (' + (res?.reason || '?') + ')')
  }
  return (
    <div className="veh-in flex h-[70vh] w-[560px] flex-col overflow-hidden rounded-3xl text-white" style={g.panel}>
      <Header title={data.lot.label} sub={`Récupération — frais ${money(data.fee)} / véhicule`} g={g} onClose={close} />
      <div className="no-scrollbar flex-1 space-y-2 overflow-y-auto p-5">
        {data.vehicles.map((v) => (
          <div key={v.id} className="flex items-center gap-3 rounded-xl bg-white/5 px-4 py-3">
            <div className="min-w-0 flex-1">
              <div className="truncate font-medium">{v.label} <span className="text-white/40">· {v.plate}</span></div>
              <div className="text-xs text-white/45">Carburant {v.fuel}% · moteur {Math.round(v.engine / 10)}%</div>
            </div>
            <Btn g={g} onClick={() => retrieve(v.id, 'cash')}>Espèces</Btn>
            <Btn g={g} kind="confirm" onClick={() => retrieve(v.id, 'bank')}>Banque</Btn>
          </div>
        ))}
        {data.vehicles.length === 0 && <div className="py-16 text-center text-white/40">Aucun véhicule en fourrière.</div>}
      </div>
    </div>
  )
}

// ── root ──────────────────────────────────────────────────────────────────────────────
export default function App() {
  const { screen, vente, gestion, bill, impound, openVente, openGestion, openBill, openImpound, setPosResult, close } = useStore()

  useNuiEvent<VenteData>('open:vente', openVente)
  useNuiEvent<GestionData>('open:gestion', openGestion)
  useNuiEvent<BillData>('bill', openBill)
  useNuiEvent<ImpoundData>('open:impound', openImpound)
  useNuiEvent<any>('posResult', (r) => setPosResult(r))
  useNuiEvent('close', () => useStore.setState({ screen: 'none' }))

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && screen !== 'bill') close() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [screen, close])

  // browser dev preview
  useEffect(() => {
    if (inGame()) return
    window.postMessage({ action: 'open:vente', data: DEV_VENTE }, '*')
  }, [])

  if (screen === 'none') return null
  return (
    <div className="fixed inset-0 grid place-items-center" onContextMenu={(e) => e.preventDefault()}>
      {screen === 'vente' && vente && <VenteScreen data={vente} />}
      {screen === 'gestion' && gestion && <GestionScreen data={gestion} />}
      {screen === 'bill' && bill && <BillPrompt data={bill} />}
      {screen === 'impound' && impound && <ImpoundScreen data={impound} />}
    </div>
  )
}

// dev mock
const DEV_VENTE: VenteData = {
  ok: true,
  dealer: { id: 'auto_centre', label: 'Concession Auto — Centre', accent: '#3ba9e0', categories: ['car', 'utility'], catNames: { car: 'Voiture', utility: 'Utilitaire' } },
  perms: ['vente'],
  stock: [
    { model: 'sultan', label: 'Sultan', brand: 'Karin', category: 'car', seats: 4, trunk: 40000, stats: { speed: 60, accel: 62, braking: 55, handling: 68 }, import: 22000, price: 26000, qty: 3, display: true },
    { model: 'kuruma', label: 'Kuruma', brand: 'Karin', category: 'car', seats: 4, trunk: 38000, stats: { speed: 68, accel: 70, braking: 62, handling: 72 }, import: 42000, price: 50000, qty: 1, display: false },
    { model: 'rumpo', label: 'Rumpo', brand: 'Bravado', category: 'utility', seats: 4, trunk: 200000, stats: { speed: 42, accel: 40, braking: 42, handling: 44 }, import: 16000, price: 19000, qty: 0, display: false },
  ],
}
