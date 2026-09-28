import { useEffect, useState } from 'react'
import { useNuiEvent } from '@/hooks/useNuiEvent'

// sl_ui/client/bridge.lua sends SendNUIMessage({ action:'notify', data:{ kind, message } }).
// kind is 'info' | 'error' (anything else is treated as 'info'). This is a transient,
// click-through toast — features fire-and-forget exports.sl_ui:notify(kind, message).
export interface NotifyData {
  kind?: string
  message?: string
}

interface Toast extends NotifyData {
  id: number
}

const LIFETIME_MS = 4200
let nextId = 0

// Grunge palette: warm brown-black surface, gold edge for info, dull red for error.
function toneClasses(kind?: string): string {
  if (kind === 'error') {
    return 'border-red-800/70 bg-gradient-to-b from-stone-900/95 to-stone-950/95 text-red-200'
  }
  return 'border-amber-700/60 bg-gradient-to-b from-stone-900/95 to-stone-950/95 text-amber-100'
}

export default function ToastHost() {
  const [toasts, setToasts] = useState<Toast[]>([])

  useNuiEvent<NotifyData>('notify', (data) => {
    const message = (data && data.message) || ''
    if (!message) return
    const id = nextId++
    setToasts((cur) => [...cur, { id, kind: data?.kind, message }])
    // Auto-dismiss after a fixed lifetime. Cap the stack so a flood can't pile up.
    window.setTimeout(() => {
      setToasts((cur) => cur.filter((t) => t.id !== id))
    }, LIFETIME_MS)
  })

  if (toasts.length === 0) return null

  return (
    <div className="pointer-events-none fixed top-6 left-1/2 z-50 flex -translate-x-1/2 flex-col items-center gap-2">
      {toasts.slice(-4).map((t) => (
        <ToastItem key={t.id} kind={t.kind} message={t.message} />
      ))}
    </div>
  )
}

function ToastItem({ kind, message }: NotifyData) {
  const [shown, setShown] = useState(false)
  // Mount-then-show so the entrance transition runs.
  useEffect(() => {
    const r = requestAnimationFrame(() => setShown(true))
    return () => cancelAnimationFrame(r)
  }, [])

  return (
    <div
      className={
        'min-w-[14rem] max-w-md rounded-lg border px-5 py-2.5 text-center text-sm font-medium uppercase tracking-wide shadow-lg shadow-black/60 backdrop-blur-sm transition-all duration-300 ' +
        toneClasses(kind) +
        (shown ? ' translate-y-0 opacity-100' : ' -translate-y-2 opacity-0')
      }
    >
      {message}
    </div>
  )
}
