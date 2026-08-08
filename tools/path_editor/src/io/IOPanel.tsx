// Import / Export panel.
// Export: generates maneuvers.txt block → copy to clipboard or download.
// Import: open a .txt file with <input type="file"> → parse all [name] blocks → pick one.

import { useState, useRef, useCallback } from 'react'
import { useStore, PathData } from '../store'
import { exportBlock, parseBlocks } from './format'

export function IOPanel() {
  const { path, setPath, setStatus } = useStore()
  const [exportText, setExportText] = useState('')
  const [importBlocks, setImportBlocks] = useState<Map<string, PathData>>(new Map())
  const [selectedBlock, setSelectedBlock] = useState('')
  const fileInputRef = useRef<HTMLInputElement>(null)

  // ── Export ────────────────────────────────────────────────────────────
  const handleExport = useCallback(() => {
    const text = exportBlock(path)
    setExportText(text)
  }, [path])

  const handleCopy = useCallback(async () => {
    if (!exportText) return
    try {
      await navigator.clipboard.writeText(exportText)
      setStatus('copied to clipboard')
    } catch {
      setStatus('copy failed — select text manually')
    }
  }, [exportText, setStatus])

  const handleDownload = useCallback(() => {
    const text = exportText || exportBlock(path)
    if (!exportText) setExportText(text)
    const blob = new Blob([text], { type: 'text/plain' })
    const url  = URL.createObjectURL(blob)
    const a    = document.createElement('a')
    a.href     = url
    a.download = `${path.name}.txt`
    a.click()
    URL.revokeObjectURL(url)
    setStatus(`downloaded ${path.name}.txt`)
  }, [exportText, path, setStatus])

  // ── Import ────────────────────────────────────────────────────────────
  const handleFileOpen = useCallback(() => {
    fileInputRef.current?.click()
  }, [])

  const handleFileChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => {
      const text = ev.target?.result as string
      const blocks = parseBlocks(text)
      setImportBlocks(blocks)
      const first = blocks.keys().next().value as string | undefined
      setSelectedBlock(first ?? '')
      setStatus(`opened ${file.name} — ${blocks.size} block(s) found`)
    }
    reader.readAsText(file)
    // Reset so the same file can be re-opened
    e.target.value = ''
  }, [setStatus])

  const handleLoad = useCallback(() => {
    const block = importBlocks.get(selectedBlock)
    if (!block) return
    setPath(block)
    setStatus(`loaded [${selectedBlock}]`)
  }, [importBlocks, selectedBlock, setPath, setStatus])

  const blockNames = Array.from(importBlocks.keys())

  return (
    <div className="io-panel">
      {/* Export */}
      <div className="io-section" style={{ flex: 1, minHeight: 0 }}>
        <div className="io-section-label">Export</div>
        <div className="io-row">
          <button className="primary" onClick={handleExport}>Generate ↓</button>
          <button onClick={handleCopy}    disabled={!exportText}>Copy</button>
          <button onClick={handleDownload}>Download</button>
        </div>
        <textarea
          readOnly
          value={exportText}
          placeholder="click Generate to produce the [name] block"
          style={{ flex: 1 }}
          onClick={(e) => (e.target as HTMLTextAreaElement).select()}
        />
      </div>

      {/* Import */}
      <div className="io-section" style={{ flex: 1, minHeight: 0 }}>
        <div className="io-section-label">Import</div>
        <div className="io-row">
          <button className="primary" onClick={handleFileOpen}>Open File…</button>
          {blockNames.length > 1 && (
            <select
              value={selectedBlock}
              onChange={(e) => setSelectedBlock(e.target.value)}
              style={{
                flex: 1,
                background: 'var(--surface)',
                border: '1px solid var(--border2)',
                color: 'var(--text)',
                fontFamily: 'var(--font-mono)',
                fontSize: '11px',
                padding: '2px 4px',
                borderRadius: 'var(--radius)',
              }}
            >
              {blockNames.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          )}
          {blockNames.length === 1 && (
            <span style={{ color: 'var(--path)', fontSize: '11px', padding: '2px 6px' }}>
              [{blockNames[0]}]
            </span>
          )}
          {blockNames.length > 0 && (
            <button className="primary" onClick={handleLoad}>Load →</button>
          )}
        </div>
        {blockNames.length === 0 && (
          <div style={{ color: 'var(--text-faint)', fontSize: '10px', paddingTop: 4 }}>
            Open a maneuvers.txt file to import blocks
          </div>
        )}
        {blockNames.length > 0 && (
          <div style={{ color: 'var(--text-dim)', fontSize: '10px' }}>
            {blockNames.length} block{blockNames.length > 1 ? 's' : ''} found:&nbsp;
            <span style={{ color: 'var(--path)' }}>{blockNames.join(', ')}</span>
          </div>
        )}
      </div>

      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        accept=".txt,text/plain"
        style={{ display: 'none' }}
        onChange={handleFileChange}
      />
    </div>
  )
}
