import { defineConfig } from 'vite'
import arraybuffer from 'vite-plugin-arraybuffer'

export default defineConfig({
  base: '/Earthbound-Battle-Backgrounds-JS/',
  plugins: [arraybuffer()]
})
