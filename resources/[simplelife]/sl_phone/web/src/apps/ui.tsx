import type { ReactNode } from 'react'
import { ChevronLeft, ChevronRight, Plus, Search } from 'lucide-react'
import { initials } from '../lib/format'

// ── iOS palette (dark) ───────────────────────────────────────────────────────────
export const iOS = {
  tint: '#0a84ff',
  bg: '#000000',
  cell: '#1c1c1e',
  cell2: '#2c2c2e',
  sep: 'rgba(255,255,255,0.07)',
  label: '#ffffff',
  label2: 'rgba(235,235,245,0.6)',
  label3: 'rgba(235,235,245,0.3)',
  green: '#34c759',
  red: '#ff453a',
}

// Compact nav bar: blue back (chevron + label) left, centered title, optional right action.
export function AppHeader({
  title, onBack, backLabel = 'Accueil', right,
}: { title: string; onBack: () => void; backLabel?: string; right?: ReactNode }) {
  return (
    <div className="relative h-12 shrink-0 flex items-center px-2">
      <button onClick={onBack} className="flex items-center text-[#0a84ff] text-[17px] -ml-1 active:opacity-50">
        <ChevronLeft size={26} strokeWidth={2.3} />
        <span className="-ml-1 truncate max-w-[90px]">{backLabel}</span>
      </button>
      <span className="absolute left-1/2 -translate-x-1/2 font-semibold text-white text-[17px] max-w-[52%] truncate">{title}</span>
      {right && <div className="ml-auto pr-2 text-[#0a84ff] text-[17px] flex items-center">{right}</div>}
    </div>
  )
}

// iOS large-title header (big bold title; optional inline left/right actions above it).
export function LargeHeader({ title, left, right }: { title: string; left?: ReactNode; right?: ReactNode }) {
  return (
    <div className="px-4 pt-1.5">
      {(left || right) && (
        <div className="h-7 flex items-center justify-between text-[#0a84ff] text-[17px]">
          <div className="active:opacity-50">{left}</div>
          <div className="active:opacity-50">{right}</div>
        </div>
      )}
      <h1 className="text-[32px] leading-[1.1] font-bold text-white py-1">{title}</h1>
    </div>
  )
}

export function SearchBar({ value, onChange, placeholder = 'Rechercher' }: { value: string; onChange: (v: string) => void; placeholder?: string }) {
  return (
    <div className="px-4 pb-2">
      <div className="flex items-center gap-1.5 rounded-[10px] px-2.5 py-[7px]" style={{ background: 'rgba(118,118,128,0.24)' }}>
        <Search size={15} className="text-white/45" />
        <input
          value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder}
          className="bg-transparent outline-none text-[15px] text-white placeholder:text-white/45 w-full"
        />
      </div>
    </div>
  )
}

// Grouped inset list (iOS Settings style). Children should be <ListRow>.
export function ListGroup({ header, children, footer }: { header?: string; children: ReactNode; footer?: string }) {
  return (
    <div className="px-4 mb-5">
      {header && <div className="px-1 pb-1.5 text-[12px] uppercase tracking-wide text-white/45">{header}</div>}
      <div className="rounded-[12px] overflow-hidden divide-y" style={{ background: iOS.cell, borderColor: iOS.sep }}>
        <div className="divide-y" style={{ borderColor: iOS.sep }}>{children}</div>
      </div>
      {footer && <div className="px-1 pt-1.5 text-[12px] text-white/40 leading-snug">{footer}</div>}
    </div>
  )
}

export function IconBadge({ color, children }: { color: string; children: ReactNode }) {
  return (
    <div className="w-[29px] h-[29px] rounded-[7px] flex items-center justify-center shrink-0" style={{ background: color }}>
      {children}
    </div>
  )
}

export function ListRow({
  leading, title, subtitle, value, right, chevron = false, onClick, danger = false,
}: {
  leading?: ReactNode; title: ReactNode; subtitle?: ReactNode; value?: ReactNode; right?: ReactNode
  chevron?: boolean; onClick?: () => void; danger?: boolean
}) {
  const cls = 'w-full flex items-center gap-3 px-3.5 py-[11px] text-left active:bg-white/[0.06]'
  const body = (
    <>
      {leading}
      <div className="flex-1 min-w-0">
        <div className={`text-[16px] truncate ${danger ? 'text-[#ff453a]' : 'text-white'}`}>{title}</div>
        {subtitle && <div className="text-[13px] text-white/45 truncate">{subtitle}</div>}
      </div>
      {value !== undefined && <div className="text-[15px] text-white/45 shrink-0 max-w-[45%] truncate">{value}</div>}
      {right}
      {chevron && <ChevronRight size={18} className="text-white/25 shrink-0 -mr-1" />}
    </>
  )
  return onClick ? <button onClick={onClick} className={cls}>{body}</button> : <div className={cls.replace('active:bg-white/[0.06]', '')}>{body}</div>
}

export function Toggle({ on, onChange }: { on: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      onClick={() => onChange(!on)}
      className={`w-[51px] h-[31px] rounded-full transition-colors relative shrink-0 ${on ? 'bg-[#34c759]' : 'bg-white/15'}`}
    >
      <span className={`absolute top-[2px] w-[27px] h-[27px] rounded-full bg-white shadow-md transition-all ${on ? 'left-[22px]' : 'left-[2px]'}`} />
    </button>
  )
}

export interface TabDef { id: string; label: string; icon: ReactNode }
export function TabBar({ tabs, active, onSelect }: { tabs: TabDef[]; active: string; onSelect: (id: string) => void }) {
  return (
    <div className="flex shrink-0 border-t border-white/10 pt-1.5 pb-1" style={{ background: 'rgba(22,22,24,0.92)' }}>
      {tabs.map((t) => (
        <button key={t.id} onClick={() => onSelect(t.id)} className={`flex-1 flex flex-col items-center gap-0.5 py-0.5 ${active === t.id ? 'text-[#0a84ff]' : 'text-white/45'}`}>
          {t.icon}
          <span className="text-[10px] font-medium">{t.label}</span>
        </button>
      ))}
    </div>
  )
}

// iOS app icon (squircle).
export function Squircle({ color, size = 60, children }: { color: string; size?: number; children: ReactNode }) {
  return (
    <div className="flex items-center justify-center shadow-md" style={{ width: size, height: size, borderRadius: Math.round(size * 0.225), background: color }}>
      {children}
    </div>
  )
}

export function Avatar({
  name, number, size = 44, color = '#3a3a3c',
}: { name?: string | null; number?: string; size?: number; color?: string }) {
  return (
    <div
      className="rounded-full flex items-center justify-center text-white font-semibold shrink-0"
      style={{ width: size, height: size, background: color, fontSize: Math.round(size * 0.4) }}
    >
      {initials(name || undefined, number)}
    </div>
  )
}

export function FAB({ onClick, color = '#0a84ff', children }: { onClick: () => void; color?: string; children?: ReactNode }) {
  return (
    <button
      onClick={onClick}
      className="absolute bottom-5 right-5 w-14 h-14 rounded-full flex items-center justify-center shadow-xl active:scale-90 transition-transform z-20"
      style={{ background: color }}
    >
      {children ?? <Plus size={26} color="#fff" />}
    </button>
  )
}

export function Empty({ icon, label, hint }: { icon: ReactNode; label: string; hint?: string }) {
  return (
    <div className="h-full flex flex-col items-center justify-center gap-3 text-center px-10 text-white/40">
      {icon}
      <div className="text-base font-medium text-white/70">{label}</div>
      {hint && <div className="text-xs text-white/40">{hint}</div>}
    </div>
  )
}
