# HTTP queue (`src/sys/http.bas`)

## What problem it solves

QB64-PE has no built-in async HTTP client, and the game loop can't afford to block on a network round-trip mid-frame. `http.bas` wraps libcurl's multi-interface (non-blocking, handle-based) behind a tiny request queue so game code can fire off a POST or GET and keep rendering; the transfer completes in the background across subsequent frames.

It's used by [`telemetry.bas`](README-telemetry.md) to POST batched gameplay events and score submissions, and by [`lbrd.bas`](README-telemetry.md#leaderboard-lbrdbas) to GET the leaderboard.

## How it works

- QB64-PE's `DECLARE LIBRARY` calls straight into libcurl via a small C shim, `curl_qb64.h`. That header exists because QB64-PE's string marshalling frees temporary buffers as soon as a `DECLARE LIBRARY` call returns — anything curl needs to hold onto for an async transfer (URL, POST body, auth headers) has to be copied into a stable C-side buffer first, or curl reads freed memory on the next frame.
- Linkage to `-lcurl` is triggered by `httpForceLink`, a `Sub` that's never actually called at runtime — its presence with `_OPENCLIENT("TCP:...")` makes QB64-PE set `DEPENDENCY_SOCKETS`, which pulls in curl at link time.
- One `curl_multi` handle drives at most one in-flight `curl_easy` transfer at a time; additional requests wait in a small ring-buffer queue (`HTTP_QUEUE_CAP = 8`). `HTTP_Pump`, called once per frame from the main loop, advances the in-flight transfer and starts the next queued one when it completes.

## Public API

```basic
HTTP_Post url$, key$, body$, tag$   ' enqueue a POST; returns immediately
HTTP_Get  url$, key$, tag$          ' enqueue a GET; returns immediately
HTTP_Pump                            ' drive in-flight I/O; call once per frame
HTTP_Flush secs                      ' blocking drain -- call before exit paths only
```

State you read after a request completes (all `Dim Shared`, declared in `dims.bas`):

```basic
httpEasyH    ' _OFFSET; non-zero while a transfer is in flight
httpQCount   ' pending requests still in the queue
httpLastOK   ' -1 if the most recently completed request succeeded, 0 if it failed
httpLastTag  ' the tag string of the most recently completed request
httpLastBody ' response body of the most recently completed request
```

`key$` is sent as both a Supabase `apikey` header and a `Authorization: Bearer` header — that's Supabase's REST API convention, not a general-purpose auth scheme.

### Example: fire-and-forget POST, checked next frame

```basic
HTTP_Post DB_URL + "/sss_telemetry", DB_KEY, jsonBody$, "telem_batch"
' ... later, once per frame in the main loop ...
HTTP_Pump
If httpLastTag = "telem_batch" And httpEasyH = 0 Then
    If httpLastOK Then
        ' succeeded
    End If
    httpLastTag = ""  ' clear so this branch doesn't re-fire on the next completion
End If
```

`sss.bas`'s main loop already runs `HTTP_Pump` and dispatches on `httpLastTag` for the game's own consumers (leaderboard poll, score/telemetry POST) — see that dispatch block for the canonical pattern before adding a new one.

## Adding a new endpoint

1. Call `HTTP_Post` or `HTTP_Get` with a new, unique `tag$` — tags are how you tell completions apart in the shared `httpLastTag`/`httpLastOK`/`httpLastBody` state.
2. Add a branch in the main loop's `HTTP_Pump` dispatch (in `sss.bas`) that checks for your tag and does something with `httpLastBody` on success.
3. If the response needs structured parsing, add a small hand-rolled parser like `LBRD_Parse` in `lbrd.bas` — there's no general JSON *decoder* in this codebase (`json.bas` only *encodes*), so parsing is linear string scanning tailored to the exact response shape you expect.
4. Test against the local mock server (below) before pointing at a real backend.

## Known limitations and gotchas

- **One transfer in flight at a time.** The queue is FIFO and serializes everything through a single `curl_easy` handle. Fine for this game's request volume; don't assume concurrency.
- **Fixed size limits** in `curl_qb64.h`: POST bodies cap at 128 KB (`QBC_POST_MAX`), response bodies at 32 KB (`QBC_BODY_MAX`), response headers at 8 KB (`QBC_HDR_MAX`). Oversized requests/responses are silently truncated or rejected at the C layer — there's no QB64-side warning.
- **`HTTP_Flush` blocks the calling thread** (up to `secs` seconds via `_Delay` inside a pump loop) and exists only for shutdown paths where you need pending requests to finish before the process exits. Never call it from the main loop.
- **The `_OPENCLIENT` linkage trick is fragile by nature** — if QB64-PE ever changes how it detects `DEPENDENCY_SOCKETS`, `httpForceLink` needs to change with it, even though the Sub itself does nothing at runtime.
- **No retry logic.** A failed request (`httpLastOK = 0`) is just dropped; callers that care about delivery (like telemetry) need their own retry/backoff if that ever becomes a requirement.

## Testing in isolation

`tests/http_queue_test.bas` exercises the whole queue (ordering, non-blocking pumping, GET, overflow, `HTTP_Flush`, and both success and failure responses) against a local mock server, with no real credentials or network access required:

```bash
tools/http_queue_test
```

This builds `tests/http_queue_test.bas`, starts `tools/http_mock_server` (a small Python `http.server`-based mock with canned `/fast`, `/slow/<ms>`, `/fail`, and `/get_ok` endpoints) on a free local port, runs the test binary against it, and tears the mock server down. It's the same thing `.github/scripts/qb64test.sh` runs in CI on all three platforms.
