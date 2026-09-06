import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"
import qbtheme from "../../qbtheme/vite-plugin.mjs"

// FiveM's CEF NUI browser loads this page from a local resource path, not from
// a domain root -- asset URLs must be relative ("./assets/..") or every
// script/style 404s in-game. Do NOT change `base` back to "/". Same convention
// as qblib's, qbhud's and qbdispatch's own vite configs.
export default defineConfig({
    plugins: [qbtheme(), react()],
    base: "./",
    build: {
        outDir: "build",
        // Nothing is vendored under build/ here (no map tiles, no fonts), so
        // emptying the output directory is safe and keeps stale hashed bundles
        // from piling up in git. `prebuild` clears build/assets as well, which
        // matters when a build is run with emptyOutDir disabled locally.
        emptyOutDir: true,
    },
    resolve: {
        alias: {
            "@": path.resolve(__dirname, "./src"),
        },
    },
})
