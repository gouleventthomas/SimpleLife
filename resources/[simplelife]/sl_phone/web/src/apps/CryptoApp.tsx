import { useEffect, useState } from 'react'
import { Send, X, Bitcoin } from 'lucide-react'
import { usePhone } from '../store'
import { rpc } from '../lib/rpc'
import type { CryptoHolding, CoinDef } from '../types'
import { LargeHeader, ListGroup, ListRow, Empty } from './ui'

export function CryptoApp() {
  const setBackHandler = usePhone((s) => s.setBackHandler)
  const notify = usePhone((s) => s.pushNotification)
  const [holdings, setHoldings] = useState<CryptoHolding[]>([])
  const [coins, setCoins] = useState<CoinDef[]>([])
  const [sheet, setSheet] = useState<{ coin: string; to: string; amount: string } | null>(null)

  const load = async () => {
    const r = await rpc<{ ok: boolean; holdings: CryptoHolding[]; coins: CoinDef[] }>('crypto:state', {}, { ok: true, holdings: [], coins: [] })
    if (r.ok) { setHoldings(r.holdings); setCoins(r.coins) }
  }
  useEffect(() => { load() }, [])

  const sheetOpen = !!sheet
  useEffect(() => {
    if (sheetOpen) setBackHandler(() => { setSheet(null); return true })
    else setBackHandler(null)
    return () => setBackHandler(null)
  }, [sheetOpen, setBackHandler])

  const coinDef = (id: string) => coins.find((c) => c.id === id)

  const submit = async () => {
    if (!sheet) return
    const to = sheet.to.replace(/\D/g, '')
    const amount = parseFloat(sheet.amount)
    if (!to || !(amount > 0)) return
    const r = await rpc<{ ok: boolean; reason?: string }>('crypto:transfer', { coin: sheet.coin, to, amount }, { ok: true })
    if (r.ok) { setSheet(null); load() }
    else notify({ app: 'crypto', title: 'Crypto', body: r.reason === 'INSUFFICIENT' ? 'Solde insuffisant.' : r.reason === 'UNKNOWN_NUMBER' ? 'Numéro inconnu.' : r.reason === 'SELF' ? 'Vers soi-même impossible.' : 'Échec.' })
  }

  return (
    <div className="h-full flex flex-col relative">
      <LargeHeader title="Crypto" />
      <div className="flex-1 overflow-y-auto no-scrollbar pt-2">
        {holdings.length === 0 ? (
          <Empty icon={<Bitcoin size={40} />} label="Aucune crypto" hint="Tu ne détiens encore aucun coin." />
        ) : (
          <ListGroup footer="Touche l'icône d'envoi pour transférer un coin à un autre numéro.">
            {holdings.map((h) => {
              const d = coinDef(h.coin)
              return (
                <ListRow
                  key={h.coin}
                  leading={
                    <div className="w-[34px] h-[34px] rounded-full flex items-center justify-center text-[15px] font-bold shrink-0" style={{ background: `${d?.color || '#888'}33`, color: d?.color || '#fff' }}>{d?.symbol || '?'}</div>
                  }
                  title={d?.label || h.coin}
                  subtitle={`${Number(h.amount)} ${h.coin.toUpperCase()}`}
                  right={
                    <button onClick={() => setSheet({ coin: h.coin, to: '', amount: '' })} className="w-9 h-9 rounded-full bg-white/[0.08] flex items-center justify-center shrink-0 active:opacity-50">
                      <Send size={16} className="text-[#0a84ff]" />
                    </button>
                  }
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
              <span className="text-white font-semibold text-lg">Envoyer {coinDef(sheet.coin)?.label || sheet.coin}</span>
              <button onClick={() => setSheet(null)}><X size={20} className="text-white/50" /></button>
            </div>
            <input autoFocus value={sheet.to} onChange={(e) => setSheet({ ...sheet, to: e.target.value.replace(/\D/g, '') })} placeholder="Numéro du destinataire" inputMode="numeric" className="rounded-xl px-3 py-3 text-white outline-none" style={{ background: 'rgba(255,255,255,0.07)' }} />
            <input value={sheet.amount} onChange={(e) => setSheet({ ...sheet, amount: e.target.value.replace(/[^\d.]/g, '') })} placeholder="Montant" inputMode="decimal" className="rounded-xl px-3 py-3 text-white outline-none" style={{ background: 'rgba(255,255,255,0.07)' }} />
            <button onClick={submit} disabled={!sheet.to || !sheet.amount} className="py-3 rounded-xl bg-[#0a84ff] text-white font-semibold disabled:opacity-40 mt-1">Envoyer</button>
          </div>
        </div>
      )}
    </div>
  )
}
