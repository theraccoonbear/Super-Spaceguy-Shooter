// Undo helpers for multi-step operations (drag, dialog edit).
// Pattern: call pauseAfterCheckpoint() at operation start so intermediate
// setWp/replaceWps calls don't flood pastStates. Call resumeTemporal() when
// the operation ends — the final state is already in the main store and will
// be captured as a past-state entry the next time anything changes.
import { useStore } from '../store'

/** Push the current path onto the undo stack, then pause temporal tracking.
 *  The checkpoint represents the "before" snapshot for the coming operation. */
export function pauseAfterCheckpoint(): void {
  const temp = useStore.temporal.getState()
  if (!temp.isTracking) return
  const { path } = useStore.getState()
  // _handleSet is zundo's internal API for pushing directly into pastStates.
  // The public TemporalState type omits it, so we cast.
  ;(temp as unknown as { _handleSet: (s: { path: typeof path }) => void })._handleSet({ path })
  temp.pause()
}

export function resumeTemporal(): void {
  useStore.temporal.getState().resume()
}
