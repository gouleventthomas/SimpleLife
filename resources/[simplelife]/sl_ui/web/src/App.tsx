import { useEffect, useState } from 'react'
import { useNuiEvent } from '@/hooks/useNuiEvent'
import { fetchNui } from '@/lib/fetchNui'
import CharSelect from '@/screens/CharSelect'
import type { CharSelectPayload } from '@/screens/CharSelect'
import CharCreate from '@/screens/CharCreate'
import type { CharCreatePayload } from '@/screens/CharCreate'
import Menu from '@/screens/Menu'
import type { MenuPayload } from '@/screens/Menu'
import InputPrompt from '@/screens/InputPrompt'
import type { InputPayload } from '@/screens/InputPrompt'
import Inventory from '@/screens/Inventory'
import type { InventoryPayload } from '@/screens/Inventory'
import ToastHost from '@/components/Toast'

// An interactive screen pushed by client/bridge.lua via SendNUIMessage('open', …).
// payload shape depends on `screen`; each screen validates/narrows its own props.
interface OpenMessage {
  screen: string
  payload: unknown
}

// A 'notify' message from sl_ui/client/bridge.lua.
interface NotifyMessage {
  kind?: string
  message?: string
}

export default function App() {
  const [active, setActive] = useState<OpenMessage | null>(null)
  // Last create-error reason text, surfaced ON the re-opened CharCreate form (not
  // just as a transient toast) so a player whose create keeps failing always sees
  // why. Cleared when any screen (re)opens for a fresh attempt or another screen.
  const [createError, setCreateError] = useState<string | null>(null)

  useNuiEvent<OpenMessage>('open', (data) => {
    // NOTE: we deliberately do NOT clear createError here. The create-error path in
    // sl_identity fires notify('error') and THEN re-opens 'charcreate', so the error
    // captured by the notify handler must survive this re-open to reach the form.
    setActive(data)
  })
  useNuiEvent('closeAll', () => {
    setActive(null)
    setCreateError(null)
  })
  // Capture error toasts so the reason is also legible on the create form. Errors
  // are sl_identity create failures (NAME_LEN / DB_ERROR / DUPLICATE / ...).
  useNuiEvent<NotifyMessage>('notify', (data) => {
    if (data && data.kind === 'error' && data.message) {
      setCreateError(data.message)
    }
  })
  // NOTE: 'hudUpdate' is intentionally ignored for now — the in-world HUD was removed
  // (to be redesigned). The Lua side may still push it; it is simply a no-op here.

  // Tell the Lua bridge we're mounted (listeners attached) so it can flush any
  // one-shot message — notably the very first 'open' — that was sent before this
  // NUI finished loading. Without this the character screen can be lost on a fast
  // connect and the player is left on a black hold screen.
  useEffect(() => {
    fetchNui('uiReady', {})
  }, [])

  // A screen is up: render it full-viewport with pointer events.
  if (active) {
    return (
      <>
        <div className="pointer-events-auto fixed inset-0 select-none text-amber-50">
          <Screen screen={active.screen} payload={active.payload} serverError={createError} />
        </div>
        <ToastHost />
      </>
    )
  }

  // Idle: no HUD for now (removed, to be redesigned) — only transient toasts.
  return <ToastHost />
}

// Switch on screen name -> the matching overlay. Unknown screens render nothing
// (defensive: a screen the React build doesn't know about must never softlock).
function Screen({ screen, payload, serverError }: OpenMessage & { serverError?: string | null }) {
  switch (screen) {
    case 'charselect':
      return <CharSelect {...(payload as CharSelectPayload)} />
    case 'charcreate':
      return <CharCreate {...(payload as CharCreatePayload)} serverError={serverError} />
    case 'menu':
      return <Menu {...(payload as MenuPayload)} />
    case 'input':
      return <InputPrompt {...(payload as InputPayload)} />
    case 'inventory':
      return <Inventory {...(payload as InventoryPayload)} />
    default:
      return null
  }
}
