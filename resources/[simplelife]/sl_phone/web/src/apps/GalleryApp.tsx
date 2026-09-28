import { useEffect, useState } from 'react'
import { Image as ImageIcon, Trash2, X } from 'lucide-react'
import { usePhone } from '../store'
import { rpc } from '../lib/rpc'
import { Empty, LargeHeader } from './ui'

interface MediaItem { id: number; thumb: string | null; created_at: string }

export function GalleryApp() {
  const setBackHandler = usePhone((s) => s.setBackHandler)
  const [items, setItems] = useState<MediaItem[]>([])
  const [viewId, setViewId] = useState<number | null>(null)
  const [full, setFull] = useState<string | null>(null)

  const load = () =>
    rpc<{ ok: boolean; media: MediaItem[] }>('gallery:list', {}, { ok: true, media: [] }).then((r) => { if (r.ok) setItems(r.media) })
  useEffect(() => { load() }, [])

  const open = async (id: number) => {
    setViewId(id)
    setFull(null)
    const fallback = items.find((m) => m.id === id)?.thumb ?? undefined
    const r = await rpc<{ ok: boolean; data?: string }>('gallery:get', { id }, { ok: true, data: fallback })
    if (r.ok && r.data) setFull(r.data)
  }
  const close = () => { setViewId(null); setFull(null) }
  const del = async () => {
    if (viewId == null) return
    const r = await rpc<{ ok: boolean; media: MediaItem[] }>('gallery:delete', { id: viewId }, { ok: true, media: items.filter((m) => m.id !== viewId) })
    if (r.ok) setItems(r.media)
    close()
  }

  const viewerOpen = viewId != null
  useEffect(() => {
    if (viewerOpen) setBackHandler(() => { close(); return true })
    else setBackHandler(null)
    return () => setBackHandler(null)
  }, [viewerOpen, setBackHandler])

  return (
    <div className="h-full flex flex-col relative">
      <LargeHeader title="Galerie" />
      <div className="flex-1 overflow-y-auto no-scrollbar">
        {items.length === 0 ? (
          <Empty icon={<ImageIcon size={40} />} label="Aucune photo" hint="Prends-en avec l'app Caméra" />
        ) : (
          <div className="grid grid-cols-3 gap-[2px]">
            {items.map((m) => (
              <button
                key={m.id}
                onClick={() => open(m.id)}
                className="aspect-square overflow-hidden bg-white/[0.06] flex items-center justify-center active:opacity-70"
              >
                {m.thumb
                  ? <img src={m.thumb} alt="" className="w-full h-full object-cover" />
                  : <ImageIcon size={22} className="text-white/25" />}
              </button>
            ))}
          </div>
        )}
      </div>

      {viewerOpen && (
        <div className="absolute inset-0 z-30 bg-black flex flex-col" style={{ animation: 'app-in 0.15s ease' }}>
          <div className="flex items-center justify-between px-3 h-12 shrink-0">
            <button onClick={close} className="text-white/90 active:opacity-50"><X size={26} strokeWidth={2.2} /></button>
            <button onClick={del} className="text-[#ff453a] active:opacity-50"><Trash2 size={22} /></button>
          </div>
          <div className="flex-1 flex items-center justify-center px-2 pb-4 min-h-0">
            {full
              ? <img src={full} alt="" className="max-w-full max-h-full object-contain" />
              : <span className="text-white/40 text-[15px]">Chargement…</span>}
          </div>
        </div>
      )}
    </div>
  )
}
