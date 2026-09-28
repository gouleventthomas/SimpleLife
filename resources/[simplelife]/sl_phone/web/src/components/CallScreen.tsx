import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { Phone, PhoneOff } from 'lucide-react'
import { usePhone } from '../store'
import { formatNumber, callDuration, initials } from '../lib/format'

function CallBtn({ color, onClick, children }: { color: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      onClick={onClick}
      className="w-16 h-16 rounded-full flex items-center justify-center active:scale-90 transition-transform shadow-lg"
      style={{ background: color }}
    >
      {children}
    </button>
  )
}

// Full-screen call overlay shown whenever callState != idle. Covers the home/app behind it.
export function CallScreen() {
  const call = usePhone((s) => s.callState)
  const accept = usePhone((s) => s.acceptCall)
  const decline = usePhone((s) => s.declineCall)
  const hangup = usePhone((s) => s.hangupCall)
  const [elapsed, setElapsed] = useState(0)

  useEffect(() => {
    if (call.status !== 'active' || !call.since) return
    const since = call.since
    const tick = () => setElapsed(Math.floor((Date.now() - since) / 1000))
    tick()
    const t = setInterval(tick, 500)
    return () => clearInterval(t)
  }, [call.status, call.since])

  const title = call.name || formatNumber(call.number) || 'Inconnu'
  const sub =
    call.status === 'incoming' ? 'Appel entrant…' :
    call.status === 'outgoing' ? 'Appel…' :
    call.status === 'active' ? callDuration(elapsed) :
    call.reason === 'declined' ? 'Refusé' :
    call.reason === 'no_answer' || call.reason === 'missed' ? 'Pas de réponse' : 'Terminé'

  return (
    <div
      className="absolute inset-0 z-40 flex flex-col items-center justify-between py-24 px-8 text-white"
      style={{ background: 'linear-gradient(180deg,#16243f 0%,#0a0f1c 100%)' }}
    >
      <div className="flex flex-col items-center gap-4 mt-6">
        <div className="w-28 h-28 rounded-full bg-white/10 flex items-center justify-center text-5xl font-light ring-1 ring-white/15">
          {initials(call.name || undefined, call.number)}
        </div>
        <div className="text-2xl font-semibold text-center">{title}</div>
        <div className="text-white/55 text-sm">
          {call.name && call.number ? `${formatNumber(call.number)} · ` : ''}{sub}
        </div>
      </div>

      <div className="w-full flex items-center justify-center gap-12">
        {call.status === 'incoming' ? (
          <>
            <CallBtn color="#ff3b30" onClick={decline}><PhoneOff size={28} color="#fff" /></CallBtn>
            <CallBtn color="#34c759" onClick={accept}><Phone size={28} color="#fff" /></CallBtn>
          </>
        ) : call.status === 'ended' ? null : (
          <CallBtn color="#ff3b30" onClick={hangup}><PhoneOff size={28} color="#fff" /></CallBtn>
        )}
      </div>
    </div>
  )
}
