// iPhone case / bezel colours (the "Couleur du téléphone" setting). The frame is the visible
// border around the screen; pick matches the playful colored iPhones.
export interface Frame {
  id: string
  label: string
  color: string
}

export const FRAMES: Frame[] = [
  { id: 'coral', label: 'Corail', color: '#f56b86' },
  { id: 'midnight', label: 'Minuit', color: '#1c2230' },
  { id: 'graphite', label: 'Graphite', color: '#3a3a3c' },
  { id: 'silver', label: 'Argent', color: '#d8dadc' },
  { id: 'gold', label: 'Or', color: '#e6caa0' },
  { id: 'blue', label: 'Bleu', color: '#2f6db0' },
  { id: 'green', label: 'Vert', color: '#5aa979' },
  { id: 'purple', label: 'Violet', color: '#8a6fd0' },
  { id: 'red', label: 'Rouge', color: '#c23b3b' },
  { id: 'yellow', label: 'Jaune', color: '#ebd27a' },
]

export function frameColor(id?: string): string {
  return (FRAMES.find((f) => f.id === id) ?? FRAMES[0]).color
}
