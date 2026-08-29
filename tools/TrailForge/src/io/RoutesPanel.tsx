// Live maneuvers/ directory integration (dev-server only).
// Each route is stored as a separate .mvr file under assets/maneuvers/.
// Fetches the route list from /api/maneuvers; loads/saves individual routes
// via /api/maneuvers/:name. Writes are atomic (tmp → rename on the server).
// Falls back gracefully when the API is not available (production build).

import { useState, useEffect, useCallback } from 'react'
import { useStore, PathData } from '../store'
import { exportBlock, parseFile, nameToFilename } from './format'
import { GenerateDialog } from '../ui/GenerateDialog'

export function RoutesPanel() {
  const { path, setPath, setStatus } = useStore()

  const [apiAvail,      setApiAvail]      = useState<boolean | null>(null) // null = loading
  const [routeNames,    setRouteNames]    = useState<string[]>([])
  const [selectedName,  setSelectedName]  = useState('')
  const [savedPath,     setSavedPath]     = useState<PathData | null>(null)
  const [loading,       setLoading]       = useState(false)
  const [saving,        setSaving]        = useState(false)
  const [showNewDialog, setShowNewDialog] = useState(false)

  // Consider the current path dirty if it differs from the last loaded / saved snapshot.
  const isDirty = savedPath !== null &&
    JSON.stringify({ ...path, name: savedPath.name }) !== JSON.stringify(savedPath)

  // ── Fetch route list ───────────────────────────────────────────────────
  const fetchList = useCallback(() => {
    fetch('/api/maneuvers')
      .then(r => { if (!r.ok) throw new Error('not ok'); return r.json() })
      .then(({ routes }: { routes: string[] }) => {
        setApiAvail(true)
        setRouteNames(routes)
        setSelectedName(prev => routes.includes(prev) ? prev : (routes[0] ?? ''))
      })
      .catch(() => setApiAvail(false))
  }, [])

  useEffect(() => { fetchList() }, [fetchList])

  // ── Load ───────────────────────────────────────────────────────────────
  const handleLoad = useCallback(async () => {
    if (!selectedName) return
    if (isDirty && !window.confirm(
      `"${path.name}" has unsaved changes.\nDiscard and load "${selectedName}"?`
    )) return
    setLoading(true)
    try {
      const r = await fetch(`/api/maneuvers/${encodeURIComponent(selectedName)}`)
      if (!r.ok) throw new Error(`${r.status}`)
      const text   = await r.text()
      const loaded = parseFile(text)
      if (!loaded) throw new Error('parse error')
      setPath(loaded)
      setSavedPath(loaded)
      setStatus(`loaded [${loaded.name}]`)
    } catch (err) {
      setStatus(`load failed -- ${err}`)
    }
    setLoading(false)
  }, [selectedName, isDirty, path.name, setPath, setStatus])

  // ── Save (shared impl) ─────────────────────────────────────────────────
  const doSave = useCallback(async (name: string) => {
    const updated  = { ...path, name } as PathData
    const filename = nameToFilename(name)
    setSaving(true)
    try {
      const r = await fetch(`/api/maneuvers/${encodeURIComponent(filename)}`, {
        method:  'PUT',
        headers: { 'Content-Type': 'text/plain' },
        body:    exportBlock(updated),
      })
      if (!r.ok) throw new Error(`${r.status}`)
      setPath(updated)
      setSelectedName(filename)
      setSavedPath(updated)
      setRouteNames(prev =>
        prev.includes(filename) ? prev : [...prev, filename].sort()
      )
      setStatus(`saved → maneuvers/${filename}.mvr`)
    } catch (err) {
      setStatus(`save failed -- ${err}`)
    }
    setSaving(false)
  }, [path, setPath, setStatus])

  const handleSave = useCallback(() => {
    doSave(path.name.trim() || selectedName || 'unnamed')
  }, [doSave, path.name, selectedName])

  const handleSaveAs = useCallback(() => {
    const newName = window.prompt('Save as:', path.name.trim() || selectedName || 'unnamed')?.trim()
    if (!newName) return
    doSave(newName)
  }, [doSave, path.name, selectedName])

  // ── Delete ─────────────────────────────────────────────────────────────
  const handleDelete = useCallback(async () => {
    if (!selectedName) return
    if (!window.confirm(`Delete "${selectedName}.mvr"?\nThis cannot be undone.`)) return
    try {
      const r = await fetch(`/api/maneuvers/${encodeURIComponent(selectedName)}`, {
        method: 'DELETE',
      })
      if (!r.ok) throw new Error(`${r.status}`)
      const remaining = routeNames.filter(n => n !== selectedName)
      setRouteNames(remaining)
      setSelectedName(remaining[0] ?? '')
      if (savedPath && nameToFilename(savedPath.name) === selectedName) setSavedPath(null)
      setStatus(`deleted ${selectedName}.mvr`)
    } catch (err) {
      setStatus(`delete failed -- ${err}`)
    }
  }, [selectedName, routeNames, savedPath, setStatus])

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
            Start the Vite dev server<br />(npm run dev) to enable<br />live maneuvers/ editing.
          </div>
          <div className="io-row">
            <button onClick={fetchList}>Retry</button>
          </div>
        </div>
      </div>
    )
  }

  const saveName = path.name.trim() || selectedName || 'unnamed'

  // ── Main UI ────────────────────────────────────────────────────────────
  return (
    <div className="io-panel">
      <div className="io-section">
        <div className="io-section-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
          <span>maneuvers/</span>
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
            {routeNames.map(n => <option key={n} value={n}>{n}</option>)}
          </select>
          <button title="Refresh route list" onClick={fetchList} style={{ padding: '3px 7px' }}>↺</button>
        </div>

        <div className="io-row">
          <button className="primary"
            onClick={handleLoad}
            disabled={!selectedName || loading}>
            {loading ? '…' : 'Load →'}
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className={isDirty ? 'primary' : ''}
            title={`Save as maneuvers/${nameToFilename(saveName)}.mvr`}>
            {saving ? '...' : 'Save'}
          </button>
          <button
            onClick={handleSaveAs}
            disabled={saving}
            title="Save under a new name">
            Save As…
          </button>
          <button onClick={handleNew} title="Create a new blank route">+ New</button>
          <button
            onClick={handleDelete}
            disabled={!selectedName}
            title={selectedName ? `Delete ${selectedName}.mvr` : ''}
            style={{ color: 'var(--text-dim)' }}>
            Del
          </button>
        </div>

        {routeNames.length > 0 && (
          <div style={{ color: 'var(--text-faint)', fontSize: 10, marginTop: 2 }}>
            {routeNames.length} route{routeNames.length !== 1 ? 's' : ''}
          </div>
        )}
      </div>
      {showNewDialog && (
        <GenerateDialog newRoute onClose={() => setShowNewDialog(false)} />
      )}
    </div>
  )
}
