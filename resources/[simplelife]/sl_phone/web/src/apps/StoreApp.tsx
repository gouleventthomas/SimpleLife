import { useState } from 'react'
import { Store, Search } from 'lucide-react'
import { usePhone } from '../store'
import { appIcon } from '../lib/icons'
import type { AppDef } from '../types'
import { LargeHeader, SearchBar, ListGroup, ListRow, Empty } from './ui'

// Small app icon for list rows: generated PNG (icons/<id>.png) with lucide glyph fallback.
function StoreIcon({ app }: { app: AppDef }) {
  const [failed, setFailed] = useState(false)
  if (!failed) {
    return (
      <img
        src={`icons/${app.id}.png`} alt="" draggable={false} onError={() => setFailed(true)}
        className="w-[44px] h-[44px] object-contain shrink-0"
      />
    )
  }
  const Icon = appIcon(app.icon)
  return (
    <div
      className="w-[44px] h-[44px] rounded-[10px] flex items-center justify-center shrink-0"
      style={{ background: `linear-gradient(160deg, ${app.color}, ${app.color}cc)` }}
    >
      <Icon size={24} color="#fff" />
    </div>
  )
}

function Pill({ label, tone, onClick }: { label: string; tone: 'get' | 'remove' | 'locked'; onClick?: () => void }) {
  const styles =
    tone === 'get'
      ? 'text-[#0a84ff] font-bold'
      : tone === 'remove'
        ? 'text-[#ff453a] font-semibold'
        : 'text-white/40 font-medium'
  return (
    <button
      onClick={onClick} disabled={!onClick}
      className={`text-[13px] uppercase tracking-wide rounded-full px-3.5 py-1 shrink-0 ${styles} ${onClick ? 'active:opacity-50' : ''}`}
      style={{ background: 'rgba(118,118,128,0.24)' }}
    >
      {label}
    </button>
  )
}

export function StoreApp() {
  const device = usePhone((s) => s.device)!
  const installApp = usePhone((s) => s.installApp)
  const uninstallApp = usePhone((s) => s.uninstallApp)
  const [q, setQ] = useState('')

  const removed = new Set(device.removed ?? [])
  const query = q.trim().toLowerCase()
  // The store lists every app except itself; calendrier shows here as a normal (system) entry.
  const apps = device.apps.filter((a) => a.id !== 'store' && (!query || a.label.toLowerCase().includes(query)))
  const available = apps.filter((a) => removed.has(a.id))
  const installed = apps.filter((a) => !removed.has(a.id))

  return (
    <div className="h-full flex flex-col overflow-y-auto no-scrollbar">
      <LargeHeader title="iFruit Store" />
      <SearchBar value={q} onChange={setQ} placeholder="Apps et jeux" />

      {available.length > 0 && (
        <ListGroup header="Disponible au téléchargement">
          {available.map((a) => (
            <ListRow
              key={a.id}
              leading={<StoreIcon app={a} />}
              title={a.label}
              subtitle="Application"
              right={<Pill label="Obtenir" tone="get" onClick={() => installApp(a.id)} />}
            />
          ))}
        </ListGroup>
      )}

      <ListGroup header={`Installé · ${installed.length}`} footer="Les apps système ne peuvent pas être supprimées.">
        {installed.map((a) => (
          <ListRow
            key={a.id}
            leading={<StoreIcon app={a} />}
            title={a.label}
            subtitle={a.mandatory ? 'Application système' : 'Application'}
            right={
              a.mandatory
                ? <Pill label="Système" tone="locked" />
                : <Pill label="Supprimer" tone="remove" onClick={() => uninstallApp(a.id)} />
            }
          />
        ))}
      </ListGroup>

      {apps.length === 0 && (
        <div className="flex-1">
          <Empty icon={<Search size={40} />} label="Aucun résultat" hint="Essaie un autre nom" />
        </div>
      )}
      <div className="shrink-0 pb-6 flex flex-col items-center gap-1 text-white/30">
        <Store size={18} />
        <span className="text-[11px]">iFruit Store</span>
      </div>
    </div>
  )
}
