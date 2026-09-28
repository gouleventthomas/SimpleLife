import type { AppDef } from '../types'
import { getComponent } from '../apps/registry'
import { ComingSoon } from '../apps/ComingSoon'

// Each app fills the screen below the status bar and renders its OWN header (AppHeader)
// so apps with internal navigation control the back button. The screen has a solid dark
// background behind the app content.
export function AppShell({ appDef }: { appDef: AppDef }) {
  const Comp = getComponent(appDef.id)
  return (
    <div className="h-full" style={{ background: '#000000', animation: 'app-in 0.2s ease' }}>
      {Comp ? <Comp /> : <ComingSoon appDef={appDef} />}
    </div>
  )
}
