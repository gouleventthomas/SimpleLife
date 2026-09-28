import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

// FiveM NUI build: base './' so assets resolve under nui://sl_phone/html/..., and
// build straight into the resource's html/ folder (served by ui_page 'html/index.html').
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
