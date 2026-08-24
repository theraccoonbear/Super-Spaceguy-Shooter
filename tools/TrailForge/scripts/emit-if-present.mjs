// Run emit-spline.js only when living inside the SSS repo (math/formula.expr exists).
// When TrailForge is its own standalone repo, spline_gen.ts is pre-built — skip silently.
import { existsSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'
import { execSync } from 'child_process'

const __dir   = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(__dir, '../../../')
const dslFile  = resolve(repoRoot, 'math/formula.expr')

if (existsSync(dslFile)) {
  execSync(
    '(cd math && npm install --prefer-offline --silent) && node tools/emit-spline.js',
    { cwd: repoRoot, stdio: 'inherit', shell: true },
  )
} else {
  console.log('[spline] spline_gen.ts is pre-built — skipping emit')
}
