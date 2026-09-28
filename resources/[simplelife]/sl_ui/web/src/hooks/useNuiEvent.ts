import { useEffect, useRef } from 'react'

type NuiHandler<T> = (data: T) => void

// Subscribe to a message dispatched from client/bridge.lua via
// SendNUIMessage({ action, data }). The handler is kept in a ref so re-renders
// don't re-bind the window listener.
export function useNuiEvent<T = unknown>(action: string, handler: NuiHandler<T>): void {
  const saved = useRef<NuiHandler<T>>(handler)
  saved.current = handler

  useEffect(() => {
    const listener = (event: MessageEvent) => {
      const payload = event.data as { action?: string; data?: T } | undefined
      if (payload && payload.action === action) {
        saved.current(payload.data as T)
      }
    }
    window.addEventListener('message', listener)
    return () => window.removeEventListener('message', listener)
  }, [action])
}
