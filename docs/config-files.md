# Config files

Game data that isn't code lives in small `key=value` files (`;` starts a comment, no spaces around `=`), embedded at build time and parsed by one shared loader, `CFG_Parse$` / `CFG_Get$` in `src/sys/config.bas`:

| File | Holds |
|---|---|
| `assets/gamevalues.ini` | Text substitution tokens for `assets/gametext.txt` (names of the emperor, planets, ships). Only text tokens: `tools/bake_speech_dict` and the unused-token check read it with `gametext.txt` |
| `assets/config/economy.ini` | Credits earned per drone downed, boss, stage clear and asteroid event, with the economy maths; fuel and shield prices, the per-dock fuel surcharge and the next jump's fuel need |
| `assets/config/upgrades.ini` | The dock's upgrade table: names, prices per level, effect values per level, and each upgrade's description |
| `assets/config/abilities.ini` | Active ability behaviour: nova charges, radius and boss damage; roll cooldowns, length and speed; the first-purchase hints |

A new file needs an `$EMBED` line in `sss.bas` and a `CFG_Parse$` call next to the others.

**Dock background:** `assets/dock_bg.png`, a 320x240 PNG (the game's resolution; other sizes are scaled to fit), embedded at build time. Replace the file and rebuild to change it. The list sits on a see-through panel over the right two-thirds.
