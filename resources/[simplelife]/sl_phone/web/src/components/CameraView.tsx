import { useEffect, useState } from 'react'
import { Camera } from 'lucide-react'
import { useNuiEvent } from '../hooks/useNuiEvent'
import { fetchNui } from '../lib/fetchNui'
import { rpc } from '../lib/rpc'
import { processCapture } from '../lib/image'

// Fullscreen viewfinder over the scripted camera. Aiming/zoom/shutter are driven by Lua; this
// only draws the framing + handles the capture (crop to portrait when toggled) → DB.
export function CameraView() {
  const [flash, setFlash] = useState(false)
  const [shots, setShots] = useState(0)
  const [thumb, setThumb] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [portrait, setPortrait] = useState(false)

  useEffect(() => { fetchNui('camera:start', {}) }, [])

  useNuiEvent('camera:flash', () => {
    setFlash(true)
    setTimeout(() => setFlash(false), 150)
  })
  useNuiEvent('camera:toggleMode', () => setPortrait((p) => !p))

  useNuiEvent<{ image: string }>('camera:captured', async (d) => {
    if (!d || !d.image) return
    setSaving(true)
    const { full, thumb: th } = await processCapture(d.image, portrait)
    const r = await rpc<{ ok: boolean; reason?: string }>('gallery:save', { data: full, thumb: th }, { ok: true })
    setSaving(false)
    if (r.ok) { setShots((s) => s + 1); setThumb(th); setErr(null) }
    else { setErr(r.reason === 'LIMIT' ? 'Galerie pleine (max 100)' : "Échec de l'enregistrement"); setTimeout(() => setErr(null), 1800) }
  })

  return (
    <div className="fixed inset-0 z-[55] pointer-events-none select-none">
      {/* framing: a 9:16 box in portrait (darkened sides), the full frame in landscape */}
      {portrait ? (
        <div
          className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 h-[92%] aspect-[9/16] rounded-2xl border border-white/30"
          style={{ boxShadow: '0 0 0 9999px rgba(0,0,0,0.62)' }}
        />
      ) : (
        <div className="absolute inset-6 border border-white/25 rounded-2xl" />
      )}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-9 h-9 border border-white/40 rounded-full" />

      <div className="absolute top-8 inset-x-0 flex items-center justify-center gap-2 text-white/90 text-sm drop-shadow">
        <Camera size={16} /> {portrait ? 'Portrait' : 'Paysage'}{saving ? ' · enregistrement…' : ''}
      </div>
      <div className="absolute bottom-8 inset-x-0 text-center text-white/85 text-sm drop-shadow">
        Souris : viser · Molette : zoom · Clic gauche : photo · Clic droit : selfie · G : portrait/paysage · Échap : quitter{shots > 0 ? ` · ${shots} pris` : ''}
      </div>

      {thumb && (
        <img src={thumb} alt="" className="absolute bottom-8 right-8 w-14 h-24 object-cover rounded-lg ring-2 ring-white/60 shadow-lg" />
      )}
      {err && (
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 translate-y-14 px-3 py-1.5 rounded-lg bg-black/75 text-[#ff6b6b] text-sm">{err}</div>
      )}
      {flash && <div className="absolute inset-0 bg-white" />}
    </div>
  )
}
