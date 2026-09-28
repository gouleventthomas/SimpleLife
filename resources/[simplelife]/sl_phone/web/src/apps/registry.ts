import type { ComponentType } from 'react'
import { SettingsApp } from './SettingsApp'
import { ContactsApp } from './ContactsApp'
import { PhoneApp } from './PhoneApp'
import { MessagesApp } from './MessagesApp'
import { NotesApp } from './NotesApp'
import { GalleryApp } from './GalleryApp'
import { WalletApp } from './WalletApp'
import { CryptoApp } from './CryptoApp'
import { StoreApp } from './StoreApp'
import { BusinessApp } from './BusinessApp'
import { VehiclesApp } from './VehiclesApp'
import { AnnuaireApp } from './AnnuaireApp'

// id -> functional app component. Apps not listed here render the ComingSoon placeholder
// (driven by their AppDef from the Lua config). 'camera' is intentionally absent — App
// renders the fullscreen CameraView for that route, outside the phone frame.
const COMPONENTS: Record<string, ComponentType> = {
  settings: SettingsApp,
  contacts: ContactsApp,
  phone: PhoneApp,
  messages: MessagesApp,
  notes: NotesApp,
  gallery: GalleryApp,
  wallet: WalletApp,
  crypto: CryptoApp,
  store: StoreApp,
  business: BusinessApp,
  vehicules: VehiclesApp,
  annuaire: AnnuaireApp,
}

export function getComponent(id: string): ComponentType | null {
  return COMPONENTS[id] ?? null
}
