import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { fetchNui } from '@/lib/fetchNui'
import { Button } from '@/components/ui/button'

// Matches the NUI protocol payload sent by sl_identity:
//   screen 'charcreate', payload { canCancel }
export interface CharCreatePayload {
  canCancel: boolean
}

// Turn a raw server reason code (NAME_LEN / DB_ERROR / DUPLICATE / ...) — or an
// already-formatted message — into something legible on the form. The server sends
// a formatted string via notify('error', ...); if a bare code slips through we still
// show something meaningful instead of a silent reappearing form.
function describeServerError(raw: string): string {
  const code = raw.toUpperCase()
  if (code.includes('NAME_LEN')) return 'Nom ou prénom invalide (longueur).'
  if (code.includes('DUPLICATE') || code.includes('EXIST')) return 'Ce personnage existe déjà.'
  if (code.includes('CAP') || code.includes('LIMIT')) return 'Limite de personnages atteinte.'
  if (code.includes('DB_ERROR') || code.includes('DB')) return 'Erreur serveur. Réessaie.'
  return raw
}

type Gender = 'm' | 'f'

// 18+ courtesy check + a plausible window (no 130-year-olds, no future dates).
function validateDob(dob: string): string | null {
  if (!dob) return 'Renseigne ta date de naissance.'
  const d = new Date(dob)
  if (Number.isNaN(d.getTime())) return 'Date invalide.'
  const now = new Date()
  if (d > now) return 'Date dans le futur.'
  let age = now.getFullYear() - d.getFullYear()
  const m = now.getMonth() - d.getMonth()
  if (m < 0 || (m === 0 && now.getDate() < d.getDate())) age--
  if (age < 18) return 'Tu dois avoir au moins 18 ans.'
  if (age > 100) return 'Date peu plausible.'
  return null
}

export default function CharCreate({
  canCancel,
  serverError,
}: CharCreatePayload & { serverError?: string | null }) {
  const [firstname, setFirstname] = useState('')
  const [lastname, setLastname] = useState('')
  const [dob, setDob] = useState('')
  const [gender, setGender] = useState<Gender>('m')
  const [error, setError] = useState<string | null>(null)
  // The server's rejection reason for the LAST attempt, shown on the form so a failed
  // create never silently re-appears. Local validation `error` takes precedence once
  // the player starts a new attempt.
  const [dismissedServerError, setDismissedServerError] = useState(false)

  // A new serverError value (new failed attempt) re-shows the banner.
  useEffect(() => {
    setDismissedServerError(false)
  }, [serverError])

  const shownServerError =
    serverError && !dismissedServerError ? describeServerError(serverError) : null

  const submit = () => {
    // Re-submitting: clear the previous server reason so it can't linger as stale.
    setDismissedServerError(true)
    const fn = firstname.trim()
    const ln = lastname.trim()
    if (fn.length < 2) return setError('Prénom trop court.')
    if (ln.length < 2) return setError('Nom trop court.')
    const dobErr = validateDob(dob)
    if (dobErr) return setError(dobErr)

    setError(null)
    fetchNui('dispatch', {
      event: 'identity:create',
      data: { firstname: fn, lastname: ln, dob, gender },
    })
  }

  const cancel = () =>
    fetchNui('dispatch', { event: 'identity:cancelCreate' })

  return (
    <div className="relative flex h-full w-full items-center justify-center overflow-hidden">
      {/* Same grunge vignette as CharSelect for continuity. */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,#2a1d12_0%,#15100a_45%,#000_100%)]" />
      <div className="pointer-events-none absolute inset-0 shadow-[inset_0_0_220px_120px_rgba(0,0,0,0.9)]" />

      <div className="relative z-10 w-full max-w-md px-8">
        <header className="mb-6 text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.4em] text-amber-500/70">
            Nouvel arrivant
          </p>
          <h1 className="mt-2 font-heading text-3xl font-bold uppercase tracking-wide text-amber-100 drop-shadow-[0_2px_8px_rgba(0,0,0,0.8)]">
            Ton identité
          </h1>
          <p className="mt-3 text-sm italic leading-relaxed text-amber-100/40">
            Fraîchement descendu du bus. Personne ici ne connaît encore ton nom.
          </p>
          <div className="mx-auto mt-4 h-px w-40 bg-gradient-to-r from-transparent via-amber-600/60 to-transparent" />
        </header>

        <form
          onSubmit={(e) => {
            e.preventDefault()
            submit()
          }}
          className="flex flex-col gap-4 rounded-xl border border-amber-900/40 bg-gradient-to-b from-stone-900/80 to-stone-950/90 p-6 shadow-lg shadow-black/50 backdrop-blur-sm"
        >
          <Field label="Prénom">
            <TextInput
              value={firstname}
              onChange={setFirstname}
              placeholder="John"
              autoFocus
            />
          </Field>

          <Field label="Nom">
            <TextInput value={lastname} onChange={setLastname} placeholder="Doe" />
          </Field>

          <Field label="Date de naissance">
            <input
              type="date"
              value={dob}
              onChange={(e) => setDob(e.target.value)}
              className="w-full rounded-lg border border-amber-900/40 bg-stone-950/70 px-3 py-2 text-amber-50 outline-none transition-colors focus:border-amber-600/70 [color-scheme:dark]"
            />
          </Field>

          <Field label="Genre">
            <div className="grid grid-cols-2 gap-2">
              <GenderTab
                active={gender === 'm'}
                onClick={() => setGender('m')}
                label="Homme"
              />
              <GenderTab
                active={gender === 'f'}
                onClick={() => setGender('f')}
                label="Femme"
              />
            </div>
          </Field>

          {(error || shownServerError) && (
            <p className="text-center text-sm font-medium text-red-400/90">
              {error || shownServerError}
            </p>
          )}

          <Button
            type="submit"
            size="lg"
            className="mt-2 w-full bg-amber-700 text-amber-50 hover:bg-amber-600"
          >
            Descendre de l'avion
          </Button>

          {canCancel && (
            <button
              type="button"
              onClick={cancel}
              className="text-center text-xs uppercase tracking-widest text-amber-100/35 transition-colors hover:text-amber-100/70"
            >
              ← Retour à la sélection
            </button>
          )}
        </form>
      </div>
    </div>
  )
}

function Field({
  label,
  children,
}: {
  label: string
  children: ReactNode
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-[10px] font-semibold uppercase tracking-widest text-amber-500/60">
        {label}
      </span>
      {children}
    </label>
  )
}

function TextInput({
  value,
  onChange,
  placeholder,
  autoFocus,
}: {
  value: string
  onChange: (v: string) => void
  placeholder?: string
  autoFocus?: boolean
}) {
  return (
    <input
      type="text"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      autoFocus={autoFocus}
      maxLength={24}
      className="w-full rounded-lg border border-amber-900/40 bg-stone-950/70 px-3 py-2 text-amber-50 placeholder:text-amber-100/20 outline-none transition-colors focus:border-amber-600/70"
    />
  )
}

function GenderTab({
  active,
  onClick,
  label,
}: {
  active: boolean
  onClick: () => void
  label: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        'rounded-lg border px-3 py-2 text-sm font-semibold uppercase tracking-widest transition-colors ' +
        (active
          ? 'border-amber-600/70 bg-amber-700/30 text-amber-100'
          : 'border-amber-900/40 bg-stone-950/50 text-amber-100/40 hover:border-amber-700/50 hover:text-amber-100/70')
      }
    >
      {label}
    </button>
  )
}
