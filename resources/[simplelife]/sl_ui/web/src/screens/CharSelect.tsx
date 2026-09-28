import { fetchNui } from '@/lib/fetchNui'
import { Button } from '@/components/ui/button'

// Matches the NUI protocol payload sent by sl_identity:
//   screen 'charselect', payload { chars, cap }
export interface CharSummary {
  id: number
  firstname: string
  lastname: string
  model?: string
  cash: number
  bank: number
  lastZone?: string
}

export interface CharSelectPayload {
  chars: CharSummary[]
  cap: number
}

const money = (n: number) => `$${(n ?? 0).toLocaleString('fr-FR')}`

export default function CharSelect({ chars, cap }: CharSelectPayload) {
  const list = chars ?? []
  const canCreate = list.length < (cap ?? 0)

  const select = (id: number) =>
    fetchNui('dispatch', { event: 'identity:select', data: { id } })

  const newChar = () => fetchNui('dispatch', { event: 'identity:newchar' })

  return (
    <div className="relative flex h-full w-full items-center justify-center overflow-hidden">
      {/* Grunge vignette backdrop — warm brown-black bleeding to pure black edges,
          so the dark game behind reads through cleanly. */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,#2a1d12_0%,#15100a_45%,#000_100%)]" />
      <div className="pointer-events-none absolute inset-0 shadow-[inset_0_0_220px_120px_rgba(0,0,0,0.9)]" />

      <div className="relative z-10 flex w-full max-w-4xl flex-col px-8">
        <header className="mb-8 text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.4em] text-amber-500/70">
            Los Santos International
          </p>
          <h1 className="mt-2 font-heading text-4xl font-bold uppercase tracking-wide text-amber-100 drop-shadow-[0_2px_8px_rgba(0,0,0,0.8)]">
            Qui arrive à Los Santos ?
          </h1>
          <div className="mx-auto mt-3 h-px w-40 bg-gradient-to-r from-transparent via-amber-600/60 to-transparent" />
        </header>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {list.map((c) => (
            <CharCard key={c.id} char={c} onSelect={() => select(c.id)} />
          ))}

          {canCreate && <NewArrivalCard onClick={newChar} />}
        </div>

        {list.length === 0 && !canCreate && (
          <p className="mt-8 text-center text-sm text-amber-100/40">
            Aucun passager enregistré sur ce vol.
          </p>
        )}

        <footer className="mt-8 text-center text-[11px] uppercase tracking-[0.3em] text-amber-100/25">
          {list.length} / {cap ?? 0} personnages
        </footer>
      </div>
    </div>
  )
}

function CharCard({
  char,
  onSelect,
}: {
  char: CharSummary
  onSelect: () => void
}) {
  return (
    <div className="group flex flex-col justify-between rounded-xl border border-amber-900/40 bg-gradient-to-b from-stone-900/80 to-stone-950/90 p-5 shadow-lg shadow-black/50 backdrop-blur-sm transition-colors hover:border-amber-600/60">
      <div>
        <h2 className="font-heading text-xl font-bold uppercase tracking-wide text-amber-50">
          {char.firstname} {char.lastname}
        </h2>
        {char.lastZone && (
          <p className="mt-1 text-[11px] uppercase tracking-widest text-amber-500/60">
            {char.lastZone}
          </p>
        )}

        <div className="mt-4 flex gap-4 text-xs text-amber-100/45">
          <span>
            <span className="block text-[10px] uppercase tracking-widest text-amber-100/30">
              À bord
            </span>
            <span className="font-semibold tabular-nums text-emerald-400/80">
              {money(char.cash)}
            </span>
          </span>
          <span>
            <span className="block text-[10px] uppercase tracking-widest text-amber-100/30">
              Banque
            </span>
            <span className="font-semibold tabular-nums text-sky-400/80">
              {money(char.bank)}
            </span>
          </span>
        </div>
      </div>

      <Button
        size="lg"
        onClick={onSelect}
        className="mt-5 w-full bg-amber-700 text-amber-50 hover:bg-amber-600"
      >
        Sélectionner / Arriver
      </Button>
    </div>
  )
}

function NewArrivalCard({ onClick }: { onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="flex min-h-[200px] flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-amber-700/40 bg-stone-950/40 p-5 text-amber-500/70 transition-colors hover:border-amber-500/70 hover:bg-stone-900/60 hover:text-amber-300"
    >
      <span className="text-4xl font-light leading-none">＋</span>
      <span className="font-heading text-sm font-semibold uppercase tracking-widest">
        Nouvel arrivant
      </span>
    </button>
  )
}
