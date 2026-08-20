import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'
import { execSync } from 'child_process'
import fs from 'fs'
import type { IncomingMessage, ServerResponse } from 'http'

// ── Spline DSL watcher ────────────────────────────────────────────────────
// Watches math/formula.expr for changes and re-runs tools/emit-spline.js.
// The regenerated spline_gen.ts is picked up by Vite HMR automatically.
function splineEmitPlugin(): Plugin {
  const repoRoot = resolve(__dirname, '../..')
  const dslFile  = resolve(repoRoot, 'math/formula.expr')

  return {
    name: 'spline-emit-watcher',
    configureServer(server) {
      server.watcher.add(dslFile)

      server.watcher.on('change', (file) => {
        if (file !== dslFile) return

        server.config.logger.info('[spline] formula.expr changed — re-emitting...', { timestamp: true })
        try {
          execSync('node tools/emit-spline.js', { cwd: repoRoot, stdio: 'inherit' })
          server.config.logger.info('[spline] emit done', { timestamp: true })

          const genPath = resolve(__dirname, 'src/math/spline_gen.ts')
          const mod = server.moduleGraph.getModuleById(genPath)
          if (mod) server.moduleGraph.invalidateModule(mod)
          server.hot.send({ type: 'full-reload' })
        } catch {
          server.config.logger.error('[spline] emit failed — check math/formula.expr for errors')
        }
      })
    },
  }
}

// ── Maneuvers.txt API ─────────────────────────────────────────────────────
// GET  /api/maneuvers  → returns assets/maneuvers.txt content
// PUT  /api/maneuvers  → writes body back to assets/maneuvers.txt
// Only active in dev (configureServer is a no-op in production builds).
function maneuversApiPlugin(): Plugin {
  return {
    name: 'maneuvers-api',
    configureServer(server) {
      const ASSETS = resolve(__dirname, '../../assets/maneuvers.txt')

      server.middlewares.use('/api/maneuvers', (
        req: IncomingMessage,
        res: ServerResponse,
      ) => {
        res.setHeader('Access-Control-Allow-Origin', '*')
        res.setHeader('Cache-Control', 'no-store')

        if (req.method === 'GET') {
          try {
            const text = fs.readFileSync(ASSETS, 'utf-8')
            res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' })
            res.end(text)
          } catch (e) {
            res.writeHead(404, { 'Content-Type': 'text/plain' })
            res.end(`maneuvers.txt not found: ${e}`)
          }

        } else if (req.method === 'PUT') {
          let body = ''
          req.setEncoding('utf-8')
          req.on('data', (chunk: string) => { body += chunk })
          req.on('end', () => {
            try {
              fs.writeFileSync(ASSETS, body, 'utf-8')
              res.writeHead(200, { 'Content-Type': 'text/plain' })
              res.end('ok')
            } catch (e) {
              res.writeHead(500, { 'Content-Type': 'text/plain' })
              res.end(String(e))
            }
          })

        } else {
          res.writeHead(405)
          res.end()
        }
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), splineEmitPlugin(), maneuversApiPlugin()],
  base: './',
})
