import { fetchNui } from './fetchNui'

// Request/response to the server via client/main.lua's 'rpc' bridge. The Lua relays it to
// the sl_phone:rpc server callback and returns its result. `mock` is used in browser dev.
export async function rpc<T = unknown>(
  method: string,
  params: object = {},
  mock?: T,
): Promise<T> {
  return fetchNui<T>('rpc', { method, params }, mock as T)
}
