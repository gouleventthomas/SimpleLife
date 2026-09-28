// fetchNui — POST to a NUI callback registered in client/bridge.lua (RegisterNUICallback).
//
// In a normal browser (Vite dev server) the FiveM-injected global
// `GetParentResourceName` does not exist, so we short-circuit and return the
// provided `mock` value — this lets us build/preview the whole UI in the browser
// with fake data, then ship the exact same code in-game.
export async function fetchNui<T = unknown>(
  event: string,
  data: unknown = {},
  mock?: T,
): Promise<T> {
  const getName = (window as unknown as { GetParentResourceName?: () => string })
    .GetParentResourceName

  if (typeof getName !== 'function') {
    // Browser dev mode: no FiveM host present.
    return mock as T
  }

  const resource = getName()
  const resp = await fetch(`https://${resource}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  })
  return (await resp.json()) as T
}
