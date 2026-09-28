import { fetchNui } from './fetchNui'

// Relay to the sl_vehicles:rpc server callback via client/main.lua's 'rpc' bridge.
export async function rpc<T = unknown>(method: string, params: object = {}, mock?: T): Promise<T> {
  return fetchNui<T>('rpc', { method, params }, mock as T)
}
