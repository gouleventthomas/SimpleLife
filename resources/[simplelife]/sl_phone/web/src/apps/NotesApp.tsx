import { useEffect, useRef, useState } from 'react'
import { StickyNote, Trash2 } from 'lucide-react'
import { usePhone } from '../store'
import { rpc } from '../lib/rpc'
import type { Note } from '../types'
import { timeAgo } from '../lib/format'
import { Empty, AppHeader, LargeHeader } from './ui'

interface Editing { id?: number; title: string; body: string }

export function NotesApp() {
  const setBackHandler = usePhone((s) => s.setBackHandler)
  const [list, setList] = useState<Note[]>([])
  const [editing, setEditing] = useState<Editing | null>(null)
  const editingRef = useRef<Editing | null>(editing)
  editingRef.current = editing

  const load = () =>
    rpc<{ ok: boolean; notes: Note[] }>('notes:list', {}, { ok: true, notes: [] }).then((r) => { if (r.ok) setList(r.notes) })
  useEffect(() => { if (!editing) load() }, [editing])

  // Save (only if non-empty) and leave the editor — used by the back button AND right-click back.
  const exitEditor = async () => {
    const e = editingRef.current
    if (e && (e.title.trim() || e.body.trim())) {
      const r = await rpc<{ ok: boolean; notes: Note[] }>('notes:save', e, { ok: true, notes: list })
      if (r.ok) setList(r.notes)
    }
    setEditing(null)
  }
  const removeNote = async () => {
    const e = editingRef.current
    if (e?.id) {
      const r = await rpc<{ ok: boolean; notes: Note[] }>('notes:delete', { id: e.id }, { ok: true, notes: list })
      if (r.ok) setList(r.notes)
    }
    setEditing(null)
  }

  const editorOpen = !!editing
  useEffect(() => {
    if (editorOpen) setBackHandler(() => { void exitEditor(); return true })
    else setBackHandler(null)
    return () => setBackHandler(null)
  }, [editorOpen, setBackHandler]) // exitEditor reads editingRef, so it always saves the latest

  if (editing) {
    return (
      <div className="h-full flex flex-col">
        <AppHeader
          title={editing.title || 'Note'} onBack={() => void exitEditor()} backLabel="Notes"
          right={editing.id ? <button onClick={() => void removeNote()} className="text-[#ff453a] px-1 active:opacity-50"><Trash2 size={20} /></button> : undefined}
        />
        <div className="flex-1 flex flex-col px-4 py-3 gap-2 overflow-hidden">
          <input
            autoFocus value={editing.title} onChange={(e) => setEditing({ ...editing, title: e.target.value })}
            placeholder="Titre" className="bg-transparent text-white text-[22px] font-bold outline-none placeholder:text-white/30"
          />
          <textarea
            value={editing.body} onChange={(e) => setEditing({ ...editing, body: e.target.value })}
            placeholder="Écrire…" className="flex-1 bg-transparent text-white/90 text-[15px] leading-relaxed outline-none resize-none no-scrollbar placeholder:text-white/30"
          />
        </div>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col relative">
      <LargeHeader title="Notes" right={<button onClick={() => setEditing({ title: '', body: '' })}>Nouveau</button>} />
      <div className="flex-1 overflow-y-auto no-scrollbar">
        {list.length === 0 ? (
          <Empty icon={<StickyNote size={40} />} label="Aucune note" hint="Touchez Nouveau pour en créer une" />
        ) : (
          <div className="px-4">
            <div className="rounded-[12px] overflow-hidden divide-y" style={{ background: '#1c1c1e', borderColor: 'rgba(255,255,255,0.07)' }}>
              <div className="divide-y" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
                {list.map((n) => (
                  <button
                    key={n.id}
                    onClick={() => setEditing({ id: n.id, title: n.title, body: n.body })}
                    className="w-full text-left px-3.5 py-[11px] active:bg-white/[0.06]"
                  >
                    <div className="text-[16px] font-semibold text-white truncate">{n.title || 'Sans titre'}</div>
                    <div className="text-[13px] text-white/45 truncate">{timeAgo(n.updated_at)} · {n.body || '—'}</div>
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
