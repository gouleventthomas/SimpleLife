import { useEffect, useState } from 'react'
import { Check, Image as ImageIcon, Smartphone, Sun, Moon, Share2, Bell } from 'lucide-react'
import { usePhone } from '../store'
import { WALLPAPERS } from '../lib/wallpapers'
import { FRAMES } from '../lib/frames'
import { formatNumber } from '../lib/format'
import { AppHeader, LargeHeader, ListGroup, ListRow, IconBadge, Toggle, Avatar } from './ui'

export function SettingsApp() {
  const device = usePhone((s) => s.device)!
  const setBackHandler = usePhone((s) => s.setBackHandler)
  const applySettings = usePhone((s) => s.applySettings)
  const saveSettings = usePhone((s) => s.saveSettings)
  const [page, setPage] = useState<null | 'wallpaper' | 'frame'>(null)
  const [bright, setBright] = useState(device.settings.brightness ?? 1)
  const [dark, setDark] = useState(true)
  const [prox, setProx] = useState(true)
  const [sound, setSound] = useState(true)

  const pageOpen = page !== null
  useEffect(() => {
    if (pageOpen) setBackHandler(() => { setPage(null); return true })
    else setBackHandler(null)
    return () => setBackHandler(null)
  }, [pageOpen, setBackHandler])

  if (page === 'wallpaper') {
    return (
      <div className="h-full flex flex-col">
        <AppHeader title="Fond d'écran" onBack={() => setPage(null)} backLabel="Réglages" />
        <div className="flex-1 overflow-y-auto no-scrollbar px-4 py-2">
          <div className="grid grid-cols-3 gap-3">
            {WALLPAPERS.map((w) => (
              <button key={w.id} onClick={() => saveSettings({ wallpaper: w.id })} className="relative aspect-[9/16] rounded-2xl overflow-hidden ring-1 ring-white/10" style={{ background: w.css }}>
                {device.settings.wallpaper === w.id && (
                  <div className="absolute inset-0 flex items-center justify-center bg-black/30">
                    <div className="w-7 h-7 rounded-full bg-[#0a84ff] flex items-center justify-center"><Check size={16} color="#fff" /></div>
                  </div>
                )}
                <span className="absolute bottom-1 inset-x-0 text-center text-[10px] text-white/90 drop-shadow">{w.label}</span>
              </button>
            ))}
          </div>
        </div>
      </div>
    )
  }

  if (page === 'frame') {
    return (
      <div className="h-full flex flex-col">
        <AppHeader title="Couleur du téléphone" onBack={() => setPage(null)} backLabel="Réglages" />
        <div className="flex-1 overflow-y-auto no-scrollbar px-4 py-4">
          <div className="grid grid-cols-4 gap-4">
            {FRAMES.map((f) => (
              <button key={f.id} onClick={() => saveSettings({ frame: f.id })} className="flex flex-col items-center gap-1.5">
                <div className="w-14 h-14 rounded-full ring-2 ring-white/15 flex items-center justify-center shadow-md" style={{ background: f.color }}>
                  {device.settings.frame === f.id && <Check size={20} color="#fff" />}
                </div>
                <span className="text-[11px] text-white/70">{f.label}</span>
              </button>
            ))}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col">
      <LargeHeader title="Réglages" />
      <div className="flex-1 overflow-y-auto no-scrollbar pt-1 pb-6">
        <ListGroup>
          <ListRow
            leading={<Avatar number={device.number} size={52} color="#3a3a3c" />}
            title={<span className="text-[17px] font-semibold">Mon téléphone</span>}
            subtitle={formatNumber(device.number)}
            chevron
          />
        </ListGroup>

        <ListGroup>
          <ListRow leading={<IconBadge color="#ff9500"><ImageIcon size={17} color="#fff" /></IconBadge>} title="Fond d'écran" chevron onClick={() => setPage('wallpaper')} />
          <ListRow leading={<IconBadge color="#ff2d55"><Smartphone size={17} color="#fff" /></IconBadge>} title="Couleur du téléphone" chevron onClick={() => setPage('frame')} />
        </ListGroup>

        <ListGroup header="Affichage">
          <ListRow
            leading={<IconBadge color="#0a84ff"><Sun size={17} color="#fff" /></IconBadge>}
            title="Luminosité"
            right={
              <input
                type="range" min={0.2} max={1} step={0.05} value={bright}
                onChange={(e) => { const v = parseFloat(e.target.value); setBright(v); applySettings({ brightness: v }) }}
                onPointerUp={() => saveSettings({ brightness: bright })}
                className="w-[120px] accent-[#0a84ff]"
              />
            }
          />
          <ListRow leading={<IconBadge color="#5e5ce6"><Moon size={17} color="#fff" /></IconBadge>} title="Mode sombre" right={<Toggle on={dark} onChange={setDark} />} />
        </ListGroup>

        <ListGroup header="Connectivité" footer="Les réglages d'apparence sont enregistrés sur l'appareil.">
          <ListRow leading={<IconBadge color="#34c759"><Share2 size={17} color="#fff" /></IconBadge>} title="Partage de proximité" right={<Toggle on={prox} onChange={setProx} />} />
          <ListRow leading={<IconBadge color="#ff3b30"><Bell size={17} color="#fff" /></IconBadge>} title="Notifications sonores" right={<Toggle on={sound} onChange={setSound} />} />
        </ListGroup>

        <div className="text-center text-white/25 text-[11px] select-text">SimpleLife Phone · {device.uuid.slice(0, 8)}</div>
      </div>
    </div>
  )
}
