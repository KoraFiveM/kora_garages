import { createContext, useContext, useEffect, useState, type ReactNode } from "react"

import { fetchNui } from "./fetchNui"
import type { GarageState } from "./types"
import { useNuiEvent } from "./useNuiEvent"

const EMPTY: GarageState = { open: false, vehicles: [], busy: false }

const StateContext = createContext<GarageState>(EMPTY)

export function useGarageState(): GarageState {
    return useContext(StateContext)
}

export function GarageProvider({ children }: { children: ReactNode }) {
    const [state, setState] = useState<GarageState>(EMPTY)

    // Lua pushes the WHOLE view on every change rather than a diff. A garage
    // panel is a few dozen rows at most, so this is both cheap and much easier
    // to reason about than reconciling partial updates.
    useNuiEvent<GarageState>("qbgarages:state", (next) => {
        if (next) setState(next)
    })

    // Announce the frame is mounted. SendNUIMessage is postMessage-like, not a
    // mailbox -- anything Lua sent before this point was queued on its side, and
    // this ping is what releases it. Without it the panel stays blank until the
    // next state change, which for a garage means it never appears at all.
    useEffect(() => {
        fetchNui("qbgarages:ready").catch((error) => {
            console.error("[qbgarages] ready ping failed:", error)
        })
    }, [])

    return <StateContext.Provider value={state}>{children}</StateContext.Provider>
}
