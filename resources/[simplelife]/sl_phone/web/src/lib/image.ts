// Process a raw camera capture (a data URI from screenshot-basic) into { full, thumb } JPEG
// data URIs, shrinking them before they're stored base64 in the DB. In PORTRAIT mode the
// center of the (landscape) screenshot is cropped to a 9:16 frame first. Always resolves —
// falls back to the original on any failure.
export function processCapture(dataUri: string, portrait: boolean): Promise<{ full: string; thumb: string }> {
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => {
      const iw = img.width || 1
      const ih = img.height || 1
      const sh = ih
      let sw = iw
      let sx = 0
      if (portrait) {
        sw = Math.min(iw, Math.round(ih * 9 / 16))
        sx = Math.round((iw - sw) / 2)
      }
      const make = (maxW: number, q: number): string => {
        const scale = Math.min(1, maxW / sw)
        const w = Math.max(1, Math.round(sw * scale))
        const h = Math.max(1, Math.round(sh * scale))
        const c = document.createElement('canvas')
        c.width = w
        c.height = h
        const ctx = c.getContext('2d')
        if (!ctx) return dataUri
        ctx.drawImage(img, sx, 0, sw, sh, 0, 0, w, h)
        try { return c.toDataURL('image/jpeg', q) } catch { return dataUri }
      }
      resolve({ full: make(portrait ? 960 : 1280, 0.72), thumb: make(320, 0.6) })
    }
    img.onerror = () => resolve({ full: dataUri, thumb: dataUri })
    img.src = dataUri
  })
}
