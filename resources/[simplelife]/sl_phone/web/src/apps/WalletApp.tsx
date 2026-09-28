import { useEffect, useState } from 'react'
import { ArrowDownLeft, ArrowUpRight, Send, HandCoins, X, Check } from 'lucide-react'
import { usePhone } from '../store'
import { rpc } from '../lib/rpc'
import type { BankTx, PayRequest } from '../types'
import { formatMoney, timeAgo } from '../lib/format'
import { LargeHeader, ListGroup, ListRow, IconBadge, iOS } from './ui'

type Sheet = { mode: 'transfer' | 'request'; to: string; amount: string; reason: string } | null

const ERR: Record<string, string> = {
  OFFLINE: 'Destinataire hors-ligne.',
  UNKNOWN_NUMBER: 'Numéro inconnu.',
  SELF: 'Impossible vers soi-même.',
  NO_FUNDS: 'Fonds insuffisants.',
  BAD_AMOUNT: 'Montant invalide.',
  INVALID: 'Champs invalides.',
  GONE: 'Demande expirée.',
}

export function WalletApp() {
  const setBackHandler = usePhone((s) => s.setBackHandler)
  const notify = usePhone((s) => s.pushNotification)
  const [bank, setBank] = useState(0)
  const [cash, setCash] = useState(0)
  const [history, setHistory] = useState<BankTx[]>([])
  const [incoming, setIncoming] = useState<PayRequest[]>([])
  const [sheet, setSheet] = useState<Sheet>(null)

  const load = async () => {
    const s = await rpc<{ ok: boolean; cash: number; bank: number }>('wallet:state', {}, { ok: true, cash: 1200, bank: 5400 })
    if (s.ok) { setBank(s.bank); setCash(s.cash) }
    const h = await rpc<{ ok: boolean; history: BankTx[] }>('wallet:history', {}, { ok: true, history: [] })
    if (h.ok) setHistory(h.history)
    const r = await rpc<{ ok: boolean; incoming: PayRequest[] }>('wallet:requests', {}, { ok: true, incoming: [] })
    if (r.ok) setIncoming(r.incoming)
  }
  useEffect(() => { load() }, [])

  const sheetOpen = !!sheet
  useEffect(() => {
    if (sheetOpen) setBackHandler(() => { setSheet(null); return true })
    else setBackHandler(null)
    return () => setBackHandler(null)
  }, [sheetOpen, setBackHandler])

  const submit = async () => {
    if (!sheet) return
    const to = sheet.to.replace(/\D/g, '')
    const amount = parseInt(sheet.amount, 10)
    if (!to || !(amount > 0)) return
    const method = sheet.mode === 'transfer' ? 'wallet:transfer' : 'wallet:requestMoney'
    const r = await rpc<{ ok: boolean; reason?: string }>(method, { to, amount, reason: sheet.reason }, { ok: true })
    if (r.ok) { setSheet(null); load() }
    else notify({ app: 'wallet', title: 'Banque', body: ERR[r.reason || ''] || 'Échec.' })
  }

  const respond = async (id: number, accept: boolean) => {
    const r = await rpc<{ ok: boolean; reason?: string }>('wallet:respondRequest', { id, accept }, { ok: true })
    if (!r.ok) notify({ app: 'wallet', title: 'Banque', body: ERR[r.reason || ''] || 'Échec.' })
    load()
  }

  return (
    <div className="h-full flex flex-col relative" style={{ background: iOS.bg }}>
      <LargeHeader title="Banque" />
      <div className="flex-1 overflow-y-auto no-scrollbar pb-6">
        {/* Balance card (Fleeca vibe) */}
        <div className="px-4 pt-1 pb-5">
          <div className="rounded-[20px] p-5 shadow-lg" style={{ background: 'linear-gradient(145deg,#0a84ff,#0a3a8f)' }}>
            <div className="text-white/70 text-[12px] font-medium tracking-wide">Compte principal</div>
            <div className="text-white text-[34px] leading-tight font-bold mt-1">{formatMoney(bank)}</div>
            <div className="mt-3 flex items-center gap-1.5 text-white/75 text-[13px]">
              <span className="w-1.5 h-1.5 rounded-full bg-[#34c759]" />
              Liquide&nbsp;<span className="font-semibold text-white">{formatMoney(cash)}</span>
            </div>
          </div>

          {/* Action pills */}
          <div className="grid grid-cols-2 gap-3 mt-4">
            <button
              onClick={() => setSheet({ mode: 'transfer', to: '', amount: '', reason: '' })}
              className="rounded-[14px] py-3 flex items-center justify-center gap-2 text-[16px] font-semibold text-white active:opacity-80"
              style={{ background: iOS.tint }}
            >
              <Send size={18} /> Virer
            </button>
            <button
              onClick={() => setSheet({ mode: 'request', to: '', amount: '', reason: '' })}
              className="rounded-[14px] py-3 flex items-center justify-center gap-2 text-[16px] font-semibold text-[#0a84ff] active:opacity-70"
              style={{ background: iOS.cell }}
            >
              <HandCoins size={18} /> Demander
            </button>
          </div>
        </div>

        {/* Incoming requests */}
        {incoming.length > 0 && (
          <ListGroup header="Demandes reçues">
            {incoming.map((q) => (
              <ListRow
                key={q.id}
                leading={<IconBadge color="#ff9f0a"><HandCoins size={16} color="#fff" /></IconBadge>}
                title={q.name || q.number}
                subtitle={`Demande ${formatMoney(q.amount)}${q.reason ? ` · ${q.reason}` : ''}`}
                right={
                  <div className="flex items-center gap-2 shrink-0">
                    <button onClick={() => respond(q.id, false)} className="w-9 h-9 rounded-full bg-[#ff3b30]/20 text-[#ff453a] flex items-center justify-center active:opacity-70"><X size={16} /></button>
                    <button onClick={() => respond(q.id, true)} className="w-9 h-9 rounded-full bg-[#34c759]/20 text-[#34c759] flex items-center justify-center active:opacity-70"><Check size={16} /></button>
                  </div>
                }
              />
            ))}
          </ListGroup>
        )}

        {/* History */}
        {history.length === 0 ? (
          <ListGroup header="Historique">
            <ListRow title={<span className="text-white/40">Aucune transaction.</span>} />
          </ListGroup>
        ) : (
          <ListGroup header="Historique">
            {history.map((t) => {
              const out = t.dir === 'out'
              return (
                <ListRow
                  key={t.id}
                  leading={
                    <div className={`w-[29px] h-[29px] rounded-[7px] flex items-center justify-center shrink-0 ${out ? 'bg-[#ff3b30]/15 text-[#ff6b6b]' : 'bg-[#34c759]/15 text-[#34c759]'}`}>
                      {out ? <ArrowUpRight size={16} /> : <ArrowDownLeft size={16} />}
                    </div>
                  }
                  title={out ? `Vers ${t.to_number}` : `De ${t.from_number}`}
                  subtitle={`${t.reason || (t.kind === 'request' ? 'Demande' : 'Virement')} · ${timeAgo(t.created_at)}`}
                  right={<div className={`text-[15px] font-semibold shrink-0 ${out ? 'text-[#ff6b6b]' : 'text-[#34c759]'}`}>{out ? '-' : '+'}{formatMoney(t.amount)}</div>}
                />
              )
            })}
          </ListGroup>
        )}
      </div>

      {sheet && (
        <div className="absolute inset-0 z-30 flex flex-col justify-end" style={{ background: 'rgba(0,0,0,0.5)' }} onMouseDown={(e) => { if (e.target === e.currentTarget) setSheet(null) }}>
          <div className="rounded-t-3xl p-5 pb-8 flex flex-col gap-3" style={{ background: '#1b1d24', animation: 'app-in 0.2s ease' }}>
            <div className="flex items-center justify-between">
              <span className="text-white font-semibold text-lg">{sheet.mode === 'transfer' ? "Virer de l'argent" : "Demander de l'argent"}</span>
              <button onClick={() => setSheet(null)}><X size={20} className="text-white/50" /></button>
            </div>
            <input autoFocus value={sheet.to} onChange={(e) => setSheet({ ...sheet, to: e.target.value.replace(/\D/g, '') })} placeholder="Numéro" inputMode="numeric" className="rounded-xl px-3 py-3 text-white outline-none" style={{ background: 'rgba(255,255,255,0.07)' }} />
            <input value={sheet.amount} onChange={(e) => setSheet({ ...sheet, amount: e.target.value.replace(/\D/g, '') })} placeholder="Montant ($)" inputMode="numeric" className="rounded-xl px-3 py-3 text-white outline-none" style={{ background: 'rgba(255,255,255,0.07)' }} />
            <input value={sheet.reason} onChange={(e) => setSheet({ ...sheet, reason: e.target.value })} placeholder="Motif (optionnel)" className="rounded-xl px-3 py-3 text-white outline-none" style={{ background: 'rgba(255,255,255,0.07)' }} />
            <button onClick={submit} disabled={!sheet.to || !sheet.amount} className="py-3 rounded-xl bg-[#0a84ff] text-white font-semibold disabled:opacity-40 mt-1">{sheet.mode === 'transfer' ? 'Envoyer' : 'Demander'}</button>
          </div>
        </div>
      )}
    </div>
  )
}
