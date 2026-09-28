import type { DeviceState } from './types'

// Fake device used when previewing in a plain browser (npm run dev) — mirrors what the
// server sends on open so the whole phone is testable without FiveM.
export const MOCK_DEVICE: DeviceState = {
  uuid: 'dev-uuid-00000000',
  number: '0612345678',
  env: 'dev',
  accent: '#0a84ff',
  removed: ['crypto'],
  settings: { wallpaper: 'aurora', brightness: 1, frame: 'coral' },
  apps: [
    { id: 'calendrier',  label: 'Calendrier',   icon: 'Calendar',      color: '#ffffff', phase: 6, mandatory: true },
    { id: 'store',       label: 'iFruit Store',  icon: 'Store',         color: '#0a84ff', phase: 0, mandatory: true },
    { id: 'gallery',     label: 'Galerie',      icon: 'Image',         color: '#ff375f', phase: 2, mandatory: true },
    { id: 'horloge',     label: 'Horloge',      icon: 'Clock',         color: '#1c1c1e', phase: 6, mandatory: true },
    { id: 'calculatrice',label: 'Calculatrice', icon: 'Calculator',    color: '#ff9500', phase: 6 },
    { id: 'wallet',      label: 'Banque',       icon: 'Landmark',      color: '#30d158', phase: 3, mandatory: true },
    { id: 'crypto',      label: 'Crypto',       icon: 'Bitcoin',       color: '#ff9f0a', phase: 3 },
    { id: 'mail',        label: 'Mail',         icon: 'Mail',          color: '#0a84ff', phase: 5 },
    { id: 'notes',       label: 'Notes',        icon: 'StickyNote',    color: '#ffd60a', phase: 1 },
    { id: 'camera',      label: 'Caméra',       icon: 'Camera',        color: '#8e8e93', phase: 2, mandatory: true },
    { id: 'news',        label: 'Actus',        icon: 'Newspaper',     color: '#ff3b30', phase: 6 },
    { id: 'darkchat',    label: 'Dark Chat',    icon: 'Lock',          color: '#7c3aed', phase: 5 },
    { id: 'sante',       label: 'Santé',        icon: 'Heart',         color: '#ff2d55', phase: 6 },
    { id: 'contacts',    label: 'Contacts',     icon: 'Users',         color: '#5e9bff', phase: 1, mandatory: true },
    { id: 'evenements',  label: 'Événements',   icon: 'CalendarDays',  color: '#ff453a', phase: 6 },
    { id: 'vehicules',   label: 'Véhicules',    icon: 'Car',           color: '#34c759', phase: 6 },
    { id: 'proprietes',  label: 'Propriétés',   icon: 'Home',          color: '#0a84ff', phase: 6 },
    { id: 'marketplace', label: 'Marketplace',  icon: 'ShoppingBag',   color: '#ff9500', phase: 6 },
    { id: 'business',    label: 'Société',      icon: 'Briefcase',     color: '#5e5ce6', phase: 0 },
    { id: 'phone',       label: 'Téléphone',    icon: 'Phone',         color: '#34c759', phase: 1, mandatory: true },
    { id: 'messages',    label: 'Messages',     icon: 'MessageSquare', color: '#34c759', phase: 1, mandatory: true },
    { id: 'navigateur',  label: 'Internet',     icon: 'Compass',       color: '#0a84ff', phase: 6, mandatory: true },
    { id: 'settings',    label: 'Réglages',     icon: 'Settings',      color: '#8e8e93', phase: 0, mandatory: true },
  ],
  dock: ['phone', 'messages', 'navigateur', 'settings'],
}
