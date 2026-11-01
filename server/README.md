# Telemetry and leaderboards backend

The game can optionally send anonymous gameplay events and score submissions to a small backend we own: a [Cloudflare Worker](https://developers.cloudflare.com/workers/) backed by a [D1](https://developers.cloudflare.com/d1/) (SQLite) database, in this folder (`server/`). This is entirely off unless you configure it:

1. Create `assets/.env` (gitignored) at the repo root:
   ```
   DB_URL=https://sss-api.<your-account>.workers.dev
   DB_KEY=<the API_KEY you set on the Worker>
   ```
2. Leave it empty or absent to disable network telemetry entirely. The game still writes a local `sss_telemetry.csv`, and no network requests are made.
3. Players are asked for one-time consent in-game before anything is sent; `--no-telem` skips telemetry (and the consent prompt) for a single session.

See [`src/sys/README-telemetry.md`](../src/sys/README-telemetry.md) for the event schema and [`src/sys/README-http.md`](../src/sys/README-http.md) for the underlying HTTP layer.

## Deploying the backend

The Worker serves the three calls the game makes: `POST /sss_telemetry`, `POST /scores` (both need the key), and the public `GET /top_scores`. The schema is in `server/migrations/`. One-time setup, from `server/`:

1. Create a free [Cloudflare account](https://dash.cloudflare.com/sign-up).
2. `npm ci`, then `npx wrangler login`.
3. `npx wrangler d1 create sss` and paste the printed `database_id` into `server/wrangler.toml`.
4. `npm run migrate` to create the tables in the remote database.
5. `npx wrangler secret put API_KEY` and enter a long random string (e.g. `openssl rand -hex 32`). This is the game's `DB_KEY`. It identifies the client, it is not a secret: it is embedded in every build (`strings builds/sss` shows it), so anyone can post with it. The Worker's own checks are what protect the data (see below).
6. `npm run deploy`. Wrangler prints the Worker URL (`https://sss-api.<your-account>.workers.dev`).
7. In the GitHub repo settings, set the Actions secrets `DB_URL` to the Worker URL and `DB_KEY` to the `API_KEY`, then rebuild. CI writes them into `assets/.env`.

Run `npm test` in `server/` to test the Worker locally (Vitest in the Workers runtime with D1 migrations applied); CI runs it too. Later schema changes go in a new `server/migrations/NNNN_*.sql` file, applied with `npm run migrate`.

**Automatic deploys.** Pushes to `master` that change anything under `server/` deploy automatically: CI's "Deploy server" job applies the D1 migrations, then runs `wrangler deploy`, after the server tests pass. It needs two repo Actions secrets: `CLOUDFLARE_API_TOKEN` (Cloudflare dashboard → My Profile → API Tokens → the "Edit Cloudflare Workers" template, plus D1 Edit permission) and `CLOUDFLARE_ACCOUNT_ID`. The manual `npm run migrate` / `npm run deploy` steps above remain for first-time setup and emergencies.

**Local testing.** To run the Worker on your machine with a local D1, from `server/`:

```bash
echo "API_KEY=localkey" > .dev.vars            # the local DB_KEY; .dev.vars is gitignored
npx wrangler d1 migrations apply sss --local
npx wrangler dev --ip 0.0.0.0                  # serves http://localhost:8787
```

Then point the game at it in `assets/.env` with `DB_KEY=localkey` and a `DB_URL` that depends on where the game runs. A native build uses `DB_URL=http://localhost:8787`. A game run with `tools/dev run` uses `DB_URL=http://host.containers.internal:8787`, because inside the container `localhost` is the container, not your machine. `DB_URL` and `DB_KEY` are embedded at build time, so rebuild after editing `assets/.env`.

The free plan allows 100,000 Worker requests and 100,000 D1 rows written per day; past that, requests fail until the 00:00 UTC reset. Cloudflare's [Workers](https://developers.cloudflare.com/workers/platform/limits/) and [D1](https://developers.cloudflare.com/d1/platform/pricing/) limits pages list no inactivity pause.

**What the Worker accepts.** `POST /scores` takes exactly one row per request, a `score` up to 250,000 and a `wave` up to 100 (the derivation is next to `MAX_SCORE` in `server/src/index.ts`; raise it if scoring grows), and a `player_name` that follows the in-game callsign rules: 3 to 32 printable ASCII characters (32-126), `~X` colour tokens included. An optional `difficulty` is a lowercase slug (a letter, then up to 15 of `a-z`, `0-9`, `_`, `-`), not a fixed list, so new difficulty levels need no server change; a row without it is stored as `normal`, which keeps game builds from before #102 working. `GET /top_scores` can return it (`select=player_name,score,difficulty`) and filter to one board with `difficulty=eq.<slug>`; without the filter it ranks every difficulty together. Each client IP may make 10 `POST /scores` and 30 `POST /sss_telemetry` requests a minute (the `[[ratelimits]]` bindings in `server/wrangler.toml`); past that the Worker answers 429. The game sends one of each per run.

**Moderating the leaderboard.** To look at and remove bad rows, from `server/`:

```bash
npx wrangler d1 execute sss --remote --command "SELECT id, player_name, score, wave, created_at FROM scores ORDER BY score DESC LIMIT 20"
npx wrangler d1 execute sss --remote --command "DELETE FROM scores WHERE id IN (123, 124)"
```

`DELETE FROM scores WHERE player_name = '...'` or `WHERE score > ...` work the same way. Run the `SELECT` with the same `WHERE` first to check what it matches.
