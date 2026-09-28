// fetchNui — POST to a NUI callback registered in client/main.lua (RegisterNUICallback).
//
// In a normal browser (Vite dev server) the FiveM-injected global GetParentResourceName
// does not exist, so we short-circuit and return the provided `mock` value — this lets us
// build/preview the whole phone in the browser with fake data, then ship the same code.
export async function fetchNui<T = unknown>(
  event: string,
  data: unknown = {},
  mock?: T,
): Promise<T> {
  const getName = (window as unknown as { GetParentResourceName?: () => string })
    .GetParentResourceName

  if (typeof getName !== 'function') {
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

// True when running inside the FiveM CEF (vs a plain browser dev server).
export function inGame(): boolean {
  return typeof (window as unknown as { GetParentResourceName?: () => string })
    .GetParentResourceName === 'function'
}
