import { useEffect, useRef } from 'react'

// Subscribe to Lua -> NUI messages (SendNUIMessage({ action, data })).
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void) {
  const ref = useRef(handler)
  ref.current = handler
  useEffect(() => {
    const fn = (e: MessageEvent) => {
      const d = e.data
      if (d && d.action === action) ref.current(d.data as T)
    }
    window.addEventListener('message', fn)
    return () => window.removeEventListener('message', fn)
  }, [action])
}
