import { create } from 'zustand'
import { rpc } from './lib/rpc'
import { fetchNui } from './lib/fetchNui'
import type { VenteData, GestionData, BillData, ImpoundData } from './types'

type Screen = 'none' | 'vente' | 'gestion' | 'bill' | 'impound'

interface State {
  screen: Screen
  vente: VenteData | null
  gestion: GestionData | null
  bill: BillData | null
  impound: ImpoundData | null
  dealerId: string | null
  posResult: { ok: boolean; reason?: string; commission?: number } | null

  openVente: (d: VenteData) => void
  openGestion: (d: GestionData) => void
  openBill: (d: BillData) => void
  openImpound: (d: ImpoundData) => void
  setGestion: (d: GestionData) => void
  setImpound: (d: ImpoundData) => void
  setPosResult: (r: State['posResult']) => void
  close: () => void
  call: <T = { ok: boolean; reason?: string }>(method: string, params?: object) => Promise<T>
}

export const useStore = create<State>((set, get) => ({
  screen: 'none',
  vente: null, gestion: null, bill: null, impound: null, dealerId: null, posResult: null,

  openVente: (d) => set({ screen: 'vente', vente: d, dealerId: d.dealer.id, posResult: null }),
  openGestion: (d) => set({ screen: 'gestion', gestion: d, dealerId: d.dealer.id }),
  openBill: (d) => set({ screen: 'bill', bill: d }),
  openImpound: (d) => set({ screen: 'impound', impound: d }),
  setGestion: (d) => set({ gestion: d }),
  setImpound: (d) => set({ impound: d }),
  setPosResult: (r) => set({ posResult: r }),

  close: () => { fetchNui('close', {}); set({ screen: 'none', vente: null, gestion: null, bill: null, impound: null, posResult: null }) },

  call: async (method, params = {}) => {
    const dealerId = get().dealerId
    return rpc(method, { dealerId, ...params }) as never
  },
}))
