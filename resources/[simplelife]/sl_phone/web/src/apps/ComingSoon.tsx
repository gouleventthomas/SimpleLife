import { usePhone } from '../store'
import { appIcon } from '../lib/icons'
import type { AppDef } from '../types'
import { AppHeader, Squircle } from './ui'

export function ComingSoon({ appDef }: { appDef: AppDef }) {
  const goHome = usePhone((s) => s.goHome)
  const Icon = appIcon(appDef.icon)
  return (
    <div className="h-full flex flex-col">
      <AppHeader title={appDef.label} onBack={goHome} />
      <div className="flex-1 flex flex-col items-center justify-center gap-4 text-center px-10">
        <Squircle color={appDef.color} size={80}>
          <Icon size={40} color="#fff" />
        </Squircle>
        <div className="text-white text-[20px] font-semibold">{appDef.label}</div>
        <p className="text-white/55 text-[15px] leading-relaxed">arrive bientôt</p>
        <span className="mt-1 text-[12px] text-white/45 rounded-full px-3 py-1" style={{ background: 'rgba(118,118,128,0.24)' }}>
          Phase {appDef.phase}
        </span>
      </div>
    </div>
  )
}
