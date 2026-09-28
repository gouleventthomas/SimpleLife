import { fetchNui } from './fetchNui'

// Relay to the sl_vehicles server callback via client/main.lua's 'vehiclesRpc' bridge.
// Powers the "Véhicules/Clés" app (lock/locate/engine/trunk/share) and the "Annuaire" app
// (company directory + contact form). `mock` is returned in browser dev.
export async function vehiclesRpc<T = unknown>(method: string, params: object = {}, mock?: T): Promise<T> {
  return fetchNui<T>('vehiclesRpc', { method, params }, mock as T)
}
