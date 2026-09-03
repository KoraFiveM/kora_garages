import { GaragePanel } from "./components/GaragePanel"
import { GarageProvider } from "./lib/state"

/**
 * One surface, mounted unconditionally and deciding for itself whether to
 * render -- the headless pattern qblib's own App.tsx uses. The panel is the
 * only thing that takes NUI focus, and only while it is open.
 */
export default function App() {
    return (
        <GarageProvider>
            <GaragePanel />
        </GarageProvider>
    )
}
