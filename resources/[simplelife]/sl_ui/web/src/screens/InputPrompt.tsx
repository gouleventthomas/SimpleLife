import { useEffect, useRef, useState } from 'react'
import { fetchNui } from '@/lib/fetchNui'
import { glass } from '@/lib/glass'

export interface InputPayload {
  id: string
  title: string
  label?: string
  description?: string
  placeholder?: string
  confirmLabel?: string
  accent?: string         // theme color (hex), matched to the menu that opened it
}

// Liquid Glass numeric prompt (companion to Menu). Digits only; Enter submits, Esc cancels.
export default function InputPrompt({ id, title, label, description, placeholder, confirmLabel, accent }: InputPayload) {
  const g = glass(accent)
  const [value, setValue] = useState('')
  const ref = useRef<HTMLInputElement>(null)

  useEffect(() => { ref.current?.focus() }, [])

  const submit = () => {
    const n = Math.floor(Number(value))
    if (!Number.isFinite(n) || n <= 0) return
    fetchNui('dispatch', { event: 'input:submit', data: { id, value: n } })
  }
  const cancel = () => fetchNui('dispatch', { event: 'input:cancel', data: { id } })

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); cancel() } }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="absolute inset-0" onMouseDown={cancel}>
      <div
        className="absolute left-[54%] top-1/2 w-[360px] -translate-y-1/2 overflow-hidden rounded-[20px] border border-white/15 text-white"
        style={g.panel}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div
          className="border-b border-white/10 px-5 py-4 text-center"
          style={{ background: 'linear-gradient(180deg, rgba(255,255,255,0.07), rgba(255,255,255,0))' }}
        >
          <div className="text-[16px] font-medium tracking-[0.16em]">{(title ?? '').toUpperCase()}</div>
        </div>

        <div className="px-5 py-5">
          {label && <div className="mb-2 text-[12px] uppercase tracking-widest text-white/55">{label}</div>}
          <input
            ref={ref}
            type="text"
            inputMode="numeric"
            value={value}
            placeholder={placeholder}
            onChange={(e) => setValue(e.target.value.replace(/[^0-9]/g, ''))}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); submit() } }}
            className="w-full rounded-xl border border-white/15 bg-black/25 px-4 py-3 text-[18px] font-medium text-white outline-none placeholder:text-white/30 focus:border-white/35"
          />
          {description && <div className="mt-2 text-[12px] leading-snug text-white/55">{description}</div>}

          <div className="mt-5 flex gap-2.5">
            <button
              onClick={cancel}
              className="flex-1 rounded-xl border border-white/[0.12] bg-white/[0.04] py-2.5 text-[13px] text-white/70 transition-colors hover:bg-white/[0.08]"
            >
              Annuler
            </button>
            <button
              onClick={submit}
              className="flex-1 rounded-xl py-2.5 text-[13px] font-medium text-white transition-colors"
              style={g.confirm}
            >
              {confirmLabel || 'Confirmer'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
