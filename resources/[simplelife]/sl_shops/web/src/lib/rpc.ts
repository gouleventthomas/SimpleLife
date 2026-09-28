import { fetchNui } from './fetchNui'

// Request/response to the server via client/main.lua's 'rpc' bridge (relays to the
// sl_shops:rpc server callback). `mock` is returned in browser dev.
export async function rpc<T = unknown>(method: string, params: object = {}, mock?: T): Promise<T> {
  return fetchNui<T>('rpc', { method, params }, mock as T)
}
