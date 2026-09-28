import { useEffect, useState } from 'react'
import { Phone, Delete, PhoneIncoming, PhoneOutgoing, PhoneMissed, Clock, User, Grid3x3 } from 'lucide-react'
import { usePhone } from '../store'
import { rpc } from '../lib/rpc'
import type { Recent, Contact } from '../types'
import { formatNumber, timeAgo, callDuration } from '../lib/format'
import { Avatar, Empty, LargeHeader, ListRow, TabBar } from './ui'

type Tab = 'recents' | 'contacts' | 'keypad'

const MOCK_RECENTS: Recent[] = [
  { id: 1, dir: 'in', number: '0698765432', name: 'Maman', accepted: 1, duration: 92, created_at: '2026-06-28 11:30:00' },
  { id: 2, dir: 'out', number: '0612340000', name: null, accepted: 0, duration: 0, created_at: '2026-06-28 10:05:00' },
]

function Recents({ onCall }: { onCall: (n: string) => void }) {
  const [list, setList] = useState<Recent[]>([])
  useEffect(() => {
    rpc<{ ok: boolean; recents: Recent[] }>('calls:recents', {}, { ok: true, recents: MOCK_RECENTS }).then((r) => { if (r.ok) setList(r.recents) })
  }, [])
  return (
    <div className="h-full flex flex-col">
      <LargeHeader title="Récents" />
      <div className="flex-1 min-h-0 overflow-y-auto no-scrollbar">
        {!list.length ? (
          <Empty icon={<Phone size={40} />} label="Aucun appel récent" />
        ) : (
          <div className="rounded-[12px] overflow-hidden mx-4 mt-1 mb-4 divide-y" style={{ background: '#1c1c1e', borderColor: 'rgba(255,255,255,0.07)' }}>
            {list.map((r) => {
              const missed = r.dir === 'in' && r.accepted === 0
              const Icon = r.dir === 'out' ? PhoneOutgoing : missed ? PhoneMissed : PhoneIncoming
              return (
                <ListRow
                  key={r.id}
                  onClick={() => onCall(r.number)}
                  leading={<Avatar name={r.name} number={r.number} size={38} />}
                  title={<span className={missed ? 'text-[#ff453a]' : 'text-white'}>{r.name || formatNumber(r.number)}</span>}
                  subtitle={
                    <span className="flex items-center gap-1">
                      <Icon size={12} className={missed ? 'text-[#ff453a]' : r.dir === 'out' ? 'text-white/45' : 'text-[#34c759]'} />
                      {timeAgo(r.created_at)}{r.accepted ? ` · ${callDuration(r.duration)}` : ''}
                    </span>
                  }
                  right={<Phone size={18} className="text-[#34c759] shrink-0" />}
                />
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

function ContactsCall({ onCall }: { onCall: (n: string) => void }) {
  const [list, setList] = useState<Contact[]>([])
  useEffect(() => {
    rpc<{ ok: boolean; contacts: Contact[] }>('contacts:list', {}, { ok: true, contacts: [] }).then((r) => { if (r.ok) setList(r.contacts) })
  }, [])
  return (
    <div className="h-full flex flex-col">
      <LargeHeader title="Contacts" />
      <div className="flex-1 min-h-0 overflow-y-auto no-scrollbar">
        {!list.length ? (
          <Empty icon={<User size={40} />} label="Aucun contact" />
        ) : (
          <div className="rounded-[12px] overflow-hidden mx-4 mt-1 mb-4 divide-y" style={{ background: '#1c1c1e', borderColor: 'rgba(255,255,255,0.07)' }}>
            {list.map((c) => (
              <ListRow
                key={c.id}
                onClick={() => onCall(c.number)}
                leading={<Avatar name={c.name} size={38} color={c.favorite ? '#0a84ff' : '#3a3a44'} />}
                title={c.name}
                subtitle={formatNumber(c.number)}
                right={<Phone size={18} className="text-[#34c759] shrink-0" />}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

const KEYPAD: { d: string; sub: string }[] = [
  { d: '1', sub: '' }, { d: '2', sub: 'ABC' }, { d: '3', sub: 'DEF' },
  { d: '4', sub: 'GHI' }, { d: '5', sub: 'JKL' }, { d: '6', sub: 'MNO' },
  { d: '7', sub: 'PQRS' }, { d: '8', sub: 'TUV' }, { d: '9', sub: 'WXYZ' },
  { d: '*', sub: '' }, { d: '0', sub: '+' }, { d: '#', sub: '' },
]

function Keypad({ onCall }: { onCall: (n: string) => void }) {
  const [num, setNum] = useState('')
  return (
    <div className="h-full flex flex-col items-center justify-end pb-4 px-6">
      <div className="h-16 flex items-center justify-center text-[34px] text-white tracking-wider font-light min-h-[4rem]">
        {formatNumber(num) || ' '}
      </div>
      <div className="grid grid-cols-3 gap-x-6 gap-y-3.5 mb-4">
        {KEYPAD.map((k) => (
          <button
            key={k.d}
            onClick={() => setNum((n) => (n + k.d).slice(0, 15))}
            className="w-[72px] h-[72px] rounded-full bg-white/[0.09] flex flex-col items-center justify-center active:bg-white/25 transition-colors leading-none"
          >
            <span className="text-[32px] text-white font-light">{k.d}</span>
            {k.sub && <span className="text-[10px] tracking-[0.12em] text-white/55 font-semibold mt-0.5">{k.sub}</span>}
          </button>
        ))}
      </div>
      <div className="grid grid-cols-3 items-center w-full max-w-[260px]">
        <span />
        <button
          onClick={() => num && onCall(num)}
          disabled={!num}
          className="justify-self-center w-[72px] h-[72px] rounded-full bg-[#34c759] flex items-center justify-center disabled:opacity-30 active:scale-90 transition-transform"
        >
          <Phone size={30} color="#fff" />
        </button>
        <button
          onClick={() => setNum((n) => n.slice(0, -1))}
          className="justify-self-center w-12 h-12 flex items-center justify-center text-white/70 active:opacity-50"
        >
          {num ? <Delete size={26} /> : null}
        </button>
      </div>
    </div>
  )
}

export function PhoneApp() {
  const startCall = usePhone((s) => s.startCall)
  const [tab, setTab] = useState<Tab>('recents')
  return (
    <div className="h-full flex flex-col">
      <div className="flex-1 min-h-0">
        {tab === 'recents' && <Recents onCall={startCall} />}
        {tab === 'contacts' && <ContactsCall onCall={startCall} />}
        {tab === 'keypad' && <Keypad onCall={startCall} />}
      </div>
      <TabBar
        active={tab}
        onSelect={(id) => setTab(id as Tab)}
        tabs={[
          { id: 'recents', label: 'Récents', icon: <Clock size={22} /> },
          { id: 'contacts', label: 'Contacts', icon: <User size={22} /> },
          { id: 'keypad', label: 'Clavier', icon: <Grid3x3 size={22} /> },
        ]}
      />
    </div>
  )
}
