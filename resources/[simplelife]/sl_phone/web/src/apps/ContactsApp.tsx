import { useEffect, useState } from 'react'
import { Phone, MessageSquare, Star, Trash2, UserPlus, X } from 'lucide-react'
import { usePhone } from '../store'
import { rpc } from '../lib/rpc'
import type { Contact } from '../types'
import { formatNumber } from '../lib/format'
import { Avatar, Empty, LargeHeader, SearchBar, Toggle } from './ui'

const MOCK: Contact[] = [
  { id: 1, name: 'Maman', number: '0698765432', favorite: 1 },
  { id: 2, name: 'Léo Martin', number: '0612340000', favorite: 0 },
]

interface Editing { id?: number; name: string; number: string; favorite: boolean }

function ContactEditor({
  editing, setEditing, onSave, onRemove,
}: { editing: Editing; setEditing: (e: Editing | null) => void; onSave: () => void; onRemove: () => void }) {
  return (
    <div
      className="absolute inset-0 z-30 flex flex-col justify-end"
      style={{ background: 'rgba(0,0,0,0.5)' }}
      onMouseDown={(e) => { if (e.target === e.currentTarget) setEditing(null) }}
    >
      <div className="rounded-t-[20px] p-5 pb-8 flex flex-col gap-4" style={{ background: '#1c1c1e', animation: 'app-in 0.2s ease' }}>
        <div className="flex items-center justify-between">
          <span className="text-white font-semibold text-[20px]">{editing.id ? 'Modifier' : 'Nouveau contact'}</span>
          <button onClick={() => setEditing(null)} className="active:opacity-50"><X size={22} className="text-white/45" /></button>
        </div>
        <div className="flex flex-col items-center gap-2 pb-1">
          <Avatar name={editing.name || undefined} number={editing.number} size={72} color={editing.favorite ? '#0a84ff' : '#3a3a44'} />
        </div>
        <input
          autoFocus value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })}
          placeholder="Nom" className="rounded-[10px] px-3.5 py-3 text-[16px] text-white outline-none" style={{ background: 'rgba(118,118,128,0.24)' }}
        />
        <input
          value={editing.number} onChange={(e) => setEditing({ ...editing, number: e.target.value.replace(/\D/g, '') })}
          placeholder="Numéro" inputMode="numeric" className="rounded-[10px] px-3.5 py-3 text-[16px] text-white outline-none" style={{ background: 'rgba(118,118,128,0.24)' }}
        />
        <div className="flex items-center justify-between rounded-[10px] px-3.5 py-2.5" style={{ background: 'rgba(118,118,128,0.24)' }}>
          <span className="text-white text-[16px] flex items-center gap-2">
            <Star size={17} className={editing.favorite ? 'text-[#ffd60a]' : 'text-white/40'} fill={editing.favorite ? '#ffd60a' : 'none'} /> Favori
          </span>
          <Toggle on={editing.favorite} onChange={(v) => setEditing({ ...editing, favorite: v })} />
        </div>
        <div className="flex gap-3 mt-1">
          {editing.id && (
            <button onClick={onRemove} className="px-4 py-3 rounded-[12px] bg-[#ff3b30]/20 text-[#ff453a] flex items-center justify-center active:opacity-60"><Trash2 size={18} /></button>
          )}
          <button
            onClick={onSave} disabled={!editing.name.trim() || !editing.number.trim()}
            className="flex-1 py-3 rounded-[12px] bg-[#0a84ff] text-white font-semibold text-[16px] disabled:opacity-40 active:opacity-80"
          >Enregistrer</button>
        </div>
      </div>
    </div>
  )
}

export function ContactsApp() {
  const startCall = usePhone((s) => s.startCall)
  const openMessagesWith = usePhone((s) => s.openMessagesWith)
  const setBackHandler = usePhone((s) => s.setBackHandler)
  const [list, setList] = useState<Contact[]>([])
  const [q, setQ] = useState('')
  const [editing, setEditing] = useState<Editing | null>(null)

  const load = () =>
    rpc<{ ok: boolean; contacts: Contact[] }>('contacts:list', {}, { ok: true, contacts: MOCK }).then((r) => { if (r.ok) setList(r.contacts) })
  useEffect(() => { load() }, [])

  // back closes the editor sheet first (if open), else the store takes it home.
  const editorOpen = !!editing
  useEffect(() => {
    if (editorOpen) setBackHandler(() => { setEditing(null); return true })
    else setBackHandler(null)
    return () => setBackHandler(null)
  }, [editorOpen, setBackHandler])

  const filtered = list.filter((c) => c.name.toLowerCase().includes(q.toLowerCase()) || c.number.includes(q))

  const save = async () => {
    if (!editing) return
    const method = editing.id ? 'contacts:update' : 'contacts:add'
    const r = await rpc<{ ok: boolean; contacts: Contact[] }>(method, editing, { ok: true, contacts: list })
    if (r.ok) { setList(r.contacts); setEditing(null) }
  }
  const remove = async () => {
    if (!editing?.id) return
    const r = await rpc<{ ok: boolean; contacts: Contact[] }>('contacts:delete', { id: editing.id }, { ok: true, contacts: list })
    if (r.ok) { setList(r.contacts); setEditing(null) }
  }

  return (
    <div className="h-full flex flex-col relative" style={{ background: '#000' }}>
      <LargeHeader
        title="Contacts"
        right={<button onClick={() => setEditing({ name: '', number: '', favorite: false })} className="active:opacity-50"><UserPlus size={22} /></button>}
      />
      <SearchBar value={q} onChange={setQ} />
      <div className="flex-1 overflow-y-auto no-scrollbar px-4 pt-1">
        {filtered.length === 0 ? (
          <Empty icon={<UserPlus size={40} />} label="Aucun contact" hint="Ajoutez-en un avec le bouton +" />
        ) : (
          <div className="rounded-[12px] overflow-hidden" style={{ background: '#1c1c1e' }}>
            <div className="divide-y" style={{ borderColor: 'rgba(255,255,255,0.07)' }}>
              {filtered.map((c) => (
                <div key={c.id} className="flex items-center gap-3 px-3.5 py-2 active:bg-white/[0.06]">
                  <Avatar name={c.name} color={c.favorite ? '#0a84ff' : '#3a3a44'} />
                  <button
                    className="flex-1 text-left min-w-0"
                    onClick={() => setEditing({ id: c.id, name: c.name, number: c.number, favorite: !!c.favorite })}
                  >
                    <div className="text-white text-[16px] font-semibold truncate flex items-center gap-1">
                      {c.name}{c.favorite ? <Star size={12} className="text-[#ffd60a]" fill="#ffd60a" /> : null}
                    </div>
                    <div className="text-white/45 text-[13px] truncate">{formatNumber(c.number)}</div>
                  </button>
                  <button onClick={() => openMessagesWith(c.number)} className="w-9 h-9 rounded-full bg-white/[0.08] flex items-center justify-center active:scale-90 shrink-0">
                    <MessageSquare size={17} className="text-[#34c759]" />
                  </button>
                  <button onClick={() => startCall(c.number)} className="w-9 h-9 rounded-full bg-white/[0.08] flex items-center justify-center active:scale-90 shrink-0">
                    <Phone size={17} className="text-[#34c759]" />
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
      {editing && <ContactEditor editing={editing} setEditing={setEditing} onSave={save} onRemove={remove} />}
    </div>
  )
}
