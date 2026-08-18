// In-editor help dialog — keyboard shortcut: ?
// Renders from the SHORTCUTS registry so it can never drift from the actual keybindings.
// Static "Notes" sections at the bottom cover UI controls that aren't keyboard/mouse shortcuts.

import type { ReactNode } from 'react'
import { SHORTCUTS } from '../shortcuts'

interface Props { onClose: () => void }

export function HelpDialog({ onClose }: Props) {
  // Build ordered list of unique contexts, preserving insertion order from registry
  const contexts = Array.from(new Set(SHORTCUTS.map(s => s.context)))

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal"
        style={{ maxWidth: 580, maxHeight: '82vh', overflowY: 'auto' }}
        onClick={e => e.stopPropagation()}>

        <div className="modal-header"
          style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span>Trailforge Help</span>
          <button style={{ fontSize: 12, padding: '2px 8px' }} onClick={onClose}>✕</button>
        </div>

        {/* Registry-driven sections */}
        {contexts.map(ctx => (
          <Section key={ctx} title={ctx}>
            {SHORTCUTS.filter(s => s.context === ctx).map(s => (
              <Row key={s.keys} k={s.keys} v={s.desc} />
            ))}
          </Section>
        ))}

        {/* Static notes — UI controls that aren't keyboard/mouse shortcuts */}
        <Section title="Toolbar controls">
          <Row k="Speed" v="Arc-length correct — constant world-space speed regardless of node spacing" />
          <Row k="Orient" v="PATH-FOLLOWING = nose follows curve; FIXED TARGET = nose faces target point" />
          <Row k="Standoff" v="Perpendicular offset from wire curve; use node P° to angle it" />
          <Row k="LINKED / FREE" v="Sync all ortho pan/zoom (L key toggles)" />
          <Row k="GAME CTX" v="Show game-context overlays: player ship, camera frustum, scale planes" />
          <Row k="DBG LOG" v="Log per-frame pos, fwd, R, U vectors to browser console" />
          <Row k="BEHAVIORS" v="Toggle behaviors panel (B key toggles)" />
        </Section>

        <Section title="Waypoint rolls (sidebar)">
          <Row k="P° — Path Roll" v="Rotates the standoff offset direction at this node" />
          <Row k="C° — Craft Roll" v="Banks the ship body at this node (cosmetic)" />
        </Section>

        <Section title="Shape generator (⬡ Gen)">
          <Row k="Circle / Ellipse" v="Parametric loop in chosen axis plane" />
          <Row k="Figure-8" v="Lemniscate of Gerono — figure-of-eight loop" />
          <Row k="Helix" v="Corkscrew along X axis" />
          <Row k="Arc" v="Partial sweep of a circle" />
        </Section>

        <div style={{ marginTop: 12, fontSize: 10, color: 'var(--text-faint)', textAlign: 'right' }}>
          Press Esc or click outside to close
        </div>
      </div>
    </div>
  )
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{
        fontSize: 11, fontWeight: 700, color: 'var(--accent)', textTransform: 'uppercase',
        letterSpacing: '0.06em', marginBottom: 4, paddingBottom: 2, borderBottom: '1px solid var(--border2)'
      }}>
        {title}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '190px 1fr', gap: '2px 8px', fontSize: 11 }}>
        {children}
      </div>
    </div>
  )
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <>
      <span style={{ color: 'var(--text-dim)', fontFamily: 'var(--font-mono)', fontSize: 10 }}>{k}</span>
      <span style={{ color: 'var(--text)' }}>{v}</span>
    </>
  )
}
