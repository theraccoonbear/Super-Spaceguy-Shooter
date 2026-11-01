# Credits and the upgrade dock

The numbers (prices, levels, credit amounts, fuel margins) live in `assets/config/economy.ini`, `upgrades.ini` and `abilities.ini`, which are the source of truth. The values quoted below were accurate when written; if they differ from the `.ini` files, the files win.

Credits (`$`, shown next to the score) are a second currency, separate from score: spending them never lowers your score or rank. Kills, bosses, stage clears and the asteroid field (near misses, asteroids a nova pulse destroys, and getting through) earn them. After each planet arrival except the last, the **upgrade dock** opens: buy upgrades for the rest of the run, or leave with one press. Credits and upgrades reset on a new game. At the end of a run, win or death, leftover credits become score (1 point per credit by default, `credit_bonus_rate` in `assets/config/economy.ini`), shown as `CREDITS BONUS +N` on the game-over screen or the title after the outro, and counted in your high score and leaderboard score.

## Upgrades

| Upgrade | What it does | Levels |
|---|---|---|
| Laser capacitor | Bigger laser bank (LA) that recharges faster | 3 |
| Twin cannons → spread shot | Two parallel shots per trigger pull, then a three-way spread | 2 |
| Rapid fire | Shorter delay between shots | 2 |
| Shield capacity | Bigger shield (SH) | 3 |
| Shield regen | Shields refill on their own after a few seconds without a hit | 2 |
| Hull armour | Less damage from collisions and asteroids | 2 |
| Nova pulse | **Q** / pad **Y**: clears every enemy shot and blasts ships and asteroids near you; a boss loses a few points. Charges per stage refill at every dock | 3 |
| Thrusters | Faster sideways movement | 2 |
| Evasive roll | **E** / pad **X**: a quick sideways dash (the way you're steering) that nothing can hit; level 2 cools down faster | 2 |
| Tractor beam | Pulls power-ups toward the ship | 2 |
| Fuel tank | Bigger fuel tank (the extra room arrives empty: fill it at REFUEL) | 2 |

## Fuel and shields

The first two dock rows sell supplies by the amount. Nothing else refills them: a planet arrival tops up the laser only, and only losing a ship hands you a full tank and full shields.

- **REFUEL**: fuel at `fuel_price` per unit times the dock's surcharge (`fuel_mult`, see below).
- **SHIELDS**: shield points at a flat `shield_price` each.

The highlighted row shows the amount between ◂ ▸ arrows and its cost (red when you can't afford it, `FULL` when nothing is missing). The amount starts at what your credits fill and goes back there after every purchase, so one ENTER means "fill what I can afford"; ← → change it in steps of 10% of the capacity. Under the list, REFUEL shows the price per unit and `NEXT JUMP NEEDS 55 FU`, an honest estimate from the next leg's stages in `assets/sequence.txt`: their expected seconds (`fuel_kill_secs`, `fuel_asteroid_secs` in `economy.ini`, each boss fight's `secs=`) x the real burn in play (`fuel_burn`) x a margin (`fuel_margin`). Some legs need more than the base tank holds; the line then alternates with `TANK 100: UPGRADE TANK` and the need tick sits past the end of the FU bar. You are only stranded when your credits can't fill the tank to what it can hold of the leg: flying the rest dry is allowed; SHIELDS shows the price and the result (`SHIELD 40 > 100`).

**Fuel prices only go up.** After chapter 1 the Emperor blockades the refinery world, and every dock after that charges more: `fuel_mult` in `economy.ini` is 1.0, 1.4, 1.8, 2.2, 2.6 for docks 1 to 5, and it never eases. REFUEL shows the rise next to the price (`$2.80/U  ▲+40%`), and each dock reads out a news line about the blockade on arrival (shown as a ticker under the list; the `dock_news1`..`dock_news5` blocks in `assets/gametext.txt`).

**Stranded.** If you try to leave (LAUNCH or back) when the fuel in the tank plus all the fuel your credits can buy won't reach the next planet, the dock asks **ABANDON RUN AND EKE OUT A LIVING HERE?** with one answer, **[ YES ]**: back and the arrows do nothing, so spend what you can first. YES ends the run: leftover credits become score as on a death, a short crawl plays (`stranded_final` in `gametext.txt`), and the game-over card reads **STRANDED**. God mode is never stranded. `--scene dock2 --credits 0 --fuel 10` shows it.

A status box at the bottom left shows the ship's shields (SH), laser (LA) and fuel (FU) as absolute values over bars: a highlighted supply row adds a see-through segment for the amount being bought, and the fuel bar has a white tick at what the next jump needs. In the dock, the two lines under the list say what the highlighted upgrade does and exactly what its next level changes (for example `MAX 100>125, REGEN +20%`), or `MAXED`. The same list is in game on the Controls screen's **SHIP SYSTEMS** pages (pages 3 and 4: ← → or the stick). The first launch after buying the roll or the nova shows its key (`NOVA READY - Q / PAD Y`) for a few seconds. The descriptions sit next to each upgrade in `assets/config/upgrades.ini` (`upgdesc_*`); the hints are in `assets/config/abilities.ini` (`hint_*`).

Tuning lives in purpose-named config files under `assets/config/` (see [Config files](config-files.md)): credit amounts, the economy maths and the fuel and shield prices in `economy.ini`, prices, levels, effects and descriptions in `upgrades.ini`, and nova / roll behaviour in `abilities.ini`. `--scene dockN` opens the dock after stage N, `--credits N` starts with N credits and `--fuel N` with N fuel, to try it out.
