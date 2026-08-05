# Domain Docs

How engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — module map, domain vocabulary, architectural invariants, QB64-PE language notes, and a "where to look for X" index. Load it at the start of any session touching game code.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. If the directory is empty, proceed silently; ADRs are created lazily via `/domain-modeling`.

If either file or directory doesn't exist, proceed silently.

## File structure

Single-context repo:

```
3d/                        ← git root
├── CONTEXT.md             ← domain context (load first)
├── docs/
│   ├── adr/               ← architectural decision records
│   │   └── 0001-*.md
│   └── agents/            ← skill configuration (this directory)
└── src/                   ← does not exist; source lives as *.bas at repo root
```

## Use the glossary's vocabulary

When naming issues, refactor proposals, test names, or hypotheses — use terms as defined in `CONTEXT.md`. In particular:

- "sequencer" = `sequence.bas` scene flow; not the music engine
- "wave" is ambiguous — clarify: "audio wave" or "enemy wave"
- "object" / "obj" = game entity; not a mesh
- "waypoint" in sequencer context ≠ waypoint in path-editor context

## Flag ADR conflicts

If a proposed change contradicts an existing ADR, surface it:

> _Contradicts ADR-0003 (no runtime file I/O) — but worth reopening because…_
