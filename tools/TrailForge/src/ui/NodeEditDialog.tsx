// Modal dialog for editing a waypoint's X/Y/Z coordinates directly.
// Opened via right-click → "Edit Coords…" on a node in any ortho view.
// Live preview: each input change calls setWp immediately (temporal is
// paused while the dialog is open so no interim positions pollute undo).
// Set  → resumes temporal, commits one clean undo entry.
// Cancel → restores original coords, resumes temporal, no undo entry.

import { useState, useEffect, useCallback } from 'react'
import { useStore } from '../store'
import { resumeTemporal } from '../views/undoHelpers'

export function NodeEditDialog() {
  const { editGhost, setEditGhost, setWp, path } = useStore()

  // Local string state so partial decimal values aren't clobbered mid-type
  const [xs, setXs] = useState('')
  const [ys, setYs] = useState('')
  const [zs, setZs] = useState('')

  // Initialize local strings from the CURRENT wp (not ghost — ghost is the snapshot)
  useEffect(() => {
    if (!editGhost) return
    const wp = path.wps[editGhost.wpIdx]
    if (!wp) return
    setXs(String(wp.x))
    setYs(String(wp.y))
    setZs(String(wp.z))
  // Only re-init when the dialog opens (editGhost becomes non-null)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editGhost?.wpIdx])

  const applyCoords = useCallback((xStr: string, yStr: string, zStr: string) => {
    if (!editGhost) return
    const { wpIdx } = editGhost
    const wp = path.wps[wpIdx]
    if (!wp) return
    const x = parseFloat(xStr)
    const y = parseFloat(yStr)
    const z = parseFloat(zStr)
    setWp(wpIdx, { ...wp, x: isNaN(x) ? wp.x : x, y: isNaN(y) ? wp.y : y, z: isNaN(z) ? wp.z : z })
  }, [editGhost, path.wps, setWp])

  const handleSet = useCallback(() => {
    if (!editGhost) return
    applyCoords(xs, ys, zs)
    resumeTemporal()
    setEditGhost(null)
  }, [editGhost, xs, ys, zs, applyCoords, setEditGhost])

  const handleCancel = useCallback(() => {
    if (!editGhost) return
    // Restore original coords from the ghost snapshot
    const orig = editGhost.path.wps[editGhost.wpIdx]
    if (orig) setWp(editGhost.wpIdx, orig)
    resumeTemporal()
    setEditGhost(null)
  }, [editGhost, setWp, setEditGhost])

  // Escape closes (cancel)
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleCancel()
      if (e.key === 'Enter')  handleSet()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [handleCancel, handleSet])

  if (!editGhost) return null
  const wpIdx = editGhost.wpIdx

  const numField = (
    label: string,
    val: string,
    setVal: (s: string) => void,
    axis: 'x' | 'y' | 'z',
  ) => (
    <div className="modal-row" key={label}>
      <span className="modal-label" style={{ color: 'var(--text-dim)', width: 16 }}>{label}</span>
      <input
        type="number"
        value={val}
        step={0.5}
        style={{ width: 80, fontFamily: 'var(--font-mono)', fontSize: 12 }}
        onChange={e => {
          setVal(e.target.value)
          const n = parseFloat(e.target.value)
          if (!isNaN(n)) {
            const wp = path.wps[wpIdx]
            if (wp) setWp(wpIdx, { ...wp, [axis]: n })
          }
        }}
        onFocus={e => e.target.select()}
      />
    </div>
  )

  return (
    <div className="modal-overlay" onClick={handleCancel}>
      <div className="modal" style={{ maxWidth: 220 }} onClick={e => e.stopPropagation()}>
        <div className="modal-header">Edit Node {wpIdx} Coords</div>
        {numField('X', xs, setXs, 'x')}
        {numField('Y', ys, setYs, 'y')}
        {numField('Z', zs, setZs, 'z')}
        <div className="modal-footer">
          <button onClick={handleCancel}>Cancel</button>
          <button className="primary" onClick={handleSet}>Set</button>
        </div>
        <div style={{ fontSize: 9, color: 'var(--text-faint)', textAlign: 'right', marginTop: 4 }}>
          Enter to confirm · Esc to cancel
        </div>
      </div>
    </div>
  )
}
