import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

// ── FiveM NUI build config ──────────────────────────────────────────────────
//  base './'          -> assets are referenced relatively, so they resolve under
//                        nui://sl_ui/html/... in-game (an absolute '/' base 404s).
//  build.outDir '../html' -> Vite builds straight into the resource's html/ folder,
//                        which fxmanifest serves via `ui_page 'html/index.html'`.
//  emptyOutDir        -> clean the html/ folder on each build.
//  '@' alias          -> clean imports (@/components/...) + ShadCN convention.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: './',
  resolve: {
    alias: { '@': path.resolve(import.meta.dirname, './src') },
  },
  build: {
    outDir: '../html',
    emptyOutDir: true,
  },
})
