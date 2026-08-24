#!/usr/bin/env node
// One-shot migration: splits assets/maneuvers.txt → assets/maneuvers/*.mvr
//
// Run from the repo root: node tools/migrate-maneuvers.js
//
// Each [route-name] block in maneuvers.txt becomes its own .mvr file.
// Existing .mvr files are NOT overwritten (re-run is safe).
// After migration, archive or delete maneuvers.txt once the game side
// is also updated to read from assets/maneuvers/*.mvr.

'use strict'

const fs   = require('fs')
const path = require('path')

const REPO   = path.resolve(__dirname, '..')
const SRC    = path.join(REPO, 'assets/maneuvers.txt')
const OUTDIR = path.join(REPO, 'assets/maneuvers')

// Must match nameToFilename() in src/io/format.ts
function nameToFilename(name) {
  return name.trim()
    .toLowerCase()
    .replace(/[\s_]+/g, '-')
    .replace(/[^a-z0-9-]/g, '')
    .replace(/-{2,}/g, '-')
    .replace(/^-+|-+$/g, '')
    || 'unnamed'
}

if (!fs.existsSync(SRC)) {
  console.error(`Not found: ${SRC}`)
  process.exit(1)
}

const text   = fs.readFileSync(SRC, 'utf-8')
const blocks = []

let cur = null
for (const rawLine of text.split(/\r?\n/)) {
  const header = rawLine.trim().match(/^\[([^\]]+)\]$/)
  if (header) {
    if (cur) blocks.push(cur)
    cur = { name: header[1], lines: [rawLine] }
  } else if (cur) {
    cur.lines.push(rawLine)
  }
}
if (cur) blocks.push(cur)

if (blocks.length === 0) {
  console.log('No [route] blocks found in maneuvers.txt — nothing to do.')
  process.exit(0)
}

fs.mkdirSync(OUTDIR, { recursive: true })

let wrote = 0, skipped = 0
for (const block of blocks) {
  const stem = nameToFilename(block.name)
  const dest = path.join(OUTDIR, `${stem}.mvr`)
  if (fs.existsSync(dest)) {
    console.log(`  skip   ${stem}.mvr  (already exists)`)
    skipped++
    continue
  }
  const content = block.lines.join('\n').trimEnd() + '\n'
  fs.writeFileSync(dest, content, 'utf-8')
  console.log(`  wrote  ${stem}.mvr  ← [${block.name}]`)
  wrote++
}

console.log(`\n${wrote} written, ${skipped} skipped → ${OUTDIR}/`)
if (wrote + skipped === blocks.length) {
  console.log('Migration complete. Archive assets/maneuvers.txt once the game side is updated.')
}
