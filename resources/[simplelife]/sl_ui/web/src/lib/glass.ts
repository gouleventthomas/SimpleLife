import type { CSSProperties } from 'react'

// Parse a #rgb / #rrggbb hex into [r,g,b]; falls back to the default cyan on garbage.
function hexToRgb(hex?: string): [number, number, number] {
  let h = (hex || '').replace('#', '').trim()
  if (h.length === 3) h = h.split('').map((c) => c + c).join('')
  const int = parseInt(h, 16)
  if (h.length !== 6 || !Number.isFinite(int)) return [166, 227, 242]
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

// Build the whole Liquid Glass style set from ONE accent hex. The dark translucent panel
// is tinted slightly toward the accent (so an ATM can be "green glass", a shop "amber glass",
// etc.); the selection bar/glow and the confirm button carry the accent at full strength.
// The bright white selection fill stays neutral so text is always legible.
export function glass(accentHex?: string): Glass {
  const [r, g, b] = hexToRgb(accentHex)
  const a = `${r}, ${g}, ${b}`
  const tint = (base: number, c: number, t: number) => clamp(base + c * t)
  const top = `rgba(${tint(20, r, 0.17)}, ${tint(22, g, 0.17)}, ${tint(28, b, 0.17)}, 0.64)`
  const bot = `rgba(${tint(12, r, 0.12)}, ${tint(14, g, 0.12)}, ${tint(19, b, 0.12)}, 0.72)`
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
      background: `linear-gradient(180deg, rgba(${a}, 0.32), rgba(${a}, 0.16))`,
      border: `1px solid rgba(${a}, 0.45)`,
      boxShadow: `0 0 18px rgba(${a}, 0.28)`,
    },
  }
}
