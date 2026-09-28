import { fetchNui } from './fetchNui'

// Relay to the sl_shops server callback via client/main.lua's 'shopsRpc' bridge. Lets the
// Société app read company stock + bill a customer without sl_phone owning any shop logic.
// `mock` is returned in browser dev.
export async function shopsRpc<T = unknown>(method: string, params: object = {}, mock?: T): Promise<T> {
  return fetchNui<T>('shopsRpc', { method, params }, mock as T)
}
