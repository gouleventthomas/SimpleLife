import { useEffect, useState } from 'react'
import { Wifi } from 'lucide-react'

export function StatusBar() {
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000)
    return () => clearInterval(t)
  }, [])
  const hh = now.getHours().toString().padStart(2, '0')
  const mm = now.getMinutes().toString().padStart(2, '0')

  return (
    <div className="absolute top-0 inset-x-0 h-11 flex items-end justify-between px-7 pb-1.5 z-50 text-white select-none">
      <div className="flex items-center gap-1 text-[15px] font-semibold tracking-tight">
        <span>{hh}:{mm}</span>
        <svg width="11" height="11" viewBox="0 0 24 24" fill="white" aria-hidden><path d="M2 11l20-9-9 20-2-9-9-2z" /></svg>
      </div>
      <div className="flex items-end gap-1.5">
        <div className="flex items-end gap-[2px] h-3">
          <span className="w-[3px] h-[5px] bg-white rounded-[1px]" />
          <span className="w-[3px] h-[7px] bg-white rounded-[1px]" />
          <span className="w-[3px] h-[9px] bg-white rounded-[1px]" />
          <span className="w-[3px] h-[11px] bg-white rounded-[1px]" />
        </div>
        <Wifi size={16} />
        <div className="flex items-center">
          <div className="w-[22px] h-[11px] rounded-[3px] border border-white/70 p-[1.5px]">
            <div className="h-full bg-white rounded-[1px]" style={{ width: '82%' }} />
          </div>
          <div className="w-[1.5px] h-[4px] bg-white/70 rounded-r ml-[1px]" />
        </div>
      </div>
    </div>
  )
}
