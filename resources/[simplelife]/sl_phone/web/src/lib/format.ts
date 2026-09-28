// 0612345678 -> 06 12 34 56 78. Accepts anything (oxmysql may hand back non-strings).
export function formatNumber(n?: unknown): string {
  return String(n ?? '').replace(/(\d{2})(?=\d)/g, '$1 ').trim()
}

// Parse a timestamp from oxmysql, which may be a "YYYY-MM-DD HH:MM:SS" string, an ISO
// string, a Date object, or an epoch number. Never call .replace on a non-string.
function parse(ts?: unknown): Date | null {
  if (ts == null || ts === '') return null
  if (ts instanceof Date) return isNaN(ts.getTime()) ? null : ts
  if (typeof ts === 'number') {
    const d = new Date(ts)
    return isNaN(d.getTime()) ? null : d
  }
  const d = new Date(String(ts).replace(' ', 'T'))
  return isNaN(d.getTime()) ? null : d
}

export function timeAgo(ts?: unknown): string {
  const d = parse(ts)
  if (!d) return ''
  const diff = (Date.now() - d.getTime()) / 1000
  if (diff < 60) return "à l'instant"
  if (diff < 3600) return `il y a ${Math.floor(diff / 60)} min`
  if (diff < 86400) return `il y a ${Math.floor(diff / 3600)} h`
  return d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })
}

export function clockTime(ts?: unknown): string {
  const d = parse(ts)
  if (!d) return ''
  return d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
}

export function callDuration(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds || 0))
  const m = Math.floor(s / 60)
  return `${m}:${(s % 60).toString().padStart(2, '0')}`
}

export function initials(name?: string, number?: string): string {
  const src = String(name || number || '?').trim()
  return (src[0] || '?').toUpperCase()
}

export function formatMoney(n?: number | string): string {
  const v = Math.round(Number(n) || 0)
  return `${v.toLocaleString('fr-FR')} $`
}
