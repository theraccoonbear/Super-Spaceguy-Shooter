# Controls

To see the controls in game, open the pause dialog (ESC / Start) and press **C** (the roll button, X by default, on a gamepad), or pick CONTROLS in the title screen's command console.

The tables below show the default bindings. On-screen prompts follow the device you last touched: key names after a key press, the bound pad button (as a coloured badge) after a pad press. Every menu and dialog has a cursor: ↑ / ↓ (or the stick or d-pad) move it and ENTER / pad A picks, and the hotkeys listed below still work.

## Remapping

Settings > **CONTROLS** (ENTER / pad A on that row), or **K** / the nova button (Y by default) in the pause dialog, opens the remap page. It lists every action with its key and its pad button. ↑ / ↓ pick an action, ← / → switch between the KEY and PAD columns, and ENTER / pad A rebinds it: press the new key or button. **RUN PAD SETUP** asks for each pad action in turn, and **RESET TO DEFAULTS** restores both. ESC is always pause and back, and the arrow keys and the stick and d-pad always move, so those can't be rebound; W / A / S / D are the movement keys you can change. Leaving the page saves the bindings in `sss_settings.ini`, with pad bindings stored per controller name.

**First-run pad setup.** When a gamepad the game has no built-in layout for, and no saved bindings for, is connected at the title screen, the pad setup wizard opens on its own: press the button you want for each action. A stick, d-pad or arrow push skips an action (so does waiting 10 seconds), and keyboard ESC cancels. A cancelled setup isn't asked again for that pad; run it from Settings > CONTROLS > RUN PAD SETUP.

## In flight

| Key | Gamepad | Action |
|---|---|---|
| Arrow keys / WASD | Left stick | Move ship |
| Space (hold) | A or B | Fire (both bottom face buttons, so a Nintendo-labeled pad fires from either) |
| E | X | Evasive roll, once bought at the dock |
| Q | Y | Nova pulse, once bought at the dock |
| ESC | Start | Pause / abort-mission dialog: CONFIRM RETREAT, CONTROLS, REMAP CONTROLS, CANCEL. It opens on CANCEL, so ENTER / A resumes. Keyboard hotkeys: Y retreats, C shows the controls, K opens the remap page, N cancels. Pad: the roll button (X) shows the controls, the nova button (Y) opens the remap page, B cancels. ESC / Start closes it |
| TAB | Back / Select | Camera mode on/off. The game freezes while you adjust; pressing it again locks the angle and saves it |
| ↑ / ↓ (camera mode) | Stick up/down | Tilt the camera |
| R (camera mode) | — | Reset to the default chase camera |
| ESC (planet arrival / cutscene) | Start | Return to the title |

## Title and menus

| Key | Gamepad | Action |
|---|---|---|
| P | Start | Start a new game |
| ESC | Back / Select | Open/close the command console |
| A / C / S / L / T / Q / N | B (Cancel only) | Console: About / Controls / Settings / Leaderboard / Tutorial / Quit / Cancel |
| ↑ ↓ then ENTER | Stick up/down then A | Console: move the highlight and pick it |
| ↑ ↓ ← → | Left stick | Navigate and adjust Settings; scroll About; page through Controls |
| ENTER | A | Confirm (Settings callsign and CONTROLS rows, data notice, remap page) |
| ESC | B (or Start) | Back / cancel (Settings, About, Leaderboard, Controls, remap page, data notice) |
| F11 | — | Toggle fullscreen (any screen) |

## Tutorial

The first New Game on a fresh install starts the tutorial instead of stage 1 (an existing settings file counts as having done it). TUTORIAL in the title screen's command console (**T**) replays it any time. The Orientation Unit speaks and shows each line at the bottom of the screen, and outlines the HUD element it is explaining. Nothing advances on a timer: a line ends when it has been spoken or skipped, and each task waits until you have done it.

| Key | Gamepad | Action |
|---|---|---|
| ENTER (tap) | Nova button (Y by default) | Skip the line being spoken |
| N | Roll button (X by default) | Skip to the next lesson |
| ENTER (hold 2 seconds) | Nova button (hold 2 seconds) | File a waiver and leave the tutorial; a meter fills while you hold. Letting go early does nothing |
| ESC | Start | The usual pause dialog; CONFIRM RETREAT leaves the tutorial and counts as skipped |

The tutorial leaves no record (no score, high score or telemetry) and cannot be failed. Finishing, skipping or leaving it saves `tutorial_done=1` in `sss_settings.ini`; delete that line, or the file, to be sent through it again on the next New Game.

## Story screens

| Key | Gamepad | Action |
|---|---|---|
| Space (hold) | A or B (hold) | Fast-forward the narrative crawl |
| Space + ESC | A or B + Start | Skip the crawl |
| Space | A | Continue (intro card, game over) |
| Any key | A / Start | Skip the logo cards |

On the data notice, X is "don't ask again" (S on the keyboard).

**Callsign entry.** On the keyboard, type the name, then ENTER (or SPACE) when done or ESC to skip. On a gamepad it's an arcade letter spinner: up / down spin the character under the cursor (A-Z, 0-9, space, `-`, `.`; hold to repeat), left / right move, A goes to the next character (adding one at the end), B deletes, Y cycles that character's colour, Start is done and Back skips. Both edit the same name, so you can switch device mid-entry.

## Upgrade dock

| Key | Gamepad | Action |
|---|---|---|
| ↑ / ↓ (or W / S) | Stick or d-pad up/down | Pick a row (the list scrolls) |
| ← / → (or A / D) | Stick or d-pad left/right | On REFUEL / SHIELDS: buy less / more (steps of 10% of the tank or shield) |
| ENTER | A | Buy the amount shown, or the next level (on LAUNCH: leave) |
| ESC | B or Start | Leave for the next stage at once |

## Debug

| Key | Action |
|---|---|
| `` ` `` | Toggle the debug HUD overlay. It starts on with `--debug`, but the key works in any build |
