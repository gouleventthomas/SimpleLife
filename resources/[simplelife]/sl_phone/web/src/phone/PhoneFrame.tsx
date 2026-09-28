import { useEffect } from 'react'
import { usePhone } from '../store'
import { wallpaperCss } from '../lib/wallpapers'
import { frameColor } from '../lib/frames'
import { StatusBar } from './StatusBar'
import { HomeScreen } from './HomeScreen'
import { AppShell } from './AppShell'
import { CallScreen } from '../components/CallScreen'

export function PhoneFrame() {
  const device = usePhone((s) => s.device)
  const route = usePhone((s) => s.route)
  const closing = usePhone((s) => s.closing)
  const close = usePhone((s) => s.close)
  const goHome = usePhone((s) => s.goHome)
  const goBack = usePhone((s) => s.goBack)
  const callState = usePhone((s) => s.callState)
  const inCall = callState.status !== 'idle'

  // Esc OR right-click = hierarchical back (no-op during a call).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); goBack() }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [goBack])

  if (!device) return null
  const appDef = route !== 'home' ? device.apps.find((a) => a.id === route) ?? null : null
  const wp = wallpaperCss(device.settings.wallpaper)
  const brightness = device.settings.brightness ?? 1
  const caseColor = frameColor(device.settings.frame)

  return (
    <div
      className="fixed inset-0 flex items-end justify-end"
      onMouseDown={(e) => { if (!inCall && e.target === e.currentTarget) close() }}
      onContextMenu={(e) => { e.preventDefault(); goBack() }}
    >
      <div
        className="relative m-7"
        style={{
          width: 380, height: 812,
          animation: closing ? 'phone-out 0.2s ease forwards' : 'phone-in 0.3s cubic-bezier(0.22,1,0.36,1)',
        }}
      >
        {/* coloured case / bezel */}
        <div className="absolute inset-0 rounded-[3.4rem] shadow-[0_40px_90px_rgba(0,0,0,0.78)]" style={{ background: caseColor, padding: 10 }}>
          {/* screen */}
          <div
            className="w-full h-full rounded-[2.85rem] overflow-hidden relative ring-1 ring-black/40"
            style={{ background: wp, filter: `brightness(${0.55 + brightness * 0.45})` }}
          >
            <StatusBar />
            <div className="absolute inset-0 pt-11">
              {appDef ? <AppShell appDef={appDef} /> : <HomeScreen />}
            </div>
            {inCall && <CallScreen />}
            {/* dynamic island */}
            <div className="absolute top-2 left-1/2 -translate-x-1/2 w-[92px] h-[26px] bg-black rounded-full z-50" />
            {/* home indicator */}
            {!inCall && (
              <button
                onClick={goHome}
                title="Accueil"
                className="absolute bottom-1.5 left-1/2 -translate-x-1/2 w-[120px] h-[5px] rounded-full bg-white/80 z-50 cursor-pointer hover:bg-white"
              />
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
