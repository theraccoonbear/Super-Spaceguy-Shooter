import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'
import { execSync } from 'child_process'

// ── Spline DSL watcher ────────────────────────────────────────────────────
// Watches math/spline-frame.js for changes and re-runs tools/emit-spline.js.
// The regenerated spline_gen.ts is picked up by Vite HMR automatically.
function splineEmitPlugin(): Plugin {
  const repoRoot = resolve(__dirname, '../..')
  const dslFile  = resolve(repoRoot, 'math/spline-frame.js')

  return {
    name: 'spline-emit-watcher',
    configureServer(server) {
      server.watcher.add(dslFile)

      server.watcher.on('change', (file) => {
        if (file !== dslFile) return

        server.config.logger.info('[spline] spline-frame.js changed — re-emitting...', { timestamp: true })
        try {
          execSync('node tools/emit-spline.js', { cwd: repoRoot, stdio: 'inherit' })
          server.config.logger.info('[spline] emit done', { timestamp: true })

          // Invalidate the generated module so HMR propagates to all importers
          const genPath = resolve(__dirname, 'src/math/spline_gen.ts')
          const mod = server.moduleGraph.getModuleById(genPath)
          if (mod) server.moduleGraph.invalidateModule(mod)
          server.hot.send({ type: 'full-reload' })
        } catch (err) {
          server.config.logger.error('[spline] emit failed — check math/spline-frame.js for errors')
        }
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), splineEmitPlugin()],
  base: './',   // relative asset paths so the built index.html opens from anywhere
})
