import { useEffect, useState } from 'react'
import { Building2, Car, ShoppingBag, Send, RefreshCw } from 'lucide-react'
import { usePhone } from '../store'
import { vehiclesRpc } from '../lib/vehiclesRpc'
import { LargeHeader, AppHeader, ListGroup, ListRow, IconBadge, Empty } from './ui'

interface Company { id: string; kind: string; label: string; tag: string; sub: string; owned: boolean }

const MOCK: { ok: boolean; companies: Company[] } = {
  ok: true,
  companies: [
    { id: 'auto_centre', kind: 'dealership', label: 'Concession Auto — Centre', tag: 'Concession', sub: 'Voiture, Utilitaire', owned: true },
    { id: 'ltd_morningwood', kind: 'shop', label: 'LTD Morningwood', tag: 'Boutique', sub: 'Commerce', owned: true },
  ],
}

export function AnnuaireApp() {
  const [list, setList] = useState<Company[] | null>(null)
  const [sel, setSel] = useState<Company | null>(null)
  const [subject, setSubject] = useState('')
  const [message, setMessage] = useState('')
  const [sent, setSent] = useState(false)
  const [busy, setBusy] = useState(false)
  const notify = usePhone((s) => s.pushNotification)

  const load = () => { vehiclesRpc<{ ok: boolean; companies: Company[] }>('phone:directory', {}, MOCK).then((d) => setList(d?.companies || [])) }
  useEffect(() => { load() }, [])

  const open = (c: Company) => { setSel(c); setSubject(''); setMessage(''); setSent(false) }

  const submit = async () => {
    if (busy || !sel || message.trim() === '') return
    setBusy(true)
    const res: any = await vehiclesRpc('phone:contact', { companyId: sel.id, kind: sel.kind, subject, message }, { ok: true })
    setBusy(false)
    if (res?.ok) setSent(true)
    else notify({ app: 'annuaire', title: 'Annuaire', body: 'Envoi impossible' })
  }

  // ── contact form ──
  if (sel) {
    return (
      <div className="h-full flex flex-col">
        <AppHeader title={sel.label} backLabel="Annuaire" onBack={() => setSel(null)} />
        {sent ? (
          <div className="flex-1 flex flex-col items-center justify-center text-center px-10 gap-4">
            <IconBadge color="#34c759"><Send size={20} color="#fff" /></IconBadge>
            <div className="text-white text-[17px] font-semibold">Demande envoyée</div>
            <p className="text-white/55 text-[14px]">La société vous recontactera. Vous pouvez fermer.</p>
            <button onClick={() => setSel(null)} className="mt-2 px-5 py-2 rounded-full bg-[#34c759] text-white text-[14px] font-medium">Retour à l'annuaire</button>
          </div>
        ) : (
          <div className="flex-1 overflow-y-auto no-scrollbar px-4 pb-6">
            <div className="text-white/50 text-[13px] mb-3 mt-1">Formulaire de contact — laissez un message, un employé vous rappellera.</div>
            <input value={subject} onChange={(e) => setSubject(e.target.value)} placeholder="Objet (ex : modèle recherché)"
              className="w-full rounded-[12px] px-3.5 py-3 text-[15px] text-white outline-none mb-2" style={{ background: 'rgba(118,118,128,0.24)' }} />
            <textarea value={message} onChange={(e) => setMessage(e.target.value)} placeholder="Votre message…" rows={5}
              className="w-full rounded-[12px] px-3.5 py-3 text-[15px] text-white outline-none resize-none" style={{ background: 'rgba(118,118,128,0.24)' }} />
            <button onClick={submit} disabled={busy || message.trim() === ''}
              className="mt-4 w-full py-2.5 rounded-[12px] font-semibold text-white bg-[#34c759] disabled:opacity-30 active:scale-[0.99]">
              Envoyer la demande
            </button>
          </div>
        )}
      </div>
    )
  }

  // ── directory ──
  return (
    <div className="h-full flex flex-col">
      <LargeHeader title="Annuaire" right={<button onClick={load} className="active:opacity-50"><RefreshCw size={20} /></button>} />
      {!list ? (
        <div className="flex-1 grid place-items-center text-white/40">Chargement…</div>
      ) : list.length === 0 ? (
        <Empty icon={<Building2 size={40} />} label="Aucune société" />
      ) : (
        <div className="flex-1 overflow-y-auto no-scrollbar pb-6">
          <ListGroup header={`${list.length} société${list.length > 1 ? 's' : ''}`} footer="Touchez une société pour la contacter.">
            {list.map((c) => (
              <ListRow key={c.id + c.kind} onClick={() => open(c)} chevron
                leading={<IconBadge color={c.kind === 'dealership' ? '#34c759' : '#ff9500'}>
                  {c.kind === 'dealership' ? <Car size={16} color="#fff" /> : <ShoppingBag size={16} color="#fff" />}
                </IconBadge>}
                title={c.label} subtitle={`${c.tag} · ${c.sub}`} value={c.owned ? undefined : <span className="text-white/35">fermée</span>} />
            ))}
          </ListGroup>
        </div>
      )}
    </div>
  )
}
