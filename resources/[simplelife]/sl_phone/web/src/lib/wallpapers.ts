export interface Wallpaper {
  id: string
  label: string
  css: string
}

// Image wallpapers live in public/wallpapers/<id>.jpg (served from html/ in-game). Add more
// entries here as new images are dropped in.
export const WALLPAPERS: Wallpaper[] = [
  { id: 'aurora', label: 'Aurora', css: "url('wallpapers/aurora.jpg') center / cover no-repeat" },
  { id: 'city', label: 'Los Santos', css: "url('wallpapers/city.jpg') center / cover no-repeat" },
]

export function wallpaperCss(id: string): string {
  return (WALLPAPERS.find((w) => w.id === id) ?? WALLPAPERS[0]).css
}
