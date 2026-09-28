import { useEffect, useRef, useState } from 'react'
import { MessageSquare, Send, DollarSign } from 'lucide-react'
import { usePhone } from '../store'
import { rpc } from '../lib/rpc'
import type { Conversation, Message } from '../types'
import { formatNumber, timeAgo, clockTime, formatMoney } from '../lib/format'
import { Avatar, Empty, AppHeader, LargeHeader, SearchBar, iOS } from './ui'

const MOCK_CONVOS: Conversation[] = [
  { number: '0698765432', name: 'Maman', last_body: 'Tu rentres quand ?', last_at: '2026-06-28 11:40:00', unread: 2 },
  { number: '0612340000', name: null, last_body: 'ok à toute', last_at: '2026-06-28 09:10:00', unread: 0 },
]

function Thread({ number, onBack }: { number: string; onBack: () => void }) {
  const me = usePhone((s) => s.device?.number)
  const smsBump = usePhone((s) => s.smsBump)
  const setActiveThread = usePhone((s) => s.setActiveThread)
  const [msgs, setMsgs] = useState<Message[]>([])
  const [name, setName] = useState<string | null>(null)
  const [text, setText] = useState('')
  const [pay, setPay] = useState<string | null>(null)
  const scrollRef = useRef<HTMLDivElement>(null)

  const load = () =>
    rpc<{ ok: boolean; messages: Message[]; name?: string | null }>('sms:thread', { number }, { ok: true, messages: [], name: null })
      .then((r) => { if (r.ok) { setMsgs(r.messages); setName(r.name ?? null) } })
  useEffect(() => { load() }, [number, smsBump])
  useEffect(() => { scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight }) }, [msgs])
  // tell the store which thread is open so handleSms suppresses its banner/badge for it.
  useEffect(() => { setActiveThread(number); return () => setActiveThread(null) }, [number, setActiveThread])

  const send = async () => {
    const body = text.trim()
    if (!body) return
    const r = await rpc<{ ok: boolean; reason?: string }>('sms:send', { to: number, body }, { ok: true })
    if (r.ok) { setText(''); load() }
    else usePhone.getState().pushNotification({ app: 'messages', title: 'Message', body: r.reason === 'UNKNOWN_NUMBER' ? 'Numéro inconnu.' : r.reason === 'RATE' ? 'Trop rapide, réessaie.' : 'Envoi impossible.' })
  }

  const doPay = async () => {
    const amount = parseInt(pay || '', 10)
    if (!(amount > 0)) return
    const r = await rpc<{ ok: boolean; reason?: string }>('messages:pay', { to: number, amount }, { ok: true })
    if (r.ok) { setPay(null); load() }
    else usePhone.getState().pushNotification({ app: 'wallet', title: 'Paiement', body: r.reason === 'OFFLINE' ? 'Destinataire hors-ligne.' : r.reason === 'NO_FUNDS' ? 'Fonds insuffisants.' : r.reason === 'UNKNOWN_NUMBER' ? 'Numéro inconnu.' : 'Échec.' })
  }

  return (
    <div className="h-full flex flex-col relative">
      <AppHeader title={name || formatNumber(number)} onBack={onBack} backLabel="Messages" />
      <div ref={scrollRef} className="flex-1 overflow-y-auto no-scrollbar px-3 py-3 flex flex-col gap-1">
        {msgs.map((m) => {
          const mine = m.sender === me
          if (m.kind === 'transfer') {
            return (
              <div
                key={m.id}
                className={`max-w-[75%] px-3.5 py-2.5 rounded-[18px] flex items-center gap-2.5 ${mine ? 'self-end' : 'self-start'}`}
                style={{ background: 'rgba(52,199,89,0.18)', border: '1px solid rgba(52,199,89,0.45)' }}
              >
                <span className="text-lg">💸</span>
                <div>
                  <div className="font-semibold text-[#7CFFB0] text-[15px]">{mine ? 'Envoyé' : 'Reçu'} {formatMoney(m.amount)}</div>
                  <div className="text-[10px] text-white/50 mt-0.5">{clockTime(m.created_at)}</div>
                </div>
              </div>
            )
          }
          return (
            <div
              key={m.id}
              className={`max-w-[78%] px-3.5 py-[7px] rounded-[18px] text-[15px] leading-snug ${mine ? 'self-end text-white' : 'self-start text-white'}`}
              style={mine ? { background: iOS.tint } : { background: iOS.cell2 }}
            >
              <div className="whitespace-pre-wrap break-words">{m.body}</div>
              <div className={`text-[10px] mt-0.5 text-right ${mine ? 'text-white/60' : 'text-white/40'}`}>{clockTime(m.created_at)}</div>
            </div>
          )
        })}
      </div>
      <div className="flex items-center gap-2 px-2.5 py-2 border-t border-white/10">
        <button onClick={() => setPay('')} className="w-8 h-8 rounded-full flex items-center justify-center shrink-0" style={{ background: 'rgba(255,255,255,0.08)' }} title="Envoyer de l'argent"><DollarSign size={17} className="text-[#34c759]" /></button>
        <input
          value={text} onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); send(); e.currentTarget.blur() } }}
          placeholder="iMessage" className="flex-1 rounded-full px-4 py-2 text-[15px] text-white outline-none" style={{ background: 'rgba(118,118,128,0.24)' }}
        />
        <button onClick={send} disabled={!text.trim()} className="w-8 h-8 rounded-full flex items-center justify-center disabled:opacity-40 shrink-0" style={{ background: iOS.tint }}><Send size={16} color="#fff" /></button>
      </div>

      {pay !== null && (
        <div className="absolute inset-0 z-30 flex flex-col justify-end" style={{ background: 'rgba(0,0,0,0.5)' }} onMouseDown={(e) => { if (e.target === e.currentTarget) setPay(null) }}>
          <div className="rounded-t-3xl p-5 pb-8 flex flex-col gap-3" style={{ background: '#1b1d24', animation: 'app-in 0.2s ease' }}>
            <span className="text-white font-semibold text-lg">Envoyer de l'argent</span>
            <input autoFocus value={pay} onChange={(e) => setPay(e.target.value.replace(/\D/g, ''))} placeholder="Montant ($)" inputMode="numeric" className="rounded-xl px-3 py-3 text-white outline-none" style={{ background: 'rgba(255,255,255,0.07)' }} />
            <button onClick={doPay} disabled={!pay} className="py-3 rounded-xl bg-[#34c759] text-white font-semibold disabled:opacity-40">Envoyer{pay ? ` ${formatMoney(parseInt(pay, 10))}` : ''}</button>
          </div>
        </div>
      )}
    </div>
  )
}

function Compose({ onClose, onSent }: { onClose: () => void; onSent: (n: string) => void }) {
  const [number, setNumber] = useState('')
  const [text, setText] = useState('')
  const send = async () => {
    const to = number.replace(/\D/g, '')
    const body = text.trim()
    if (!to || !body) return
    const r = await rpc<{ ok: boolean; reason?: string }>('sms:send', { to, body }, { ok: true })
    if (r.ok) onSent(to)
    else usePhone.getState().pushNotification({ app: 'messages', title: 'Message', body: r.reason === 'UNKNOWN_NUMBER' ? 'Numéro inconnu.' : 'Envoi impossible.' })
  }
  return (
    <div className="h-full flex flex-col">
      <AppHeader title="Nouveau message" onBack={onClose} backLabel="Annuler" />
      <div className="p-3 flex flex-col gap-3">
        <input
          autoFocus value={number} onChange={(e) => setNumber(e.target.value.replace(/\D/g, ''))}
          placeholder="Numéro du destinataire" inputMode="numeric" className="rounded-xl px-3.5 py-3 text-[15px] text-white outline-none" style={{ background: 'rgba(118,118,128,0.24)' }}
        />
        <textarea
          value={text} onChange={(e) => setText(e.target.value)} placeholder="Message" rows={4}
          className="rounded-xl px-3.5 py-3 text-[15px] text-white outline-none resize-none" style={{ background: 'rgba(118,118,128,0.24)' }}
        />
        <button onClick={send} disabled={!number || !text.trim()} className="py-3 rounded-xl text-white font-semibold disabled:opacity-40" style={{ background: iOS.tint }}>Envoyer</button>
      </div>
    </div>
  )
}

export function MessagesApp() {
  const smsBump = usePhone((s) => s.smsBump)
  const consume = usePhone((s) => s.consumePendingThread)
  const syncMessagesBadge = usePhone((s) => s.syncMessagesBadge)
  const setBackHandler = usePhone((s) => s.setBackHandler)
  const [thread, setThread] = useState<string | null>(null)
  const [convos, setConvos] = useState<Conversation[]>([])
  const [composing, setComposing] = useState(false)
  const [query, setQuery] = useState('')

  const loadConvos = () =>
    rpc<{ ok: boolean; conversations: Conversation[] }>('sms:conversations', {}, { ok: true, conversations: MOCK_CONVOS })
      .then((r) => {
        if (r.ok) {
          setConvos(r.conversations)
          syncMessagesBadge(r.conversations.reduce((a, c) => a + (c.unread || 0), 0)) // badge = server truth
        }
      })

  useEffect(() => {
    const t = consume()
    if (t) setThread(t)
  }, [consume])
  useEffect(() => { if (!thread && !composing) loadConvos() }, [thread, composing, smsBump])
  // back goes: compose/thread -> conversation list (one step), then the store takes it home.
  useEffect(() => {
    if (composing) setBackHandler(() => { setComposing(false); return true })
    else if (thread) setBackHandler(() => { setThread(null); return true })
    else setBackHandler(null)
    return () => setBackHandler(null)
  }, [thread, composing, setBackHandler])

  if (composing) return <Compose onClose={() => setComposing(false)} onSent={(n) => { setComposing(false); setThread(n) }} />
  if (thread) return <Thread number={thread} onBack={() => setThread(null)} />

  const q = query.trim().toLowerCase()
  const filtered = q
    ? convos.filter((c) => (c.name || '').toLowerCase().includes(q) || c.number.includes(q) || (c.last_body || '').toLowerCase().includes(q))
    : convos

  return (
    <div className="h-full flex flex-col relative">
      <LargeHeader
        title="Messages"
        left={<button onClick={() => { /* edit mode placeholder */ }}>Modifier</button>}
        right={<button onClick={() => setComposing(true)} className="text-[22px] leading-none -mt-0.5">+</button>}
      />
      <SearchBar value={query} onChange={setQuery} />
      <div className="flex-1 overflow-y-auto no-scrollbar">
        {filtered.length === 0 ? (
          <Empty icon={<MessageSquare size={40} />} label="Aucune conversation" hint="Touchez + pour écrire" />
        ) : filtered.map((c) => (
          <button key={c.number} onClick={() => setThread(c.number)} className="w-full flex items-center gap-3 px-4 py-2.5 text-left active:bg-white/[0.06]">
            <Avatar name={c.name} number={c.number} size={50} />
            <div className="flex-1 min-w-0 border-b py-0.5" style={{ borderColor: iOS.sep }}>
              <div className="flex justify-between items-baseline gap-2">
                <span className="text-white font-semibold text-[16px] truncate">{c.name || formatNumber(c.number)}</span>
                <span className="text-white/35 text-[13px] shrink-0">{timeAgo(c.last_at)}</span>
              </div>
              <div className="flex justify-between items-center gap-2 mt-0.5">
                <span className="text-white/45 text-[14px] truncate">{c.last_body}</span>
                {c.unread > 0 && (
                  <span className="shrink-0 min-w-[20px] h-[20px] px-1.5 rounded-full text-white text-[11px] font-bold flex items-center justify-center" style={{ background: iOS.tint }}>{c.unread}</span>
                )}
              </div>
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
