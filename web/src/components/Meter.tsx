/**
 * A 0-100 condition bar.
 *
 * Colour is derived from the VALUE, not passed in: fuel, engine and body all
 * mean the same thing to a player ("how much of this is left"), so they must
 * read identically. The thresholds are the same ones the framework's status
 * bars use -- amber under a third, red under a sixth.
 */
export function Meter({ label, value, unit }: { label: string; value: number; unit?: string }) {
    const clamped = Math.max(0, Math.min(100, Math.round(value)))
    const tone =
        clamped <= 16 ? "hsl(var(--destructive))" : clamped <= 33 ? "hsl(var(--warning))" : "hsl(var(--success))"

    return (
        <div className="flex items-center gap-2">
            <span className="w-12 shrink-0 text-[10px] uppercase tracking-wide text-muted-foreground">{label}</span>
            <div
                className="h-1.5 flex-1 overflow-hidden rounded-full bg-secondary"
                role="meter"
                aria-label={label}
                aria-valuenow={clamped}
                aria-valuemin={0}
                aria-valuemax={100}
            >
                <div className="h-full rounded-full transition-all" style={{ width: `${clamped}%`, background: tone }} />
            </div>
            <span className="w-10 shrink-0 text-right font-mono text-[11px] tabular-nums text-foreground">
                {clamped}
                {unit ?? "%"}
            </span>
        </div>
    )
}
