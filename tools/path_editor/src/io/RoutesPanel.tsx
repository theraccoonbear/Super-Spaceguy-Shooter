// Live maneuvers.txt integration (dev-server only).
// Fetches /api/maneuvers (served by the Vite plugin in vite.config.ts),
// lets you load / save / create routes directly in the file.
// Falls back gracefully when the API is not available (production build).

import { useState, useEffect, useCallback } from 'react'
import { useStore, PathData } from '../store'
import { exportBlock, parseBlocks } from './format'
import { GenerateDialog } from '../ui/GenerateDialog'

export function RoutesPanel() {
  const { path, setPath, setStatus } = useStore()

  const [apiAvail,     setApiAvail]     = useState<boolean | null>(null) // null = loading
  const [allBlocks,    setAllBlocks]    = useState<Map<string, PathData>>(new Map())
  const [selectedName, setSelectedName] = useState('')
  const [savedPath,    setSavedPath]    = useState<PathData | null>(null)
  const [saving,       setSaving]       = useState(false)
  const [showNewDialog, setShowNewDialog] = useState(false)

  // Consider the current path dirty if it differs from the last loaded / saved snapshot.
  const isDirty = savedPath !== null &&
    JSON.stringify({ ...path, name: savedPath.name }) !== JSON.stringify(savedPath)

  // ── Fetch on mount ─────────────────────────────────────────────────────
  const fetchFile = useCallback(() => {
    fetch('/api/maneuvers')
      .then(r => { if (!r.ok) throw new Error('not ok'); return r.text() })
      .then(text => {
        setApiAvail(true)
        const parsed = parseBlocks(text)
        setAllBlocks(parsed)
        // Preserve selection if it still exists, otherwise take first
        setSelectedName(prev =>
          parsed.has(prev) ? prev : ((parsed.keys().next().value as string | undefined) ?? ''))
      })
      .catch(() => setApiAvail(false))
  }, [])

  useEffect(() => { fetchFile() }, [fetchFile])

  // ── Load ───────────────────────────────────────────────────────────────
  const handleLoad = useCallback(() => {
    const block = allBlocks.get(selectedName)
    if (!block) return
    if (isDirty && !window.confirm(
      `"${path.name}" has unsaved changes.\nDiscard and load "${selectedName}"?`
    )) return
    setPath(block)
    setSavedPath(block)
    setStatus(`loaded [${selectedName}]`)
  }, [allBlocks, selectedName, setPath, setStatus, isDirty, path.name])

  // ── Save (shared impl) ─────────────────────────────────────────────────
  const doSave = useCallback(async (name: string) => {
    const updated: PathData = { ...path, name }

    // Rebuild the entire file: update or append the current block
    const newBlocks = new Map(allBlocks)
    newBlocks.set(name, updated)

    const fileText = Array.from(newBlocks.values())
      .map(b => exportBlock(b))
      .join('\n\n') + '\n'

    setSaving(true)
    try {
      const r = await fetch('/api/maneuvers', {
        method: 'PUT',
        headers: { 'Content-Type': 'text/plain' },
        body: fileText,
      })
      if (!r.ok) throw new Error(`${r.status}`)
      setPath(updated)
      setAllBlocks(newBlocks)
      setSelectedName(name)
      setSavedPath(updated)
      setStatus(`saved [${name}] to maneuvers.txt`)
    } catch (err) {
      setStatus(`save failed -- ${err}`)
    }
    setSaving(false)
  }, [path, allBlocks, setPath, setStatus])

  const handleSave = useCallback(() => {
    doSave(path.name.trim() || selectedName || 'unnamed')
  }, [doSave, path.name, selectedName])

  const handleSaveAs = useCallback(() => {
    const newName = window.prompt('Save as:', path.name.trim() || selectedName || 'unnamed')?.trim()
    if (!newName) return
    doSave(newName)
  }, [doSave, path.name, selectedName])

  // ── New route ──────────────────────────────────────────────────────────
  // Opens the shape picker; GenerateDialog handles creation with name='untitled'/speed=0.25
  const handleNew = useCallback(() => {
    if (isDirty && !window.confirm(
      `"${path.name}" has unsaved changes.\nDiscard and create a new route?`
    )) return
    setShowNewDialog(true)
  }, [isDirty, path.name])

  // ── Loading state ──────────────────────────────────────────────────────
  if (apiAvail === null) {
    return (
      <div className="io-panel">
        <div className="io-section">
          <div className="io-section-label">Routes</div>
          <div style={{ color: 'var(--text-faint)', fontSize: 10 }}>connecting...</div>
        </div>
      </div>
    )
  }

  // ── No dev server ──────────────────────────────────────────────────────
  if (!apiAvail) {
    return (
      <div className="io-panel">
        <div className="io-section">
          <div className="io-section-label">Routes (dev server only)</div>
          <div style={{ color: 'var(--text-faint)', fontSize: 10, lineHeight: 1.7, marginBottom: 6 }}>
            Start the Vite dev server<br />(npm run dev) to enable<br />live maneuvers.txt editing.
          </div>
          <div className="io-row">
            <button onClick={fetchFile}>Retry</button>
          </div>
        </div>
      </div>
    )
  }

  const blockNames = Array.from(allBlocks.keys())

  // ── Main UI ────────────────────────────────────────────────────────────
  return (
    <div className="io-panel">
      <div className="io-section">
        <div className="io-section-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
          <span>maneuvers.txt</span>
          {isDirty && <span style={{ color: 'var(--sel)' }}>● unsaved</span>}
        </div>

        <div style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
          <select
            value={selectedName}
            onChange={e => setSelectedName(e.target.value)}
            style={{
              flex: 1, background: 'var(--surface)', border: '1px solid var(--border2)',
              color: 'var(--text)', fontFamily: 'var(--font-mono)', fontSize: 11,
              padding: '3px 4px', borderRadius: 'var(--radius)', outline: 'none',
            }}
          >
            {blockNames.map(n => <option key={n} value={n}>{n}</option>)}
          </select>
          <button title="Reload from disk" onClick={fetchFile} style={{ padding: '3px 7px' }}>↺</button>
        </div>

        <div className="io-row">
          <button className="primary"
            onClick={handleLoad}
            disabled={!selectedName || !allBlocks.has(selectedName)}>
            Load →
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className={isDirty ? 'primary' : ''}
            title={`Overwrite [${path.name.trim() || selectedName || 'unnamed'}] in maneuvers.txt`}>
            {saving ? '...' : 'Save'}
          </button>
          <button
            onClick={handleSaveAs}
            disabled={saving}
            title="Save under a new name">
            Save As…
          </button>
          <button onClick={handleNew} title="Create a new blank route">+ New</button>
        </div>

        {blockNames.length > 0 && (
          <div style={{ color: 'var(--text-faint)', fontSize: 10, marginTop: 2 }}>
            {blockNames.length} route{blockNames.length !== 1 ? 's' : ''} in file
          </div>
        )}
      </div>
      {showNewDialog && (
        <GenerateDialog newRoute onClose={() => setShowNewDialog(false)} />
      )}
    </div>
  )
}
