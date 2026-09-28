import { useEffect, useRef, useState } from 'react'
import type { LucideIcon } from 'lucide-react'
import {
  Utensils, CupSoda, Pill, Wrench, FileText, Key, Package, Box, X,
  Hand, Crosshair, Backpack, Shirt,
} from 'lucide-react'
import { fetchNui } from '@/lib/fetchNui'
import { glass } from '@/lib/glass'

const CAT_ICON: Record<string, LucideIcon> = {
  food: Utensils, drink: CupSoda, medical: Pill, tool: Wrench,
  document: FileText, key: Key, material: Package, misc: Box,
}
// fixed equipment slots shown around the character (data.player.equip provides the items)
const EQUIP_SLOTS: { id: string; label: string; Icon: LucideIcon }[] = [
  { id: 'clothing', label: 'Vêtement', Icon: Shirt },
  { id: 'holster', label: 'Holster', Icon: Crosshair },
  { id: 'hand', label: 'Main', Icon: Hand },
  { id: 'bag', label: 'Sac', Icon: Backpack },
]

export interface InvItem {
  slot: number | string; name: string; label: string; count: number; weight: number
  category: string; usable: boolean; stack: number; desc?: string
}
export interface Grid {
  items: InvItem[]; weight: number; maxWeight: number; slots: number
  label?: string; id?: number; kind?: 'ground' | 'container'
  equip?: Record<string, InvItem>
}
export interface InventoryPayload { player: Grid; container: Grid; accent?: string }

type Side = 'player' | 'equip' | 'ground' | 'container'
interface DragState { side: Side; item: InvItem; x: number; y: number }
interface MenuState { side: Side; item: InvItem; x: number; y: number }

const fmtKg = (g: number) => (g / 1000).toFixed(1)

export default function Inventory(payload: InventoryPayload) {
  const g = glass(payload.accent)
  const [data, setData] = useState<InventoryPayload>(payload)
  const [drag, setDrag] = useState<DragState | null>(null)
  const [menu, setMenu] = useState<MenuState | null>(null)
  const dragRef = useRef<DragState | null>(null)
  dragRef.current = drag
  const rotateRef = useRef(false)

  useNuiInventory((d) => setData(d))

  // never let an absent right panel crash the grid (defensive — the client always re-resolves it)
  const rightGrid: Grid = data.container ?? {
    items: [], weight: 0, maxWeight: data.player.maxWeight, slots: data.player.slots, kind: 'ground', label: 'Sol',
  }
  const rightSide: Side = rightGrid.kind === 'container' ? 'container' : 'ground'
  const rightLabel = rightGrid.label || (rightSide === 'container' ? 'Sac' : 'Sol')
  const containerId = rightGrid.kind === 'container' ? rightGrid.id : undefined

  const close = () => fetchNui('dispatch', { event: 'inv:close' })
  const op = (event: string, o: unknown) => fetchNui('dispatch', { event, data: o })

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' || e.key === 'Tab') { e.preventDefault(); close() } }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // item drag (drop onto the slot under the pointer) + character rotation
  useEffect(() => {
    const onMove = (e: MouseEvent) => {
      if (dragRef.current) setDrag({ ...dragRef.current, x: e.clientX, y: e.clientY })
      else if (rotateRef.current && e.movementX) op('inv:rotate', { delta: e.movementX * 0.6 })
    }
    const onUp = (e: MouseEvent) => {
      rotateRef.current = false
      const d = dragRef.current
      if (!d) return
      setDrag(null)
      const cell = (document.elementFromPoint(e.clientX, e.clientY) as HTMLElement | null)?.closest('[data-slot]') as HTMLElement | null
      if (!cell) return
      const toSide = cell.dataset.side as Side
      const toSlot: number | string = toSide === 'equip' ? (cell.dataset.slot as string) : Number(cell.dataset.slot)
      if (toSide === d.side && String(toSlot) === String(d.item.slot)) return
      op('inv:move', {
        from: { inv: d.side, slot: d.item.slot },
        to: { inv: toSide, slot: toSlot },
        count: d.item.count,
        containerId,
      })
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
    return () => { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp) }
  }, [data.container])

  const startDrag = (side: Side, item: InvItem, e: React.MouseEvent) => {
    if (e.button !== 0) return
    setMenu(null)
    setDrag({ side, item, x: e.clientX, y: e.clientY })
  }
  const openMenu = (side: Side, item: InvItem, e: React.MouseEvent) => { e.preventDefault(); setMenu({ side, item, x: e.clientX, y: e.clientY }) }

  return (
    <div className="absolute inset-0 flex items-stretch justify-center gap-5 px-[4vw] py-[5vh]" onMouseDown={() => setMenu(null)}>
      <div className="flex w-[33%] max-w-[460px]" onMouseDown={(e) => e.stopPropagation()}>
        <GridPanel side="player" grid={data.player} glass={g} title="Inventaire" onDrag={startDrag} onMenu={openMenu} onClose={close} />
      </div>

      {/* MIDDLE: transparent (the real ped shows behind) + rotate + equipment row */}
      <div className="flex w-[24%] flex-col items-center" onMouseDown={(e) => e.stopPropagation()}>
        <div className="mb-2 text-[13px] uppercase tracking-[0.25em] text-white/60">Personnage</div>
        <div className="flex-1 w-full cursor-ew-resize select-none"
          onMouseDown={(e) => { e.preventDefault(); rotateRef.current = true }} title="Glisser pour tourner" />
        <div className="mt-2 grid w-full grid-cols-4 gap-2">
          {EQUIP_SLOTS.map((s) => (
            <EquipSlot key={s.id} def={s} item={data.player.equip?.[s.id]} glass={g} onDrag={startDrag} onMenu={openMenu} />
          ))}
        </div>
      </div>

      <div className="flex w-[33%] max-w-[460px]" onMouseDown={(e) => e.stopPropagation()}>
        <GridPanel side={rightSide} grid={rightGrid} glass={g} title={rightLabel} onDrag={startDrag} onMenu={openMenu} />
      </div>

      {drag && (
        <div className="pointer-events-none fixed z-50 flex h-12 w-12 items-center justify-center rounded-xl border border-white/30 bg-black/60"
          style={{ left: drag.x - 24, top: drag.y - 24 }}><ItemIcon item={drag.item} active /></div>
      )}

      {menu && (
        <ContextMenu menu={menu} accent={g.accent} onAction={(a) => {
          if (a === 'use') op('inv:use', menu.item.slot)
          else if (a === 'drop') op('inv:drop', { slot: menu.item.slot, count: menu.item.count })
          else if (a === 'give') op('inv:give', { slot: menu.item.slot })
          else if (a === 'split') op('inv:move', {
            from: { inv: menu.side, slot: menu.item.slot }, to: { inv: menu.side, slot: -1 },
            count: Math.floor(menu.item.count / 2),
            containerId,
          })
          setMenu(null)
        }} />
      )}
    </div>
  )
}

function GridPanel({
  side, grid, glass: g, title, onDrag, onMenu, onClose,
}: {
  side: Side; grid: Grid; glass: ReturnType<typeof glass>; title: string
  onDrag: (s: Side, i: InvItem, e: React.MouseEvent) => void
  onMenu: (s: Side, i: InvItem, e: React.MouseEvent) => void
  onClose?: () => void
}) {
  const bySlot: Record<number, InvItem> = {}
  for (const it of grid.items) bySlot[Number(it.slot)] = it
  const pct = Math.min(100, Math.round((grid.weight / grid.maxWeight) * 100))

  return (
    <div className="flex w-full flex-col overflow-hidden rounded-[20px] border border-white/15 text-white" style={g.panel}>
      <div className="flex items-center justify-between border-b border-white/10 px-5 py-3"
        style={{ background: 'linear-gradient(180deg, rgba(255,255,255,0.07), rgba(255,255,255,0))' }}>
        <span className="text-[15px] font-medium tracking-[0.12em]">{title.toUpperCase()}</span>
        {onClose && <button onClick={onClose} className="text-white/60 transition-colors hover:text-white"><X size={18} /></button>}
      </div>
      <div className="px-5 pt-3">
        <div className="mb-1 flex justify-between text-[11px] text-white/50">
          <span>{fmtKg(grid.weight)} / {fmtKg(grid.maxWeight)} kg</span><span>{pct}%</span>
        </div>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-white/10">
          <div className="h-full rounded-full" style={{ width: `${pct}%`, background: g.accent }} />
        </div>
      </div>
      <div className="grid flex-1 grid-cols-5 content-start gap-2 overflow-y-auto p-4">
        {Array.from({ length: grid.slots }, (_, i) => i + 1).map((slot) => (
          <Cell key={slot} side={side} slot={slot} item={bySlot[slot]} onDrag={onDrag} onMenu={onMenu} />
        ))}
      </div>
    </div>
  )
}

function Cell({
  side, slot, item, onDrag, onMenu,
}: {
  side: Side; slot: number; item?: InvItem
  onDrag: (s: Side, i: InvItem, e: React.MouseEvent) => void
  onMenu: (s: Side, i: InvItem, e: React.MouseEvent) => void
}) {
  return (
    <div data-slot={slot} data-side={side}
      className="relative flex aspect-square items-center justify-center rounded-xl border border-white/10 bg-black/25"
      onMouseDown={(e) => item && onDrag(side, item, e)}
      onContextMenu={(e) => item && onMenu(side, item, e)}>
      {item && <ItemBody item={item} />}
    </div>
  )
}

function EquipSlot({
  def, item, glass: g, onDrag, onMenu,
}: {
  def: { id: string; label: string; Icon: LucideIcon }; item?: InvItem
  glass: ReturnType<typeof glass>
  onDrag: (s: Side, i: InvItem, e: React.MouseEvent) => void
  onMenu: (s: Side, i: InvItem, e: React.MouseEvent) => void
}) {
  const { Icon } = def
  return (
    <div data-slot={def.id} data-side="equip"
      className="relative flex aspect-square items-center justify-center rounded-xl border bg-black/30"
      style={item ? g.selected : { borderColor: 'rgba(255,255,255,0.14)' }}
      onMouseDown={(e) => item && onDrag('equip', item, e)}
      onContextMenu={(e) => item && onMenu('equip', item, e)} title={def.label}>
      {item ? <ItemBody item={item} />
        : <div className="flex flex-col items-center gap-1 text-white/35"><Icon size={20} /><span className="text-[8px] uppercase tracking-wide">{def.label}</span></div>}
    </div>
  )
}

function ItemBody({ item }: { item: InvItem }) {
  return (
    <>
      <ItemIcon item={item} />
      {item.count > 1 && <span className="absolute bottom-0.5 right-1 text-[11px] font-medium tabular-nums text-white">{item.count}</span>}
      <span className="absolute left-0 right-0 top-0.5 truncate px-1 text-center text-[8px] uppercase tracking-wide text-white/55">{item.label}</span>
    </>
  )
}
function ItemIcon({ item, active }: { item: InvItem; active?: boolean }) {
  const Icon = CAT_ICON[item.category] || Box
  return <Icon size={26} strokeWidth={1.6} className={active ? 'text-white' : 'text-white/85'} />
}

function ContextMenu({
  menu, accent, onAction,
}: {
  menu: MenuState; accent: string; onAction: (a: 'use' | 'split' | 'drop' | 'give') => void
}) {
  const rows: { id: 'use' | 'split' | 'drop' | 'give'; label: string; show: boolean }[] = [
    { id: 'use', label: 'Utiliser', show: menu.item.usable && menu.side === 'player' },
    { id: 'split', label: 'Diviser', show: menu.item.count > 1 && menu.side !== 'equip' },
    { id: 'give', label: 'Donner', show: menu.side === 'player' },
    { id: 'drop', label: 'Jeter', show: menu.side === 'player' },
  ]
  const visible = rows.filter((r) => r.show)
  if (visible.length === 0) return null
  return (
    <div className="fixed z-50 w-40 overflow-hidden rounded-xl border border-white/15 bg-[rgba(18,20,26,0.92)] py-1 text-white"
      style={{ left: menu.x, top: menu.y }} onMouseDown={(e) => e.stopPropagation()}>
      <div className="border-b border-white/10 px-3 py-1.5 text-[11px] text-white/55">{menu.item.label}</div>
      {visible.map((r) => (
        <button key={r.id} onClick={() => onAction(r.id)}
          className="block w-full px-3 py-2 text-left text-[13px] transition-colors hover:bg-white/10"
          style={r.id === 'use' ? { color: accent } : undefined}>{r.label}</button>
      ))}
    </div>
  )
}

function useNuiInventory(handler: (d: InventoryPayload) => void) {
  const saved = useRef(handler)
  saved.current = handler
  useEffect(() => {
    const fn = (e: MessageEvent) => {
      const p = e.data as { action?: string; data?: InventoryPayload }
      if (p && p.action === 'inventoryUpdate') saved.current(p.data as InventoryPayload)
    }
    window.addEventListener('message', fn)
    return () => window.removeEventListener('message', fn)
  }, [])
}
