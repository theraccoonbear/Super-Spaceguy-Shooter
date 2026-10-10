// Right-click context menu for waypoints (wpIdx >= 0) or empty space (wpIdx < 0).
// Rendered as position:fixed so it floats above everything.
// Close on Escape or any click outside.

import { useEffect } from 'react'
import { useStore } from '../store'

interface Props {
  x: number
  y: number
  wpIdx: number         // >= 0: waypoint menu; < 0: empty-space menu
  onClose: () => void
  onAddHere?: () => void    // provided only for empty-space clicks
  onEditCoords?: () => void // provided only for waypoint clicks
}

export function CtxMenu({ x, y, wpIdx, onClose, onAddHere, onEditCoords }: Props) {
  const { delWp, dupWp, addWp, path } = useStore()

  // Close on any outside click (deferred one tick to not fire on the same event that opened)
  useEffect(() => {
    let handler: () => void
    const id = setTimeout(() => {
      handler = () => onClose()
      window.addEventListener('pointerdown', handler, { once: true })
    }, 0)
    return () => {
      clearTimeout(id)
      if (handler) window.removeEventListener('pointerdown', handler)
    }
  }, [onClose])

  // Close on Escape
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  // Clamp to viewport so menu doesn't spill off screen
  const left = Math.min(x, window.innerWidth  - 170)
  const top  = Math.min(y, window.innerHeight - 120)

  if (wpIdx < 0) {
    // Empty-space context menu
    return (
      <div className="ctx-menu" style={{ left, top }} onPointerDown={e => e.stopPropagation()}>
        {onAddHere && (
          <button className="ctx-item" onClick={() => { onAddHere(); onClose() }}>
            + Add Waypoint Here
          </button>
        )}
      </div>
    )
  }

  // Waypoint context menu
  return (
    <div className="ctx-menu" style={{ left, top }} onPointerDown={e => e.stopPropagation()}>
      {onEditCoords && (
        <button className="ctx-item" onClick={() => { onEditCoords(); onClose() }}>
          Edit Coords…
        </button>
      )}
      <div className="ctx-sep" />
      <button className="ctx-item" onClick={() => { delWp(wpIdx); onClose() }}>
        Delete
      </button>
      <button className="ctx-item" onClick={() => { dupWp(wpIdx); onClose() }}>
        Duplicate
      </button>
      <div className="ctx-sep" />
      <button className="ctx-item"
        onClick={() => { addWp({ ...path.wps[wpIdx] }, wpIdx); onClose() }}>
        Insert After
      </button>
    </div>
  )
}
