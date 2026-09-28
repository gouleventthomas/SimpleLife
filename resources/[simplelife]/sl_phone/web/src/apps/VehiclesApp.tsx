import { useEffect, useState } from 'react'
import {
  Car, Lock, Unlock, MapPin, Power, PowerOff, Package, KeyRound, Users, RefreshCw, Trash2,
} from 'lucide-react'
import { usePhone } from '../store'
import { vehiclesRpc } from '../lib/vehiclesRpc'
import { LargeHeader, AppHeader, ListGroup, ListRow, IconBadge, Empty } from './ui'

interface Veh {
  id: number; plate: string; model: string; label: string; brand?: string
  fuel: number; body: number; engine: number; status: string; garage?: string; role: string; active: boolean
}
interface Holder { charid: number; name: string; role: string }

const STATUS: Record<string, { label: string; color: string }> = {
  out: { label: 'Sorti', color: '#34c759' }, parked: { label: 'Garé', color: '#0a84ff' }, impound: { label: 'Fourrière', color: '#ff453a' },
}
const REASON: Record<string, string> = {
  NO_KEY: "Vous n'avez pas la clé", NOT_OUT: "Le véhicule n'est pas sorti", NO_TARGET: 'Personne à proximité',
  IMPOUND: 'En fourrière', UNKNOWN: 'Position inconnue', LOCKED: 'Verrouillé', RATE: 'Trop rapide',
}
const msg = (r?: string) => REASON[r || ''] || 'Action impossible'

const MOCK: { ok: boolean; vehicles: Veh[] } = {
  ok: true,
  vehicles: [
    { id: 1, plate: 'SL12AB34', model: 'sultan', label: 'Sultan', brand: 'Karin', fuel: 72, body: 1000, engine: 880, status: 'out', role: 'owner', active: true },
    { id: 2, plate: 'KX99ZZ01', model: 'rumpo', label: 'Rumpo', brand: 'Bravado', fuel: 40, body: 600, engine: 700, status: 'parked', garage: 'central', role: 'owner', active: false },
  ],
}

export function VehiclesApp() {
  const [list, setList] = useState<Veh[] | null>(null)
  const [sel, setSel] = useState<Veh | null>(null)
  const [view, setView] = useState<'list' | 'detail' | 'keys'>('list')
  const [holders, setHolders] = useState<Holder[] | null>(null)
  const notify = usePhone((s) => s.pushNotification)

  const load = () => { vehiclesRpc<{ ok: boolean; vehicles: Veh[] }>('phone:vehicles', {}, MOCK).then((d) => setList(d?.vehicles || [])) }
  useEffect(() => { load() }, [])

  const act = async (method: string, params: object, okMsg?: string) => {
    const res: any = await vehiclesRpc(method, { dbId: sel?.id, ...params }, { ok: true })
    if (res?.ok) { if (okMsg) notify({ app: 'vehicules', title: 'Véhicules', body: okMsg }); return res }
    notify({ app: 'vehicules', title: 'Véhicules', body: msg(res?.reason) })
    return res
  }

  const openKeys = async () => {
    const res: any = await act('key:holders', {})
    if (res?.ok) { setHolders(res.holders || []); setView('keys') }
  }

  // ── list ──
  if (view === 'list') {
    return (
      <div className="h-full flex flex-col">
        <LargeHeader title="Véhicules" right={<button onClick={load} className="active:opacity-50"><RefreshCw size={20} /></button>} />
        {!list ? (
          <div className="flex-1 grid place-items-center text-white/40">Chargement…</div>
        ) : list.length === 0 ? (
          <Empty icon={<Car size={40} />} label="Aucun véhicule" hint="Achetez un véhicule à la concession." />
        ) : (
          <div className="flex-1 overflow-y-auto no-scrollbar pb-6">
            <ListGroup header={`${list.length} véhicule${list.length > 1 ? 's' : ''}`}>
              {list.map((v) => {
                const st = STATUS[v.status] || STATUS.out
                return (
                  <ListRow key={v.id} onClick={() => { setSel(v); setView('detail') }} chevron
                    leading={<IconBadge color="#34c759"><Car size={16} color="#fff" /></IconBadge>}
                    title={v.label} subtitle={`${v.plate}${v.role === 'shared' ? ' · clé partagée' : ''}`}
                    value={<span style={{ color: st.color }}>{st.label}</span>} />
                )
              })}
            </ListGroup>
          </div>
        )}
      </div>
    )
  }

  // ── keys management ──
  if (view === 'keys' && sel) {
    return (
      <div className="h-full flex flex-col">
        <AppHeader title="Clés" backLabel={sel.label} onBack={() => setView('detail')} />
        <div className="flex-1 overflow-y-auto no-scrollbar pb-6">
          <ListGroup header="Détenteurs">
            {(holders || []).map((h) => (
              <ListRow key={h.charid} leading={<IconBadge color={h.role === 'owner' ? '#0a84ff' : '#8e8e93'}><Users size={16} color="#fff" /></IconBadge>}
                title={h.name} subtitle={h.role === 'owner' ? 'Propriétaire' : 'Clé partagée'}
                right={h.role !== 'owner' ? (
                  <button onClick={async () => { const r: any = await act('key:revoke', { charid: h.charid }, 'Clé retirée'); if (r?.ok) setHolders(r.holders || []) }}
                    className="w-8 h-8 rounded-lg bg-[#ff453a]/15 text-[#ff453a] grid place-items-center"><Trash2 size={15} /></button>
                ) : undefined} />
            ))}
          </ListGroup>
          <div className="px-4">
            <button onClick={async () => { const r: any = await act('key:share', {}, 'Clé partagée'); if (r?.ok) setHolders(r.holders || []) }}
              className="w-full py-2.5 rounded-[12px] font-semibold text-white bg-[#34c759] active:scale-[0.99]">
              Partager la clé (personne à proximité)
            </button>
          </div>
        </div>
      </div>
    )
  }

  // ── detail ──
  if (!sel) return null
  const fuelColor = sel.fuel <= 15 ? '#ff453a' : '#34c759'
  return (
    <div className="h-full flex flex-col">
      <AppHeader title={sel.label} backLabel="Véhicules" onBack={() => setView('list')} />
      <div className="flex-1 overflow-y-auto no-scrollbar pb-6">
        <div className="px-4 py-2 flex items-center gap-3">
          <IconBadge color="#34c759"><Car size={16} color="#fff" /></IconBadge>
          <div>
            <div className="text-white text-[17px] font-semibold">{sel.brand} {sel.label}</div>
            <div className="text-white/45 text-[13px]">{sel.plate}</div>
          </div>
          <div className="ml-auto text-right">
            <div className="text-[13px]" style={{ color: fuelColor }}>⛽ {sel.fuel}%</div>
            <div className="text-[12px] text-white/40">moteur {Math.round(sel.engine / 10)}%</div>
          </div>
        </div>
        <ListGroup header="Commandes">
          <ListRow onClick={() => act('key:lock', { locked: false }, 'Déverrouillé')} leading={<IconBadge color="#34c759"><Unlock size={16} color="#fff" /></IconBadge>} title="Déverrouiller" />
          <ListRow onClick={() => act('key:lock', { locked: true }, 'Verrouillé')} leading={<IconBadge color="#ff9f0a"><Lock size={16} color="#fff" /></IconBadge>} title="Verrouiller" />
          <ListRow onClick={() => act('key:locate', {}, 'Position marquée')} leading={<IconBadge color="#0a84ff"><MapPin size={16} color="#fff" /></IconBadge>} title="Localiser (GPS)" />
          <ListRow onClick={() => act('key:engine', { on: true }, 'Moteur démarré')} leading={<IconBadge color="#30d158"><Power size={16} color="#fff" /></IconBadge>} title="Démarrer le moteur" />
          <ListRow onClick={() => act('key:engine', { on: false }, 'Moteur coupé')} leading={<IconBadge color="#8e8e93"><PowerOff size={16} color="#fff" /></IconBadge>} title="Couper le moteur" />
          <ListRow onClick={() => act('trunk:open', {})} leading={<IconBadge color="#a2845e"><Package size={16} color="#fff" /></IconBadge>} title="Ouvrir le coffre" />
        </ListGroup>
        {sel.role === 'owner' && (
          <ListGroup header="Clés">
            <ListRow onClick={openKeys} chevron leading={<IconBadge color="#5e5ce6"><KeyRound size={16} color="#fff" /></IconBadge>} title="Partager / gérer les clés" />
          </ListGroup>
        )}
      </div>
    </div>
  )
}
