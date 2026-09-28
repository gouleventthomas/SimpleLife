import { useEffect, useMemo, useRef, useState } from 'react'
import type { LucideIcon } from 'lucide-react'
import {
  Wallet, Banknote, Coins, Landmark, CreditCard, ArrowDownCircle, ArrowUpCircle,
  ArrowRightLeft, Receipt, Lock, Briefcase, Car, ShoppingBag, ChevronRight,
  Crosshair, Users, User, Ghost, Bug, Wrench, Heart, Shield, MapPin, Trash2,
} from 'lucide-react'
import { fetchNui } from '@/lib/fetchNui'
import { glass, type Glass } from '@/lib/glass'

// Curated icon set (string name -> lucide component). Extend as new menus need icons.
const ICONS: Record<string, LucideIcon> = {
  wallet: Wallet, cash: Banknote, coins: Coins, bank: Landmark, card: CreditCard,
  deposit: ArrowDownCircle, withdraw: ArrowUpCircle, transfer: ArrowRightLeft,
  receipt: Receipt, lock: Lock, job: Briefcase, car: Car, shop: ShoppingBag,
  gun: Crosshair, users: Users, user: User, ghost: Ghost, bug: Bug,
  wrench: Wrench, heart: Heart, shield: Shield, pin: MapPin, trash: Trash2,
}

export interface MenuItem {
  id: string
  label: string
  icon?: string
  value?: string          // right-aligned value (info rows / status)
  description?: string    // shown in the footer while this row is selected
  kind?: 'action' | 'info'
  disabled?: boolean
}

export interface MenuPayload {
  id: string
  title: string
  subtitle?: string
  items: MenuItem[]
  accent?: string         // theme color (hex); e.g. ATM Fleeca -> green. Default cyan.
}

const selectable = (it: MenuItem) => it.kind !== 'info' && !it.disabled

// The signature Liquid Glass list menu (Menu V layout, translucent tinted-glass skin).
export default function Menu({ id, title, subtitle, items, accent }: MenuPayload) {
  const g = glass(accent)
  const list = items ?? []
  const idxs = useMemo(
    () => list.map((it, i) => (selectable(it) ? i : -1)).filter((i) => i >= 0),
    [list],
  )
  const [sel, setSel] = useState<number>(idxs[0] ?? -1)
  const selRef = useRef(sel)
  selRef.current = sel

  // Reset selection to the first selectable row whenever the menu content changes (id OR items
  // — sibling submenus like the weapon lists reuse one id but bring different items).
  useEffect(() => { setSel(idxs[0] ?? -1) }, [id, idxs]) // eslint-disable-line react-hooks/exhaustive-deps

  const move = (dir: number) => {
    if (idxs.length === 0) return
    const pos = idxs.indexOf(selRef.current)
    setSel(idxs[(pos + dir + idxs.length) % idxs.length])
  }
  const choose = (i: number) => {
    const it = list[i]
    if (!it || !selectable(it)) return
    fetchNui('dispatch', { event: 'menu:select', data: { menuId: id, itemId: it.id } })
  }
  const close = () => fetchNui('dispatch', { event: 'menu:close', data: { menuId: id } })

  // Keyboard navigation (pure keyboard — the mouse never touches the menu). RE-bound whenever
  // the menu changes (id/items) so a submenu — which reuses this same component instance, no
  // remount — reads ITS OWN items and id, not the parent's (the stale-closure submenu bug).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowDown') { e.preventDefault(); move(1) }
      else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1) }
      else if (e.key === 'Enter') { e.preventDefault(); choose(selRef.current) }
      // Back: Escape, Backspace ("Retour arrière") AND Delete ("Suppr") all step back / close.
      else if (e.key === 'Escape' || e.key === 'Backspace' || e.key === 'Delete') { e.preventDefault(); close() }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [id, idxs]) // eslint-disable-line react-hooks/exhaustive-deps

  const selItem = sel >= 0 ? list[sel] : undefined
  // Counter reflects position among SELECTABLE rows only — info rows (kind:'info'/disabled) don't count.
  const selPos = idxs.indexOf(sel)
  const counter = selPos >= 0 ? `${selPos + 1} / ${idxs.length}` : `${idxs.length}`

  return (
    // pointer-events-none: this is a KEYBOARD-DRIVEN menu. The mouse must not hover/select/move
    // the UI — events pass straight through to the game (camera look) while ↑↓/Enter/Suppr drive it.
    <div className="pointer-events-none absolute inset-0">
      <div
        className="absolute left-[54%] top-1/2 w-[320px] -translate-y-1/2 overflow-hidden rounded-[20px] border border-white/15 text-white"
        style={g.panel}
      >
        <div
          className="border-b border-white/10 px-5 py-4 text-center"
          style={{ background: 'linear-gradient(180deg, rgba(255,255,255,0.07), rgba(255,255,255,0))' }}
        >
          <div className="text-[17px] font-medium tracking-[0.18em]">{(title ?? '').toUpperCase()}</div>
        </div>

        <div className="flex items-center justify-between border-b border-white/[0.07] px-5 py-2 text-[11px] tracking-[0.15em] text-white/55">
          <span>{(subtitle ?? '').toUpperCase()}</span>
          <span>{counter}</span>
        </div>

        <div className="p-2">
          {list.map((it, i) => (
            <Row key={it.id} item={it} active={i === sel} glass={g} />
          ))}
        </div>

        {selItem?.description && (
          <div className="mx-3 mb-3 rounded-xl border border-white/[0.08] bg-black/20 px-3.5 py-2.5 text-[12px] leading-snug text-white/75">
            {selItem.description}
          </div>
        )}

        <div className="flex items-center justify-center gap-4 border-t border-white/[0.07] px-4 py-2 text-[10px] tracking-wide text-white/40">
          <span>↑↓ Naviguer</span>
          <span>Entrée Valider</span>
          <span>Suppr Retour</span>
        </div>
      </div>
    </div>
  )
}

function Row({
  item, active, glass: g,
}: {
  item: MenuItem; active: boolean; glass: Glass
}) {
  const Icon = item.icon ? ICONS[item.icon] : undefined
  const info = item.kind === 'info' || item.disabled

  return (
    <div
      className={`relative my-0.5 flex items-center justify-between rounded-[13px] px-3.5 py-3 ${info ? 'opacity-60' : ''}`}
      style={active ? g.selected : { border: '1px solid transparent' }}
    >
      {active && (
        <span className="absolute left-0 top-2 bottom-2 w-[3px] rounded-full" style={g.bar} />
      )}
      <span className={`flex items-center gap-2.5 text-[14px] ${active ? 'font-medium text-white' : 'text-white/90'}`}>
        {Icon && <Icon size={17} strokeWidth={2} className={active ? 'text-white' : 'text-white/65'} />}
        {item.label}
      </span>
      {item.value
        ? <span className="text-[14px] font-medium text-white/80">{item.value}</span>
        : (!info && <ChevronRight size={17} className={active ? 'text-white' : 'text-white/40'} />)}
    </div>
  )
}
