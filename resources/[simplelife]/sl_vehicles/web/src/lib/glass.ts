import type { CSSProperties } from 'react'

function hexToRgb(hex?: string): [number, number, number] {
  let h = (hex || '').replace('#', '').trim()
  if (h.length === 3) h = h.split('').map((c) => c + c).join('')
  const int = parseInt(h, 16)
  if (h.length !== 6 || !Number.isFinite(int)) return [59, 169, 224]
  return [(int >> 16) & 255, (int >> 8) & 255, int & 255]
}
const clamp = (v: number) => Math.max(0, Math.min(255, Math.round(v)))

export interface Glass {
  accent: string
  panel: CSSProperties
  selected: CSSProperties
  bar: CSSProperties
  confirm: CSSProperties
}

// Liquid-Glass set from one accent hex (no backdrop-filter — CEF can't blur the game).
export function glass(accentHex?: string): Glass {
  const [r, g, b] = hexToRgb(accentHex)
  const a = `${r}, ${g}, ${b}`
  const tint = (base: number, c: number, t: number) => clamp(base + c * t)
  const top = `rgba(${tint(20, r, 0.17)}, ${tint(22, g, 0.17)}, ${tint(28, b, 0.17)}, 0.80)`
  const bot = `rgba(${tint(12, r, 0.12)}, ${tint(14, g, 0.12)}, ${tint(19, b, 0.12)}, 0.88)`
  return {
    accent: `rgb(${a})`,
    panel: {
      background: `linear-gradient(180deg, ${top}, ${bot})`,
      boxShadow: '0 18px 55px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.18)',
    },
    selected: {
      background: 'linear-gradient(180deg, rgba(255,255,255,0.22), rgba(255,255,255,0.10))',
      border: '1px solid rgba(255,255,255,0.28)',
      boxShadow: `0 0 22px rgba(${a}, 0.30), inset 0 1px 0 rgba(255,255,255,0.4)`,
    },
    bar: { background: `rgb(${a})`, boxShadow: `0 0 10px rgba(${a}, 0.9)` },
    confirm: {
      background: `linear-gradient(180deg, rgba(${a}, 0.40), rgba(${a}, 0.20))`,
      border: `1px solid rgba(${a}, 0.5)`,
      boxShadow: `0 0 18px rgba(${a}, 0.3)`,
    },
  }
}
