import { create } from 'zustand'
import type { DeviceState, PhoneSettings, CallState, PhoneNotification, CallEventPayload, SmsPush } from './types'
import { rpc } from './lib/rpc'
import { fetchNui } from './lib/fetchNui'

const OUT_MS = 200
let _nid = 0
const nextNotifId = () => ++_nid

const CALL_ERR: Record<string, string> = {
  OFFLINE: 'Le correspondant est injoignable.',
  UNKNOWN_NUMBER: 'Numéro inconnu.',
  BUSY: 'Vous êtes déjà en appel.',
  BUSY_TARGET: 'Le correspondant est déjà en ligne.',
  SELF: 'Vous ne pouvez pas vous appeler.',
  CALLS_DISABLED: 'Les appels sont désactivés.',
  NO_PHONE: 'Aucun téléphone.',
  INVALID: 'Numéro invalide.',
}

interface PhoneStore {
  open: boolean
  closing: boolean
  device: DeviceState | null
  route: string
  callState: CallState
  notifications: PhoneNotification[]
  badges: Record<string, number>
  smsBump: number
  pendingThread: string | null
  activeThread: string | null
  backHandler: (() => boolean) | null

  setOpen: (d: DeviceState) => void
  close: () => void
  closeLocal: () => void
  goHome: () => void
  openApp: (id: string) => void
  goBack: () => void
  setBackHandler: (fn: (() => boolean) | null) => void
  openMessagesWith: (number: string) => void
  consumePendingThread: () => string | null
  installApp: (id: string) => Promise<void>
  uninstallApp: (id: string) => Promise<void>

  applySettings: (patch: Partial<PhoneSettings>) => void
  saveSettings: (patch: Partial<PhoneSettings>) => Promise<void>

  handleCallEvent: (p: CallEventPayload) => void
  startCall: (number: string) => Promise<void>
  acceptCall: () => void
  declineCall: () => void
  hangupCall: () => void

  handleSms: (d: SmsPush) => void
  pushNotification: (n: { app: string; title: string; body: string }) => void
  dismissNotification: (id: number) => void
  setActiveThread: (n: string | null) => void
  syncMessagesBadge: (unread: number) => void
}

function finishClose(set: (p: Partial<PhoneStore>) => void, get: () => PhoneStore) {
  set({ closing: true })
  // Only actually hide if we are STILL closing when the animation ends. A reopen during the
  // window (e.g. an incoming call's auto-open) clears `closing` via setOpen, so this no-ops and
  // doesn't wipe the freshly-opened phone / call screen.
  setTimeout(() => {
    if (get().closing) set({ open: false, closing: false, route: 'home', callState: { status: 'idle' } })
  }, OUT_MS)
}

export const usePhone = create<PhoneStore>((set, get) => ({
  open: false,
  closing: false,
  device: null,
  route: 'home',
  callState: { status: 'idle' },
  notifications: [],
  badges: {},
  smsBump: 0,
  pendingThread: null,
  activeThread: null,
  backHandler: null,

  setOpen: (d) => set({ open: true, closing: false, device: d, route: 'home' }),
  close: () => { finishClose(set, get); fetchNui('phone:close', {}) },
  closeLocal: () => finishClose(set, get),
  goHome: () => set({ route: 'home' }),
  openApp: (id) => set((s) => ({ route: id, badges: { ...s.badges, [id]: 0 } })),
  // Hierarchical back: let the open app pop one internal level (thread->list, editor->list);
  // if it can't, go app->home; if already home, put the phone away. Locked during a call.
  goBack: () => {
    if (get().callState.status !== 'idle') return
    const h = get().backHandler
    if (h && h()) return
    if (get().route !== 'home') { get().goHome(); return }
    get().close()
  },
  setBackHandler: (fn) => set({ backHandler: fn }),
  openMessagesWith: (number) =>
    set((s) => ({ route: 'messages', pendingThread: number, badges: { ...s.badges, messages: 0 } })),
  consumePendingThread: () => {
    const t = get().pendingThread
    if (t) set({ pendingThread: null })
    return t
  },

  installApp: async (id) => {
    const fallback = (get().device?.removed || []).filter((x) => x !== id)
    const r = await rpc<{ ok: boolean; removed?: string[] }>('store:install', { app: id }, { ok: true, removed: fallback })
    const d = get().device
    if (r.ok && r.removed && d) set({ device: { ...d, removed: r.removed } })
  },
  uninstallApp: async (id) => {
    const fallback = [...(get().device?.removed || []), id]
    const r = await rpc<{ ok: boolean; reason?: string; removed?: string[] }>('store:uninstall', { app: id }, { ok: true, removed: fallback })
    const d = get().device
    if (r.ok && r.removed && d) set({ device: { ...d, removed: r.removed } })
    else if (!r.ok && r.reason === 'MANDATORY') get().pushNotification({ app: 'store', title: 'iFruit Store', body: 'App système — non supprimable.' })
  },

  applySettings: (patch) => {
    const d = get().device
    if (d) set({ device: { ...d, settings: { ...d.settings, ...patch } } })
  },
  saveSettings: async (patch) => {
    get().applySettings(patch)
    const res = await rpc<{ ok: boolean; settings?: PhoneSettings }>('setSettings', { patch }, { ok: true })
    const d = get().device
    if (res.ok && res.settings && d) set({ device: { ...d, settings: res.settings } })
  },

  handleCallEvent: ({ event, call }) => {
    if (event === 'incoming') set({ callState: { status: 'incoming', callId: call.callId, number: call.number, name: call.name } })
    else if (event === 'outgoing') set({ callState: { status: 'outgoing', callId: call.callId, number: call.number, name: call.name } })
    else if (event === 'accepted') set((s) => ({ callState: { ...s.callState, status: 'active', since: Date.now() } }))
    else if (event === 'ended') {
      set((s) => ({ callState: { ...s.callState, status: 'ended', reason: call?.reason } }))
      setTimeout(() => set((s) => (s.callState.status === 'ended' ? { callState: { status: 'idle' } } : {})), 1400)
    }
  },
  startCall: async (number) => {
    const res = await rpc<{ ok: boolean; reason?: string }>('calls:start', { number }, { ok: false, reason: 'OFFLINE' })
    if (!res.ok) get().pushNotification({ app: 'phone', title: 'Appel', body: CALL_ERR[res.reason || ''] || 'Appel impossible.' })
  },
  acceptCall: () => { const id = get().callState.callId; if (id) rpc('calls:accept', { callId: id }) },
  declineCall: () => { const id = get().callState.callId; if (id) rpc('calls:decline', { callId: id }) },
  hangupCall: () => { const id = get().callState.callId; if (id) rpc('calls:hangup', { callId: id }) },

  handleSms: (d) => {
    // If the matching thread is already open, the thread auto-refreshes (smsBump) and marks it
    // read server-side — so don't raise a banner or bump the home badge for it.
    const viewing = !!(d.from && d.from === get().activeThread)
    if (!viewing) get().pushNotification({ app: 'messages', title: d.name || d.from, body: d.body })
    set((s) => ({
      smsBump: s.smsBump + 1,
      badges: viewing ? s.badges : { ...s.badges, messages: (s.badges.messages || 0) + 1 },
    }))
  },
  pushNotification: (n) => {
    const id = nextNotifId()
    set((s) => ({ notifications: [...s.notifications, { id, ...n }].slice(-4) }))
    setTimeout(() => get().dismissNotification(id), 4500)
  },
  dismissNotification: (id) => set((s) => ({ notifications: s.notifications.filter((x) => x.id !== id) })),
  setActiveThread: (n) => set({ activeThread: n }),
  syncMessagesBadge: (unread) => set((s) => ({ badges: { ...s.badges, messages: Math.max(0, unread) } })),
}))
