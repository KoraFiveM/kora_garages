/** The `{ action, data }` envelope every SendNUIMessage in this framework uses. */
export interface NuiWireMessage<T = unknown> {
    action: string
    data: T
}

/** Semantic HSL tokens from Lua's QB.theme.tokens(), applied as CSS variables. */
export type ThemeTokens = Record<string, string>

/**
 * A vehicle as the SERVER chose to describe it (Garages.shared.wire).
 *
 * Deliberately narrower than the DB row: there is no owner citizenid, no mods
 * blob and no last-known position here, because a UI needs none of the three
 * and the last one is a hint about where to find somebody's car.
 */
export interface GarageVehicle {
    plate: string
    model: string
    /** Registry name ("Karin Sultan"), falling back to the raw spawn code. */
    label: string
    category?: string
    state: "garaged" | "out" | "impounded"
    /** 0-100, as stored. */
    fuel: number
    /** 0-100 percentages: the browser never learns the 0..1000 storage scale. */
    engine: number
    body: number
    /** Release fee, present only on an impounded vehicle. */
    fee?: number
    /** Whether THIS garage accepts the vehicle's category. */
    accepted: boolean
}

export interface GarageDescriptor {
    id: string
    label: string
    type: string
    typeLabel: string
    /** Whether a Store action exists here at all. A fact from the server, not
     *  inferred from `type` -- so a new garage type needs no change here. */
    canStore: boolean
    isImpound: boolean
}

export interface GarageState {
    open: boolean
    garage?: GarageDescriptor
    vehicles: GarageVehicle[]
    /** An action is in flight; every button is disabled until it answers. */
    busy: boolean
    /** The server's own refusal, shown verbatim. */
    error?: string
}
