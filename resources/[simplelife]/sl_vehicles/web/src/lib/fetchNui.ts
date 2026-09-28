// fetchNui — POST to a NUI callback registered in client/main.lua. In a plain browser the
// FiveM global GetParentResourceName is absent, so we return `mock` for dev/preview.
export async function fetchNui<T = unknown>(event: string, data: unknown = {}, mock?: T): Promise<T> {
  const getName = (window as unknown as { GetParentResourceName?: () => string }).GetParentResourceName
  if (typeof getName !== 'function') return mock as T
  const resource = getName()
  const resp = await fetch(`https://${resource}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  })
  return (await resp.json()) as T
}

export function inGame(): boolean {
  return typeof (window as unknown as { GetParentResourceName?: () => string }).GetParentResourceName === 'function'
}
