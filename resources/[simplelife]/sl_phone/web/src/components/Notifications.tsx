import { usePhone } from '../store'
import { appIcon } from '../lib/icons'

// Maps a notification's source app to a home-app icon name.
const APP_ICON: Record<string, string> = { messages: 'MessageSquare', phone: 'Phone' }

// Always rendered (even when the phone is closed), pointer-events-none so it never steals
// game input. Banners auto-dismiss from the store.
export function Notifications() {
  const notes = usePhone((s) => s.notifications)
  if (!notes.length) return null
  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-[60] flex flex-col gap-2 w-[360px] pointer-events-none">
      {notes.map((n) => {
        const Icon = appIcon(APP_ICON[n.app] ?? 'Settings')
        return (
          <div
            key={n.id}
            className="rounded-2xl px-4 py-3 flex items-start gap-3 shadow-2xl ring-1 ring-white/10"
            style={{ background: 'rgba(28,28,34,0.94)', animation: 'phone-in 0.25s ease' }}
          >
            <div className="w-9 h-9 rounded-xl bg-[#0a84ff] flex items-center justify-center shrink-0">
              <Icon size={18} color="#fff" />
            </div>
            <div className="min-w-0">
              <div className="text-white text-sm font-semibold truncate">{n.title}</div>
              <div className="text-white/70 text-xs line-clamp-2">{n.body}</div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
