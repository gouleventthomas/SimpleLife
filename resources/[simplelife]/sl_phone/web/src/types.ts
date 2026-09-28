export interface PhoneSettings {
  wallpaper: string
  brightness: number
  frame?: string
  [k: string]: unknown
}

export interface AppDef {
  id: string
  label: string
  icon: string
  color: string
  phase: number
  mandatory?: boolean
}

export interface DeviceState {
  uuid: string
  number: string
  settings: PhoneSettings
  apps: AppDef[]
  dock: string[]
  removed?: string[]
  accent?: string
  env?: string
}

// ── comms (Phase 1) ───────────────────────────────────────────────────────────
export interface Contact {
  id: number
  name: string
  number: string
  favorite: number
}

export interface Message {
  id: number
  sender: string
  receiver: string
  body: string
  kind?: string
  amount?: number
  created_at: string
}

export interface BankTx {
  id: number
  from_number: string
  to_number: string
  amount: number
  reason?: string | null
  kind: string
  dir: 'in' | 'out'
  created_at: string
}

export interface PayRequest {
  id: number
  number: string
  name?: string | null
  amount: number
  reason?: string | null
  status?: string
  created_at: string
}

export interface CryptoHolding {
  coin: string
  amount: string | number
}

export interface CoinDef {
  id: string
  label: string
  symbol: string
  color: string
}

export interface Conversation {
  number: string
  name?: string | null
  last_body: string | null
  last_at: string
  unread: number
}

export interface Recent {
  id: number
  dir: 'in' | 'out'
  number: string
  name?: string | null
  accepted: number
  duration: number
  created_at: string
}

export interface Note {
  id: number
  title: string
  body: string
  updated_at: string
}

// ── calls / notifications ───────────────────────────────────────────────────────
export type CallStatus = 'idle' | 'incoming' | 'outgoing' | 'active' | 'ended'

export interface CallState {
  status: CallStatus
  callId?: number
  number?: string
  name?: string | null
  since?: number
  reason?: string
}

export interface PhoneNotification {
  id: number
  app: string
  title: string
  body: string
}

// ── server -> NUI push payloads ──────────────────────────────────────────────────
export interface CallEventPayload {
  event: 'incoming' | 'outgoing' | 'accepted' | 'ended'
  call: { callId: number; number?: string; name?: string | null; reason?: string; duration?: number }
}
export interface SmsPush {
  id?: number
  from: string
  name?: string | null
  body: string
}
export interface NotifyPush {
  app: string
  title: string
  body: string
}
