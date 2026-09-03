import { AlertTriangle, Lock, Warehouse, X } from "lucide-react"

import { fetchNui } from "../lib/fetchNui"
import { useGarageState } from "../lib/state"
import { VehicleRow } from "./VehicleRow"

/**
 * The whole UI: a centred panel listing the player's vehicles at one garage.
 *
 * Renders nothing at all when closed. Lua takes NUI focus only while the panel
 * is open, so an always-rendered-but-hidden panel would leave a click-eating
 * transparent layer over gameplay for the rest of the session.
 */
export function GaragePanel() {
    const { open, garage, vehicles, busy, error } = useGarageState()

    if (!open || !garage) return null

    const close = () => {
        fetchNui("qbgarages:close").catch((error) => {
            console.error("[qbgarages] close failed:", error)
        })
    }

    return (
        <div className="pointer-events-auto flex h-full w-full items-center justify-center bg-black/45 p-6">
            <section
                className="panel flex max-h-[80vh] w-[520px] flex-col overflow-hidden rounded-lg shadow-modal"
                role="dialog"
                aria-label={garage.label}
            >
                <header className="flex items-center justify-between gap-3 border-b border-border px-4 py-3">
                    <div className="flex min-w-0 items-center gap-2.5">
                        <span className="icon-badge bg-brand-soft text-primary">
                            {garage.isImpound ? <Lock size={13} aria-hidden /> : <Warehouse size={13} aria-hidden />}
                        </span>
                        <div className="min-w-0">
                            <h1 className="truncate text-sm font-semibold text-foreground">{garage.label}</h1>
                            <p className="text-[11px] text-muted-foreground">{garage.typeLabel}</p>
                        </div>
                    </div>

                    <button
                        type="button"
                        onClick={close}
                        aria-label="Close"
                        className="rounded-sm p-1 text-muted-foreground transition-colors duration-fast hover:bg-surface-hover hover:text-foreground"
                    >
                        <X size={15} />
                    </button>
                </header>

                {error && (
                    <p className="flex items-start gap-2 border-b border-border bg-destructive/10 px-4 py-2 text-[11px] text-destructive">
                        <AlertTriangle size={13} className="mt-px shrink-0" aria-hidden />
                        {/* The server's own wording, verbatim. A player told "too
                            far from the garage" can act on it; one told
                            "something went wrong" cannot. */}
                        {error}
                    </p>
                )}

                {vehicles.length === 0 ? (
                    <p className="px-4 py-10 text-center text-xs text-muted-foreground">
                        {garage.isImpound
                            ? "Nothing of yours is being held here."
                            : "You have no vehicles at this garage."}
                    </p>
                ) : (
                    <ul className="scroll-thin flex flex-col gap-2 overflow-y-auto p-3">
                        {vehicles.map((vehicle) => (
                            <VehicleRow key={vehicle.plate} vehicle={vehicle} garage={garage} busy={busy} />
                        ))}
                    </ul>
                )}

                <footer className="flex items-center justify-between border-t border-border px-4 py-2 text-[10px] uppercase tracking-wide text-muted-foreground">
                    <span>
                        {vehicles.length} vehicle{vehicles.length === 1 ? "" : "s"}
                    </span>
                    {busy && <span className="text-primary">Working…</span>}
                </footer>
            </section>
        </div>
    )
}
