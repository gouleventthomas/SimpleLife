import { Component, useEffect, type ReactNode } from 'react'
import { useNuiEvent } from './hooks/useNuiEvent'
import { fetchNui, inGame } from './lib/fetchNui'
import { usePhone } from './store'
import type { DeviceState, CallEventPayload, SmsPush, NotifyPush } from './types'
import { PhoneFrame } from './phone/PhoneFrame'
import { CameraView } from './components/CameraView'
import { Notifications } from './components/Notifications'
import { MOCK_DEVICE } from './dev'

// If anything in the phone UI throws while rendering, force-release NUI focus so the player
// is never left with a stuck cursor / locked controls, and reset the store so a re-open works.
class PhoneErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() { return { failed: true } }
  componentDidCatch() {
    fetchNui('phone:forceClose', {})
    usePhone.getState().closeLocal()
  }
  render() { return this.state.failed ? null : this.props.children }
}

export default function App() {
  const open = usePhone((s) => s.open)
  const route = usePhone((s) => s.route)
  const setOpen = usePhone((s) => s.setOpen)
  const closeLocal = usePhone((s) => s.closeLocal)
  const openApp = usePhone((s) => s.openApp)
  const handleCallEvent = usePhone((s) => s.handleCallEvent)
  const handleSms = usePhone((s) => s.handleSms)
  const pushNotification = usePhone((s) => s.pushNotification)

  useNuiEvent<DeviceState>('phone:open', (d) => setOpen(d))
  useNuiEvent('phone:close', () => closeLocal())
  useNuiEvent<CallEventPayload>('phone:call', (p) => handleCallEvent(p))
  useNuiEvent<SmsPush>('phone:sms', (d) => handleSms(d))
  useNuiEvent<NotifyPush>('phone:notify', (d) => pushNotification({ app: d.app, title: d.title, body: d.body }))
  useNuiEvent('camera:closed', () => openApp('gallery')) // leaving the viewfinder lands in the gallery

  useEffect(() => {
    fetchNui('uiReady', {})
    if (!inGame()) setOpen(MOCK_DEVICE) // browser preview (npm run dev)

    // Tell Lua when a text field is focused so it blocks movement keys from leaking into the
    // game while typing (the player can still walk/drive when NOT typing).
    const isField = (el: EventTarget | null) =>
      el instanceof HTMLElement && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')
    const onIn = (e: FocusEvent) => { if (isField(e.target)) fetchNui('phone:typing', { on: true }) }
    const onOut = (e: FocusEvent) => { if (isField(e.target)) fetchNui('phone:typing', { on: false }) }
    window.addEventListener('focusin', onIn)
    window.addEventListener('focusout', onOut)
    return () => {
      window.removeEventListener('focusin', onIn)
      window.removeEventListener('focusout', onOut)
    }
  }, [setOpen])

  return (
    <>
      {open && (
        <PhoneErrorBoundary>
          {route === 'camera' ? <CameraView /> : <PhoneFrame />}
        </PhoneErrorBoundary>
      )}
      <Notifications />
    </>
  )
}
