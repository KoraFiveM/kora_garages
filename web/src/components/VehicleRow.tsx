import { CarFront, Lock, LogOut, ParkingSquare } from "lucide-react"

import { fetchNui } from "../lib/fetchNui"
import type { GarageDescriptor, GarageVehicle } from "../lib/types"
import { Meter } from "./Meter"

const STATE_LABEL: Record<GarageVehicle["state"], string> = {
    garaged: "In the garage",
    out: "Out on the street",
    impounded: "Impounded",
}

/** Currency without pulling in a locale-aware formatter for one number. */
function money(amount: number): string {
    return `$${amount.toLocaleString("en-US")}`
}

/**
 * One vehicle, with whatever action its state and this garage allow.
 *
 * Every button sends nothing but the PLATE. It is intent: the server re-resolves
 * the plate against the DB, re-resolves the garage from its own config, and
 * re-checks ownership, distance and routing bucket before acting -- so a
 * disabled button here is a courtesy, never a control.
 */
export function VehicleRow({
    vehicle,
    garage,
    busy,
}: {
    vehicle: GarageVehicle
    garage: GarageDescriptor
    busy: boolean
}) {
    const isImpounded = vehicle.state === "impounded"
    const blocked = !vehicle.accepted

    return (
        <li className="panel flex flex-col gap-2.5 rounded-md p-3">
            <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                    <div className="flex items-center gap-2">
                        <span className="icon-badge bg-brand-soft text-primary">
                            <CarFront size={13} aria-hidden />
                        </span>
                        <span className="truncate text-sm font-medium text-foreground">{vehicle.label}</span>
                    </div>
                    <div className="mt-1 flex items-center gap-2 pl-8">
                        <span className="rounded-xs border border-border-strong bg-secondary px-1.5 py-0.5 font-mono text-[10px] tracking-widest text-secondary-foreground">
                            {vehicle.plate}
                        </span>
                        <span className="text-[11px] text-muted-foreground">{STATE_LABEL[vehicle.state]}</span>
                    </div>
                </div>

                <div className="flex shrink-0 flex-col items-end gap-1.5">
                    {isImpounded && typeof vehicle.fee === "number" && (
                        <span className="font-mono text-xs text-warning">{money(vehicle.fee)}</span>
                    )}
                    <Action vehicle={vehicle} garage={garage} busy={busy} blocked={blocked} />
                </div>
            </div>

            <div className="flex flex-col gap-1 pl-8">
                <Meter label="Fuel" value={vehicle.fuel} />
                <Meter label="Engine" value={vehicle.engine} />
                <Meter label="Body" value={vehicle.body} />
            </div>

            {blocked && (
                <p className="pl-8 text-[11px] text-muted-foreground">
                    This garage does not accept {vehicle.category ?? "this class of vehicle"}.
                </p>
            )}
        </li>
    )
}

function Action({
    vehicle,
    garage,
    busy,
    blocked,
}: {
    vehicle: GarageVehicle
    garage: GarageDescriptor
    busy: boolean
    blocked: boolean
}) {
    const send = (callback: string) => {
        fetchNui(callback, { plate: vehicle.plate }).catch((error) => {
            console.error(`[qbgarages] ${callback} failed:`, error)
        })
    }

    if (vehicle.state === "impounded") {
        // Only offered at a lot. Elsewhere the row is not even listed, but the
        // guard stays: the listing and the action are separate round trips and a
        // vehicle can be impounded between them.
        if (!garage.isImpound) return null
        return (
            <Button onClick={() => send("qbgarages:retrieveImpound")} disabled={busy} icon={<Lock size={12} />}>
                Pay &amp; release
            </Button>
        )
    }

    if (vehicle.state === "out") {
        if (!garage.canStore) return null
        return (
            <Button onClick={() => send("qbgarages:store")} disabled={busy} icon={<ParkingSquare size={12} />}>
                Store
            </Button>
        )
    }

    return (
        <Button onClick={() => send("qbgarages:takeOut")} disabled={busy || blocked} icon={<LogOut size={12} />}>
            Take out
        </Button>
    )
}

function Button({
    children,
    onClick,
    disabled,
    icon,
}: {
    children: React.ReactNode
    onClick: () => void
    disabled?: boolean
    icon?: React.ReactNode
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            disabled={disabled}
            className="flex items-center gap-1.5 rounded-sm bg-primary px-2.5 py-1.5 text-[11px] font-medium text-primary-foreground transition-colors duration-fast hover:bg-brand-hover active:bg-brand-pressed disabled:cursor-not-allowed disabled:opacity-40"
        >
            {icon}
            {children}
        </button>
    )
}
