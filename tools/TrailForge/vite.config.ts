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
      // Only active when living inside the SSS repo — noop in standalone TrailForge.
      if (!fs.existsSync(dslFile)) return

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

// ── Maneuvers directory API ───────────────────────────────────────────────
// Each route lives as its own .mvr file under assets/maneuvers/.
// Only active in dev (configureServer is a no-op in production builds).
//
// GET  /api/maneuvers           → { routes: string[] }  (filename stems, sorted)
// GET  /api/maneuvers/:name     → .mvr file content (text/plain)
// PUT  /api/maneuvers/:name     → atomic write (tmp → rename); body = .mvr text
// DELETE /api/maneuvers/:name   → unlink the .mvr file
function maneuversDirApiPlugin(): Plugin {
  return {
    name: 'maneuvers-dir-api',
    configureServer(server) {
      const MANEUVERS_DIR = process.env.MANEUVERS_DIR
        ? resolve(process.env.MANEUVERS_DIR)
        : resolve(__dirname, '../../assets/maneuvers')

      // Ensure directory exists at startup
      if (!fs.existsSync(MANEUVERS_DIR)) {
        fs.mkdirSync(MANEUVERS_DIR, { recursive: true })
        server.config.logger.info(
          '[maneuvers] created assets/maneuvers/ — run: node tools/migrate-maneuvers.js',
          { timestamp: true },
        )
      }

      // Reject names with path-traversal characters or non-kebab chars
      function safeName(name: string): boolean {
        return Boolean(name) &&
          !name.includes('..') &&
          !name.includes('/') &&
          !name.includes('\\') &&
          /^[a-z0-9][a-z0-9_-]*$/i.test(name)
      }

      function cors(res: ServerResponse): void {
        res.setHeader('Access-Control-Allow-Origin', '*')
        res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, DELETE, OPTIONS')
        res.setHeader('Cache-Control', 'no-store')
      }

      server.middlewares.use('/api/maneuvers', (req: IncomingMessage, res: ServerResponse) => {
        cors(res)

        if (req.method === 'OPTIONS') {
          res.writeHead(204)
          res.end()
          return
        }

        // req.url is relative to the mount point: '/' for the list, '/name' for a route
        const url      = req.url || '/'
        const rawName  = url === '/' ? '' : decodeURIComponent(url.slice(1).split('?')[0])

        // ── GET /api/maneuvers  →  route list ──────────────────────────────
        if (!rawName && req.method === 'GET') {
          try {
            const routes = fs.readdirSync(MANEUVERS_DIR)
              .filter(f => f.endsWith('.mvr'))
              .map(f => f.slice(0, -4))
              .sort()
            res.writeHead(200, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({ routes }))
          } catch (e) {
            res.writeHead(500, { 'Content-Type': 'text/plain' })
            res.end(String(e))
          }
          return
        }

        if (!safeName(rawName)) {
          res.writeHead(400, { 'Content-Type': 'text/plain' })
          res.end('invalid route name')
          return
        }

        const filePath = resolve(MANEUVERS_DIR, `${rawName}.mvr`)

        // ── GET /api/maneuvers/:name  →  .mvr content ──────────────────────
        if (req.method === 'GET') {
          try {
            const text = fs.readFileSync(filePath, 'utf-8')
            res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' })
            res.end(text)
          } catch {
            res.writeHead(404, { 'Content-Type': 'text/plain' })
            res.end(`route not found: ${rawName}`)
          }
          return
        }

        // ── PUT /api/maneuvers/:name  →  atomic write ───────────────────────
        if (req.method === 'PUT') {
          let body = ''
          req.setEncoding('utf-8')
          req.on('data', (chunk: string) => { body += chunk })
          req.on('end', () => {
            try {
              const tmp = `${filePath}.tmp`
              fs.writeFileSync(tmp, body, 'utf-8')
              fs.renameSync(tmp, filePath)   // atomic on POSIX
              res.writeHead(200, { 'Content-Type': 'text/plain' })
              res.end('ok')
            } catch (e) {
              res.writeHead(500, { 'Content-Type': 'text/plain' })
              res.end(String(e))
            }
          })
          return
        }

        // ── DELETE /api/maneuvers/:name ─────────────────────────────────────
        if (req.method === 'DELETE') {
          try {
            fs.unlinkSync(filePath)
            res.writeHead(200, { 'Content-Type': 'text/plain' })
            res.end('ok')
          } catch {
            res.writeHead(404, { 'Content-Type': 'text/plain' })
            res.end(`route not found: ${rawName}`)
          }
          return
        }

        res.writeHead(405)
        res.end()
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), splineEmitPlugin(), maneuversDirApiPlugin()],
  base: './',
})
