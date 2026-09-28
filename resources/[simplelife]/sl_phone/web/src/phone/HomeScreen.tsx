import { useEffect, useState } from 'react'
import { usePhone } from '../store'
import { appIcon } from '../lib/icons'
import type { AppDef } from '../types'

// iOS-style Calendar app icon: white face, red weekday, big black date.
function CalendarFace() {
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 30000)
    return () => clearInterval(t)
  }, [])
  const wd = now.toLocaleDateString('fr-FR', { weekday: 'short' }).replace('.', '')
  return (
    <div className="w-[58px] h-[58px] rounded-[14px] bg-white shadow-md flex flex-col items-center justify-center">
      <div className="text-[#ff453a] text-[10px] font-bold uppercase leading-none mt-1.5">{wd}</div>
      <div className="text-black text-[30px] font-light leading-none -mt-0.5">{now.getDate()}</div>
    </div>
  )
}

// Renders the generated PNG icon (icons/<id>.png, served from public/) and falls back to the
// lucide glyph squircle if the image is missing. 'calendrier' keeps its live-date face.
function AppTile({ app }: { app: AppDef }) {
  const [failed, setFailed] = useState(false)
  if (app.id === 'calendrier') return <CalendarFace />
  if (!failed) {
    return (
      <img
        src={`icons/${app.id}.png`} alt="" draggable={false} onError={() => setFailed(true)}
        className="w-[58px] h-[58px] object-contain"
        style={{ filter: 'drop-shadow(0 1px 3px rgba(0,0,0,0.4))' }}
      />
    )
  }
  const Icon = appIcon(app.icon)
  return (
    <div
      className="w-[58px] h-[58px] rounded-[14px] flex items-center justify-center shadow-md"
      style={{ background: `linear-gradient(160deg, ${app.color}, ${app.color}cc)` }}
    >
      <Icon size={30} color="#fff" strokeWidth={2} />
    </div>
  )
}

function AppIcon({ app, onOpen, badge = 0 }: { app: AppDef; onOpen: (id: string) => void; badge?: number }) {
  return (
    <button onClick={() => onOpen(app.id)} className="flex flex-col items-center gap-1.5 group">
      <div className="relative transition-transform group-active:scale-90">
        <AppTile app={app} />
        {badge > 0 && (
          <span className="absolute -top-1.5 -right-1.5 min-w-[20px] h-5 px-1 rounded-full bg-[#ff3b30] text-white text-[11px] font-bold flex items-center justify-center ring-2 ring-black/20">
            {badge > 99 ? '99+' : badge}
          </span>
        )}
      </div>
      <span className="text-[11px] text-white font-medium drop-shadow-[0_1px_2px_rgba(0,0,0,0.6)] max-w-[68px] truncate">{app.label}</span>
    </button>
  )
}

export function HomeScreen() {
  const device = usePhone((s) => s.device)!
  const openApp = usePhone((s) => s.openApp)
  const badges = usePhone((s) => s.badges)

  const dock = device.dock ?? []
  const removed = new Set(device.removed ?? [])
  // Home shows only installed apps; mandatory (system) apps are always shown. The iFruit Store
  // manages what's installed. Dock apps are all mandatory, so they're never filtered out.
  const grid = device.apps.filter((a) => !dock.includes(a.id) && (a.mandatory || !removed.has(a.id)))
  const dockApps = dock
    .map((id) => device.apps.find((a) => a.id === id))
    .filter((a): a is AppDef => Boolean(a))

  return (
    <div className="h-full flex flex-col">
      <div className="flex-1 px-5 pt-4 grid grid-cols-4 gap-x-4 gap-y-[18px] auto-rows-min content-start overflow-y-auto no-scrollbar">
        {grid.map((a) => (
          <AppIcon key={a.id} app={a} onOpen={openApp} badge={badges[a.id] || 0} />
        ))}
      </div>
      <div className="mx-3 mb-7 rounded-[30px] px-4 py-3 flex justify-around" style={{ background: 'rgba(60,60,67,0.4)' }}>
        {dockApps.map((a) => (
          <AppIcon key={a.id} app={a} onOpen={openApp} badge={badges[a.id] || 0} />
        ))}
      </div>
    </div>
  )
}
