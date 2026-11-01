# Scene sequencer (`src/sys/sequence.bas`)

## What problem it solves

The game's entire flow (intro crawl, cutscene cards, title screen, six combat/boss/asteroid stages, outro) is a graph of named blocks, each naming the block that follows it, defined in a plain-text data file (`assets/sequence.txt`) rather than hardcoded as a state machine in QBasic. Adding, reordering, or rebalancing stages is a data edit, not a code change, and `--scene <name>` (see the [root README](../../README.md#cli-options)) can jump straight to any waypoint for testing without playing through everything before it.

## `sequence.txt` format

```
label:id [secret]      block header; id is optional, becomes part of --scene names
    TASK key=val ...    task line, must be indented (spaces or a tab)
    NEXT <target>       the block's last line: the successor
```

A block is a header, its tasks (which run in order) and one `NEXT <target>` as its last line. `NEXT` is required and is a block exit, not a task: it adds no table entry, so `seqCount` and the milestone `seqIdx`/labels are unaffected. The target is `level:2` (the same `label:id` spelling as the header) or `end`, the deliberate terminal (the run is over; the outro uses it). File order means nothing. `secret` (a bare word on the header) marks a block no `NEXT` reaches, entered only by an explicit jump (`--scene`); it still needs a `NEXT`. A task after `NEXT`, a second `NEXT`, a `NEXT` with no target, or the old `next=` on a header are load errors. Docks and arrivals are ordinary tasks, so a block with no dock simply has none (stage 6). Example:

```
title:
    TITLE mus=title
    NEXT level:1

level:6
    ...
    ARRIVE mus=planet
    NEXT outro

outro:
    CRAWL txt=outro mus=crawl
    TITLE mus=title
    NEXT end

egg: secret
    CRAWL txt=hidden
    NEXT title
```

Conditional exits (`IF <flag> NEXT <target>`, choosing between successors) are not implemented yet; see #354, #315 and #271.

Five task types:

| Task | Fields | Effect |
|---|---|---|
| `CRAWL` | `txt=<gtext-key>` `mus=<cue>` | Shows the scrolling narrative crawl (text pulled from `assets/gametext.txt` via the given key) |
| `CARD` (alias `EMPEROR`, kept for backward compatibility) | `img=<image-key>` `mus=<cue>` | Shows a full-screen cutscene card |
| `TITLE` | `mus=<cue>` | Shows the title screen |
| `PLAY` | `type=combat\|boss\|asteroid` `mus=<cue>` `[trigger=<n>]` | Enters gameplay. `trigger` is a score/distance threshold, see below |
| `ARRIVE` | `mus=<cue>` | Shows the planet-arrival screen for the stage just completed |
| `DOCK` | `[mus=<cue>]` | Opens the upgrade dock (`src/state/dock.bas`); an explicit task in each block that has one (none after the last stage). `--scene dockN` jumps to it |

Example (`assets/sequence.txt`, stage 3, a combat phase followed by a boss fight):

```
level:3
    CRAWL txt=stage3 mus=crawl
    PLAY type=combat mus=game trigger=10
    PLAY type=boss mus=boss
    ARRIVE mus=planet
    DOCK
    NEXT level:4
```

`trigger` means different things per `PLAY` type: for `combat`, the enemy kills that end the phase (scaled by `NERF_FACTOR` in `--nerf` mode, at least 1; points from power-ups and bonuses don't count, #312); for `asteroid`, distance in parsecs; `boss` ignores it (a boss fight ends when the boss dies, not on a kill count).

Boss `PLAY` lines also take per-phase lists, one comma-separated entry per HP phase: `mus=` (music cues), `speech=` (gametext keys; an empty entry means no line), `maneuver=` (flight patterns, currently unused in play), and `attack=`. `seek=` is a single number, the bullet homing strength. `attack=` is not per phase: it is the boss's attack pool (#26), any of `laser`, `spore` (spore bloom), `cut` (the cut) and `devour` (a pull toward the boss). Each volley the boss picks ONE pool entry at random, never two at once (the one exception: during devour's pull the boss keeps firing lasers, by design); a special that just fired cools down for 4 s, and picking it again in that time fires lasers instead (see `src/gameplay/attacks.bas`). Pools stack across bosses: level 3 is `attack=laser,spore`, level 5 `attack=laser,spore,cut`, level 6 `attack=laser,spore,cut,devour`. HP phases still escalate every attack: bigger, faster laser patterns, one spore cloud per phase reached (`src/gameplay/spores.bas`), one cut per phase reached in a chain (`src/gameplay/cuts.bas`), a stronger devour pull per phase (`src/gameplay/devour.bas`). `hp=` (#90) is the boss's hit points (level 3 `hp=30`, level 5 `hp=90`, level 6 `hp=130`; missing = `boss_hp_default` in `assets/config/bosses.ini`, x 0.1 under `--nerf`, at least 3). Phase 2 and 3 start at 66% and 33% of it, a hit never carries past the next phase's start, and the boss is shielded while each phase callout plays (`src/gameplay/bosshp.bas`). `secs=` (#90) is how long the fight is expected to take, for the dock's NEXT JUMP NEEDS (level 3 `secs=22`, level 5 `secs=25`, level 6 `secs=32`; missing = `fuel_boss_secs` in `assets/config/economy.ini`).

## Runtime API

```basic
SEQ_Load seqText$        ' parse sequence.txt (or any string in the same format) into the block and task tables; call once at startup
SEQ_Validate$()           ' "" when sound, else one problem per line: load errors, no NEXT, dangling NEXT, unreachable non-secret blocks
SEQ_NextIdx%(i)           ' the task after task i, following NEXT across blocks; -1 = the sequence ends
SEQ_Advance               ' step forward one waypoint and execute it (sets gameState, triggers music, etc.)
SEQ_RewindToTitle         ' jump seqIdx back to the first TITLE waypoint, without executing anything
SEQ_QuitRun               ' pause-menu quit: session end with exit=quit, run over, park at the title
SEQ_QuitProcess           ' window close / title QUIT: a run in progress ends once as exit=quit (no run, nothing)
SEQ_JumpToScene%(spec$)   ' resolve a --scene spec to a table index; returns -1 + seqLastError on failure
SEQ_GetKV$(sval$, key$)   ' extract "key=val" from a task's key=val... string
SEQ_PrintScenes fh        ' print all valid --scene names, for --help
```

`SEQ_Advance` is the workhorse: it moves `seqIdx` to the next task (the next one in the block, else the first task of the block its `NEXT` names; `SEQ_NextIdx%`), looks at `seqKind(seqIdx)`, and does whatever that waypoint means. It sets `gameState`, sets the music cue, and for `PLAY` specifically, resets the appropriate stage state (`levelNum`, `stageKills`, `stageKillTarget`, `levelType`, fuel for asteroid fields, `boss.warnTimer` for boss fights, and so on). The chain ending (a `NEXT end` block running out of tasks), or landing on the outro's `TITLE` task, both mean "the run is over" (`SEQ_EndRunWin`): leftover credits are cashed in, `highScore` is saved if beaten, and `TELEM_SessionEnd` fires with `exit=win`. That only happens while `seqRunActive` is set: the first `PLAY` of a run sets it, and every run end (win, death, stranded, `SEQ_QuitRun`) clears it. Any other landing on a `TITLE` task, such as SPACE on the intro emperor card or `--scene title`, just shows the title, the same as ESC (#331). Either way `SEQ_RewindToTitle` parks `seqIdx` at the first title waypoint.

### The title screen is a waypoint, not a mode

This is the sequencer's central design choice: `GS_TITLE` isn't a state the game falls back to and later leaves via a special "start game" transition, it's just another `SEQ_TITLE` task in the table. `SEQ_RewindToTitle` always parks at the *first* title waypoint (right after the intro crawl/card), so "New Game" from the title is really just "advance from here," which naturally lands on chapter 1's crawl. The prologue crawl and emperor card, at the very front of the table, are only ever visited once per process lifetime: the game boots directly into them and nothing ever rewinds `seqIdx` that far back.

### `--scene` resolution (`SEQ_JumpToScene%`)

```
crawl0     -> the CRAWL task in label "crawl0"          (intro crawl)
crawlN     -> the CRAWL task in label "levelN"           (N >= 1)
playingN   -> the first PLAY type=combat|asteroid task in label "levelN"
bossN      -> the first PLAY type=boss task in label "levelN"
title      -> the first SEQ_TITLE entry
emperor    -> the first SEQ_EMPEROR entry
```

It sets `seqIdx` to one *before* the resolved index and returns the resolved index; the caller (`sss.bas`'s startup block) then calls `SEQ_Advance` once to actually land on it, same as normal flow, just seeded to start somewhere other than the very beginning. For `playingN`/`bossN`, `sss.bas` also pre-seeds `levelNum` by parsing the digits out of the scene name (`playingN` → `levelNum = N - 1`, since `SEQ_Advance`'s `combat`/`asteroid` branch increments it; `bossN` → `levelNum = N`, since the boss branch doesn't increment it) so per-level kill targets and planet indices come out the same as if you'd played through normally.

## How to add a new task type

1. Add a `Const SEQ_YOURTYPE = <next number>` alongside the existing `SEQ_CRAWL`/`SEQ_EMPEROR`/`SEQ_PLAY`/`SEQ_TITLE`/`SEQ_ARRIVE` constants.
2. Add a `Case "YOURTYPE" : SEQ_Add SEQ_YOURTYPE, seqlSval` branch in `SEQ_Load`'s task-line `Select Case`.
3. Add a `Case SEQ_YOURTYPE` branch in `SEQ_Advance`'s dispatch `Select Case` that does whatever entering this waypoint should do (set `gameState`, set a music cue, reset whatever state the new mode needs).
4. If it should be reachable via `--scene`, add its name to `SEQ_SCENE_TYPES` (the one list `CLI_Parse` accepts and `--help` walks), a case to `SEQ_JumpToScene%`'s type dispatch, and a case to `SEQ_SceneList$` if it should only be listed when `sequence.txt` has one. `scene_jump_planet_test` jumps to every scene `--help` lists.
5. Add task lines using it to `assets/sequence.txt`.

## Known limitations and gotchas

- **`SEQ_MAX = 64` tasks and `SEQ_BLK_MAX = 32` blocks are fixed caps.** Going past either sets `seqLoadErr` (the extra entry is dropped) and `SEQ_Validate$` reports it; `tests/seq_graph_test.bas` asserts the shipped file loads clean with headroom.
- **`SEQ_GetKV$` is a linear string scan, not a real parser.** Values can't contain spaces (a space always ends the value), and there's no escaping.
- **Single global `seqIdx`, no history, no conditional branching.** Each block has exactly one successor. There is no "go back" and no choosing between successors based on player choices (#315, #271); `SEQ_RewindToTitle` and `--scene` (`seqJumpTo`, so a jump may land on any block's first task whatever precedes it) are the only jumps.
- **`--scene playingN`/`bossN`'s `levelNum` seeding is convention-based**, parsed from the scene name's digits rather than derived from the sequence table itself. If the `levelN` label-naming convention in `sequence.txt` ever changes, this logic (in `sss.bas`'s startup block, not in `sequence.bas` itself) needs to change with it.

## Testing in isolation

Four test files cover this thoroughly with stubbed game state, no full game boot required:

```bash
tools/buildqb tests/seq_trace_test.bas         && builds/seq_trace_test          # boot flow, NewGame, ESC-at-emperor regressions, highScore
tools/buildqb tests/seq_dispatch_test.bas      && builds/seq_dispatch_test       # parser, SEQ_GetKV$, SEQ_JumpToScene% valid/invalid, SEQ_Advance dispatch per task type
tools/buildqb tests/scene_jump_planet_test.bas && builds/scene_jump_planet_test  # --scene playingN -> correct planet/stage index for every level
tools/dev test                                                      # (runs seq_graph_test, among all tests) shipped file validates (no dangling NEXT, dead end, unreachable block, overflow); each failure detected; Advance/NextLeg follow NEXT; secret blocks
```

For an end-to-end check against the real game binary, `--scene <name>` is itself the fastest manual test: `builds/sss --scene boss3` drops straight into stage 3's boss fight.
