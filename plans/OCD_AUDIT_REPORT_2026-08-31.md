# WakeGuard — Full-Stack Forensic Audit Report & Remediation Plan

**Audit date:** 2026-08-31
**Audited branch:** `main` (HEAD `b06747d`)
**Scope:** Python core (`main.py`, `yolo/*`), Flutter app (`flutter_app/lib`, platform shells), Supabase migrations, scripts, tests, config surface, git hygiene, documentation.
**Method:** Read every source file line-by-line; executed the test suite, OpenCV rotation-decomposition verification, dependency inspection, git archaeology, and cross-checked the unmerged `fix/ocd-audit-2026-08-28` branch.
**Companion vault note:** `notes/OCD Codebase Audit - 2026-08-31.md`

---

# Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Project State & Inventory](#2-project-state--inventory)
3. [Findings Register](#3-findings-register)
   - 3.1 Security (S)
   - 3.2 Functional Breakage (F)
   - 3.3 Data Integrity (D)
   - 3.4 Dependencies & Build (B)
   - 3.5 Architecture & Robustness (A)
   - 3.6 Test Suite (T)
   - 3.7 Python HUD Visual (V)
   - 3.8 Flutter UI/UX (U)
   - 3.9 Flutter Platform Config (P)
   - 3.10 Documentation & README Drift (M)
   - 3.11 Repository & Git Hygiene (R)
4. [Comprehensive Remediation Plan](#4-comprehensive-remediation-plan)
   - 4.0 Operation 0 — Merge the Existing Fix Pack
   - 4.1 P0 — Security (sprint 1)
   - 4.2 P1 — Core Functionality (sprint 2)
   - 4.3 P2 — Data Integrity (sprint 3)
   - 4.4 P3 — Dependencies & Tooling (sprint 4)
   - 4.5 P4 — Robustness & Dead Code (sprint 5)
   - 4.6 P5 — UI / UX / Visual (sprint 6)
   - 4.7 P6 — Documentation & Hygiene (sprint 7)
5. [Fix Matrix (issue → fix → files → verification)](#5-fix-matrix)
6. [Acceptance Checklist](#6-acceptance-checklist)
7. [Appendix](#7-appendix)
   - A. Verifiable Experiments Performed
   - B. Test Suite Output (condensed)
   - C. Findings Convergence with `fix/ocd-audit-2026-08-28`
   - D. Unused Imports & Dead Symbols (exhaustive)
   - E. Hardcoded Color Inventory

---

# 1. Executive Summary

The project is a genuinely well-architected driver-fatigue detection system: a three-tier
capture → inference → display pipeline decoupled by a drop-old `LatestValue` handoff slot, a
hysteresis-latched, priority-ordered alert state machine, a loopback-gated pairing service with
rate limiting and timing-safe digest comparison, and a generation-counter SSE reconnect protocol.
The *design layer* is not the problem.

The problem is that a meaningful share of the shipped surface is **unfinished theatre**:

- A camera feed exposed to any local webpage via `Access-Control-Allow-Origin: *` combined with
  default-allow authentication.
- A token-refresh endpoint that the client calls and the server never routes (silent 404 chain).
- A mobile app whose STOP button 404s, whose settings screen is a static mockup, and whose
  post-trip safety report is partly fabricated from `math.Random(42)` and hardcoded timestamps.
- A replay/eval harness that can never terminate because the camera thread re-opens video files
  at EOF and headless mode has no exit route.
- A Supabase device-registration path that fails on a Postgres type error (`'now()'` literal) and
  a second path that fails on missing imports (`json`, `verify_jwt`, `API_PREFIX`).
- A `requirements.txt` that lists two mutually clobbering OpenCV packages, plus a venv that has
  never been synced to it (`supabase` and `PyJWT` absent → 2 test failures).
- A Flutter app running two competing design systems, declaring fonts it never ships, and
  rendering in Roboto while its mockups promise Inter and JetBrains Mono.
- Android manifests with no `INTERNET` permission, iOS with no ATS exception, and release builds
  signed with the debug key.

**Tally:** 8 CRITICAL · 13 HIGH · ~25 MEDIUM · ~40 LOW/NIT.
**Tests:** 144 collected, 141 passed, 3 failed (2 environment, 1 flaky-by-construction test/handler race).

**Critical context:** an equivalent diagnosis already exists on `fix/ocd-audit-2026-08-28`
(33 files, +1769/−995, 360-line plan) and has been **sitting unmerged for three days**. The
primary operational sin is that the repository is carrying its own cure, unabsorbed.
Operation 0 in the remediation plan is to merge that work; everything else in this document is
the residual.

---

# 2. Project State & Inventory

## 2.1 Repository

| Metric | Value |
|---|---|
| Git repo | yes; working tree **clean** at HEAD `b06747d` |
| Identity | `arv1903 <marvin06ar@gmail.com>` — personal, compliant with AGENTS.md guardrails |
| `.git` size | 10.4 MB |
| Working tree | ~3,017 MB (overwhelmingly `venv/`) |
| Branches | `main`, `feature/hardening`, `backup-before-freebuff-cleanup`, `fix/ocd-audit-2026-08-28` (unmerged) |
| Secrets tracked? | No — `.env`, `settings.json`, `profiles/`, `logs/`, `notes/` gitignored ✓ |
| Committed binaries | `best.pt`, `face_landmarker.task`, `alert.mp3` (no Git LFS) |

## 2.2 Code Surfaces

| Surface | Files | Lines (approx.) |
|---|---|---|
| Python application (`main.py` + `yolo/*.py`) | 29 | ~6,010 |
| Python tests | 21 | ~1,870 |
| Scripts (`scripts/`) | 5 | ~495 |
| SQL migrations (`supabase/migrations/`) | 5 | ~294 |
| Flutter `lib/` | 18 | ~10,000 |
| Flutter tests | 4 | ~360 |
| Platform shells (android/ios/windows/linux/macos/web) | ~80 | ~4,500 |
| Total tracked | 225 | ~80,000 |

## 2.3 Test Suite (executed during this audit)

```
144 tests collected
141 passed · 3 failed · 49.41s
```

| Failure | Cause |
|---|---|
| `tests/test_db.py::TestVerifyJwt::test_verifies_valid_token` | `ModuleNotFoundError: No module named 'jwt'` — venv lacks PyJWT despite `requirements.txt:8` |
| `tests/test_db.py::TestVerifyJwt::test_rejects_expired_token` | same |
| `tests/test_api.py::test_pairing_revoke_requires_a_companion_token` | `ConnectionAbortedError [WinError 10053]` — server aborts the socket instead of the expected `400`; teardown race with the 2 s client read |

## 2.4 Environment Notes (this machine)

- `cv2 == 5.0.0.93` — **both** `opencv-python` and `opencv-contrib-python` installed (a documented pip conflict)
- `numpy == 2.5.1`, `mediapipe == 1.0.0`, `ultralytics == 8.4.115`, `pillow == 12.3.0` (transitive)
- `supabase` and `PyJWT` **not installed** — the venv does not match `requirements.txt`
- `.env` contains **real** Telegram + Supabase service-role credentials (untracked — well done — but still occupying a P0 rotation finding)

## 2.5 Architecture Snapshot (what is genuinely good)

- `yolo/latest.py` — `LatestValue`: drop-old thread handoff with a `Condition` (no spin-polling; ~8% CPU saved vs `sleep(0.005)`).
- `main.py` display loop — single-threaded state machine; API worker threads only *enqueue* commands.
- Accumulator timers with freeze-on-face-loss (`UpdateTimer(..., Freeze=TimerFrozen)`) + `AlertLatch` hysteresis.
- `yolo/pairing.py` — `secrets`-based codes, SHA-256 digests compared with `hmac.compare_digest`, per-window failure lockout, loopback-gated code reveal with proxy-header paranoia (`api.py:237-242`).
- SSE reconnection with `server_id` + sequence generation recovery (client + server contract verified aligned).
- MediaPipe 0.10.x / 1.0+ landmark-shape normalization — genuinely cross-version safe.
- Test fixtures that spin up real HTTP servers on ephemeral ports — the Python suite is *substantially* better than average.
---

# 3. Findings Register

Every finding: **ID — Severity** · Location · Evidence · Impact · Fix · Verified.

## 3.1 Security (S)

### S-1 — CRITICAL — CORS wildcard + optional auth exposes the camera to any local web page
- **Location:** `yolo/api.py:106` (`Access-Control-Allow-Origin: *` on every response); `yolo/api.py:73-74` (`_authorized()` returns `True` when no token is configured).
- **Evidence:**
  ```python
  self.send_header("Access-Control-Allow-Origin", "*")
  # 1. No auth configured — allow everything
  if not expected:
      return True
  ```
- **Impact:** `python main.py --api` (the README quick-start, no `--api-token`) lets **any website open on the same machine** make cross-origin calls to `127.0.0.1:8765` and read `/frame.jpg`, `/status`, `/events`, and POST `session/stop`, `alarm/mute`, `calibration/start`, `settings`.
- **Fix:** (a) default-deny (require a token unless explicitly disabled with a dedicated flag); (b) replace `*` with only the loopback origin, or drop CORS headers entirely — the Flutter desktop app is native and does not need them; (c) reject requests bearing a browser `Origin` header that is not `null`/loopback; (d) keep LAN binding gated on `--api-token` (already enforced at `api.py:625-626`).

### S-2 — CRITICAL — `/api/v1/auth/refresh` does not exist (the refresh chain is a silent 404)
- **Location:** `flutter_app/lib/services/auth_service.dart:140` (client POST); `yolo/api.py:511-567` (route table: register/login/device/pairing/commands only); `yolo/db.py:218` (`auth_refresh` implemented, never routed); `flutter_app/lib/services/connection_service.dart:181-191`.
- **Evidence:** client calls `$backendUrl/api/v1/auth/refresh`; server returns 404; `_attemptRefresh()` in `connection_service.dart` treats a 404 as refresh failure, **and** would also replace the paired-device token with a Supabase JWT (`:185`) and invent a 1-hour expiry (`:187`) if it ever succeeded. Expiry bookkeeping everywhere is a guess (`:95,106,123`).
- **Fix:** wire `POST /api/v1/auth/refresh → db.auth_refresh(refresh_token)` with an auth guard, **or** delete the client refresh path and `ConnectionService._scheduleRefresh`. Never both half-present.

### S-3 — HIGH — Exception text leaked into HTTP responses
- **Location:** `yolo/api.py:321,350,372,421` — `self._error(500, f"device registration failed: {exc}")` and siblings.
- **Evidence:** `_handle_device_register`, `_handle_device_heartbeat`, `_handle_device_discover`, `_handle_auth_pair` all interpolate `exc` into the body. AGENTS.md: "Error messages must not leak sensitive data."
- **Fix:** log the exception server-side; respond with a static message (optionally a stable error code).

### S-4 — HIGH — Debug instrumentation left in production code
- **Location:** `yolo/db.py:190-197` (`auth_register`): prints `exception type:`, iterates and prints every `exc.args[i]`, then `traceback.print_exc()` on **every** registration failure.
- **Impact:** noisy, can echo sensitive provider/database detail; a `# debug` block living in a library function.
- **Fix:** replace with a single `logging.debug`/`print` of the exception type at most; remove the args loop.

### S-5 — HIGH — JWT verification trusts the header's `alg`
- **Location:** `yolo/db.py:135-156` — `alg = header.get("alg", "")` (from the *unverified* header) is passed as `algorithms=[alg]` to `jwt.decode`.
- **Impact:** an alg-confusion pattern. Modern PyJWT's strict key/algorithm matching largely neutralizes it, but a pinned allow-list (`["ES256","RS256"]`) is the correct posture. Also: the JWKS cache (`:77-113`) has no lock around refetch (benign duplicate fetches, still a smell).
- **Fix:** reject any token whose `alg` is not in `{"ES256","RS256"}`; add a `threading.Lock` around JWKS refetch.

### S-6 — MEDIUM — Semantic strength of pairing codes is context-dependent
- **Location:** `yolo/pairing.py:58-61` — `secrets.token_hex(4)` = 32 bits.
- **Impact:** safe **only** because (a) `/pairing/exchange` is rate-limited (5 failures → 30 s lockout, `pairing.py:101-103`) and (b) code reveal via `GET /pairing` is loopback-only (`api.py:237-242`). Both properties are *context*, not code — if either regresses, a LAN brute-force becomes feasible.
- **Fix:** document the invariant in `PairingManager.__init__`; consider raising to 6 hex chars (`token_hex(6)` = 48 bits) at zero UX cost.

## 3.2 Functional Breakage (F)

### F-1 — CRITICAL — Supabase device registration/heartbeat always 500s
- **Location:** `yolo/api.py:314` (`"last_seen_at": "now()"` in insert) and `:341` (same in update), against `devices.last_seen_at TIMESTAMPTZ` (`supabase/migrations/001_initial_schema.sql:24`).
- **Evidence:** PostgREST sends `"now()"` as a **string literal**; Postgres cannot cast `'now()'` to `timestamptz` → `22P02` → every `POST /device/register` and `/device/heartbeat` returns 500 → Flutter device discovery can never list a live device. *(This is the correct interpretation: clients cannot evaluate SQL functions in insert values.)*
- **Fix:** `"last_seen_at": datetime.now(timezone.utc).isoformat()` in both places; add a route test that inserts a real row.

### F-2 — CRITICAL — In-process heartbeat thread is a NameError sandwich
- **Location:** `main.py:335` (`json.load(_df)` — no `import json` in main.py), `main.py:341` (`verify_jwt(_device_jwt)` — imported only in `yolo/api.py`), `main.py:386` (`API_PREFIX` — defined in `yolo/api.py`).
- **Impact:** whenever a cached `profiles/device.json` exists with a JWT, the load swallows the exception (`except Exception`) and prints *"device info load failed: name 'json' is not defined"*; the heartbeat thread can never run.
- **Fix:** import `json`, `verify_jwt`, `API_PREFIX` (or better, move the whole heartbeat into the API module), `_heartbeat_stop = None` initialised at the top of `main()` instead of the `"_heartbeat_stop" in dir()` check at `:842`.
- **Status on branch:** fixed (imports added).

### F-3 — CRITICAL — Mobile STOP is a 404 wrapped in fire-and-forget
- **Location:** `flutter_app/lib/screens/mobile/mobile_live_monitor_screen.dart:484`; `monitoring_client.dart:529`; `yolo/api.py:580`.
- **Evidence:** `sendCommand('stop_trip')` → client builds `Uri.parse(base + 'stop_trip')` = `http://host/stop_trip` → `command_paths.get('stop_trip')` → `None` → 404 → unawaited + uncaught. Desktop uses `/api/v1/session/stop` (`app_shell.dart:132`). A mobile session can never be ended.
- **Fix:** pass the full path `/api/v1/session/stop`; await and surface errors.

### F-4 — CRITICAL — `replay_eval.py` can never complete
- **Location:** `yolo/pipeline.py:85-94` (camera re-opens the video file at EOF every 30 failures, backoff to 2 s, `failures` reset — infinite replay); `main.py` headless loop has no exit (only the `q` key, absent in `--headless`).
- **Impact:** `scripts/replay_eval.py:31` runs `main.py --source <video> --headless` with `check=True` and blocks forever. The README's "headless replay … precision/recall/F₁" workflow cannot run.
- **Fix:** (a) in `CameraThread`, for file sources (non-integer `source`) treat EOF as terminal — break the loop and let `read()` return `False` forever; (b) add `--max-seconds` to `main.py` to bound headless runs; (c) exit headless mode at EOF of a file source.

### F-5 — CRITICAL — Flutter mobile post-trip screen fabricates data
- **Location:** `mobile_post_trip_screen.dart:464-472` (`math.Random(42)` "ATTENTION TELEMETRY"), `:519-553` (hardcoded `_IncidentLog`), `:432-435` (hardcoded x-labels `0h/1h/2h/END`), `:140-148` (indefinitely-animating decorative `CircularProgressIndicator`), `:410` (meaningless `'LIVE > END'` chrome).
- **Evidence:** the real series is one `fetchSessionTelemetry` call away (`trip_log_screen.dart:641-673` does it on desktop); the backend genuinely returns `alerts_by_type` + `alert_times` (`summary.py:60-62`) that no screen reads.
- **Fix:** replace the random chart with real telemetry; replace the incident log with `alerts_by_type`/`alert_times`; drive axis labels from actual duration; pass `sessionStartTime` through `mobile_app_shell.dart:219`.

### F-6 — HIGH — Mobile settings screen is a static mockup
- **Location:** `mobile_settings_screen.dart:35-37` (`_attentionSensitivity=85`, `_drowsyDetection=2`, `_perclosTolerance=12`), `:263-284` (sliders update local state only, never `sendCommand('/api/v1/settings', …)`), `:299-318` (module toggles local-only, initial values hardcoded `true/true/false` vs backend `SessionLoggingEnabled=True`), `:201` (hardcoded profile `'Standard Night Drive'` vs `client.selectedPreset`), `:219` & `:377` (`onTap: () {}` for RECALIBRATION and LOGOUT — `authService.logout()` exists at `auth_service.dart:172` and is never invoked anywhere), `:325` (fallback email `'user@example.com'` displayed as "AUTHENTICATED").
- **Fix:** wire the sliders/toggles to the real `/api/v1/settings` surface (it accepts `ear_threshold`, `perclos_threshold`, `pitch_threshold`, `yaw_threshold`, `roll_threshold`, `alarm_enabled`, `telegram_enabled`, `logging_enabled`, `night_mode`); hydrate initial values from `client`; implement logout; show real profile/email.

### F-7 — HIGH — Desktop session state can desync from the backend
- **Location:** `app_shell.dart:111-167` (`_isSessionActive` tracked only from local command round-trips; never reads `snapshot.tripActive`); contrast `mobile_app_shell.dart:48-62` (derives from `snap.tripActive`).
- **Impact:** if the session ends from the mobile app, from a crash, or via API, the desktop shell keeps rendering the active layout (END SESSION, Live Monitor tab) indefinitely.
- **Fix:** derive `_isSessionActive` from the latest snapshot; keep local round-trip state only as an optimistic overlay.

### F-8 — HIGH — Mobile live monitor shows fake telemetry
- **Location:** `mobile_live_monitor_screen.dart:466-471` (hardcoded `'30.0'` FPS with `'LOCK'` badge while `snap.fps` is available and displayed correctly in the HUD at `:218`); `:459-462` (SESSION T+ — `_formatDuration()` at `:42-50` always returns `00:00:00` because `sessionStartTime` is passed `null` by `mobile_app_shell.dart:219`).
- **Fix:** read `snap.fps`; pass and render the real session start time.

## 3.3 Data Integrity (D)

### D-1 — HIGH — One column, three meanings: `avg_perclos`
- **Locations:** `yolo/db_sync.py:325` (`"avg_perclos": round(p_max, 4)` — stores the **max**), `yolo/summary.py:94-95` (`"perclos_max": sess.get("avg_perclos")` — recycles it as max), `scripts/migrate_to_supabase.py:89` (`"avg_perclos": round(avg_perclos, 3)` — stores the **mean**).
- **Impact:** the `sessions.avg_perclos` column in Supabase is, without provenance, sometimes a maximum and sometimes a mean. Any downstream query that treats it as `avg` is wrong for live sessions.
- **Fix:** rename the column (`max_perclos`) or make all three writers compute the same value; update `summary.py` to read a `max_perclos` field; migration `00x` to backfill.

### D-2 — HIGH — `JsonlTailReader` session stats never reset across trips
- **Locations:** `yolo/db_sync.py:50-54` (accumulators), `:87-94` (`bind_session`/`unbind_session` clear neither).
- **Impact:** trip N's summary is blended with trips 1..N-1 (`_compute_session_stats` at `:300-329`).
- **Fix:** reset `_stats_*` in `bind_session` (or on `session_start` event).

### D-3 — HIGH — Stats read across a lock boundary (possible display-thread crash)
- **Location:** `yolo/db_sync.py:296-298` (`_flush_pending` calls `_compute_session_stats` **after** releasing the lock), `:205-219` (tail thread appends to the same lists without the lock).
- **Impact:** `sum()`/`min()` over a concurrently-appending list can raise `RuntimeError`; because `unbind_session` is called from the display thread (`main.py:451`) with no surrounding `try`, the entire process can die on a rare race.
- **Fix:** hold the lock (or a dedicated stats lock) during `_compute_session_stats`; snapshot lists under the lock.

### D-4 — HIGH — Failed DB inserts are requeued forever (unbounded growth)
- **Location:** `yolo/db_sync.py:294-295`.
- **Impact:** with the `telemetry.session_id → sessions.id` FK (`001:56`), any orphaned session (e.g., the session row insert failed once) permanently re-queues the same failing batch every 5 s forever.
- **Fix:** cap requeues (e.g., 3 attempts then drop + log, or dead-letter to SQLite); at minimum bound `_pending` size.

### D-5 — MEDIUM — `BuildSummary`/history/telemetry crash on one malformed JSONL line
- **Locations:** `yolo/summary.py:33` (`ev["type"]`), `:165` (`json.loads`), `yolo/eval.py:30` (`ev["type"]`); only `FileNotFoundError` is caught (`summary.py:41`).
- **Impact:** one truncated/garbage line → `KeyError`/`JSONDecodeError` → API 500, and `SessionLogger` can legitimately produce a partial line via its StringIO fallback after a disk error (`session_log.py:22-26`).
- **Fix:** use `.get("type")`, wrap per-line `json.loads` in try/except, skip malformed lines.

### D-6 — LOW — `WriteQueue._drain_sqlite` deletes corrupted rows
- **Location:** `yolo/db.py:312-318` — a row whose `rows_json` fails to parse is still appended to the delete list.
- **Fix:** only delete rows that were successfully drained; keep the corrupt row for inspection.

## 3.4 Dependencies & Build (B)

### B-1 — CRITICAL — Two OpenCV packages, and a 4.x/5.x API schism
- **Location:** `requirements.txt:3-4` (`opencv-python>=5.0.0` **and** `opencv-contrib-python>=4.13.0`).
- **Evidence:** both installed in the venv (5.0.0.93 each — same version, so currently benign). `yolo/head_pose.py:74` does `euler_angles, _, _, _, _, _ = cv2.RQDecomp3x3(rmat)` — a **six-way** unpack, which only exists on OpenCV 5 (verified empirically: OpenCV 5.0.0 returns 6 values). If `opencv-contrib-python 4.13` ever wins the DLL battle, `RQDecomp3x3` returns 3 values → `ValueError` on every frame → `InferenceThread` catch-all (`pipeline.py:154-161`) swallows it → **no results ever publish; pose/EAR/microsleep column silently dies**.
- **Fix:** keep exactly one (recommend `opencv-contrib-python>=5.0.0`); or make the unpack tolerant (`(euler, *_)` works on both). *(The unmerged branch drops `opencv-python` and pins contrib; still keep the version floor at 5.)*

### B-2 — CRITICAL — venv desynced from `requirements.txt`
- **Evidence:** `pip list` shows **no** `supabase` and **no** `PyJWT` although `requirements.txt:7-8` require them → the two JWT test failures; backend `get_db()` raises if `SUPABASE_URL` is set without the package installed.
- **Fix:** `pip install -r requirements-dev.txt` after B-1; add a CI step or a `pip check`/import gate in tests.

### B-3 — HIGH — `numpy` floor contradicts the previous audit's pin
- **Location:** `requirements.txt:2` (`numpy>=2.4.0`) vs branch `fix/ocd-audit-2026-08-28:requirements.txt` (`numpy>=1.26,<2`, comment: "numpy 2.x breaks mediapipe wheels").
- **Evidence:** this machine runs numpy 2.5.1 + mediapipe 1.0.0 and tests pass — one of the two documents is wrong. MediaPipe wheel compatibility must be verified on a clean install, then the floor fixed once.
- **Fix:** verify on a fresh venv; pin one exact resolution; never leave two contradictory pins in history.

### B-4 — MEDIUM — `Pillow` is a direct import but only a transitive dependency
- **Location:** `yolo/hud.py:10` imports `PIL`; `requirements.txt` does not list Pillow (present only via ultralytics).
- **Fix:** add `Pillow>=10` explicitly.

### B-5 — MEDIUM — Flutter SDK constraint renders the floor decorative
- **Location:** `pubspec.yaml:8` `sdk: ">=3.3.0 <4.0.0"` / `flutter: ">=3.27.0"` vs `pubspec.lock:344-346` resolved on `dart >=3.11`, `flutter >=3.38`. Different transitive sets for the same declared contract.
- **Fix:** raise the floor to the actually-tested resolution, or remove the fiction of a floor.

### B-6 — LOW — `SUPABASE_ANON_KEY` documented in `.env.example` but used by zero code
- **Location:** `.env.example:9`; grep across `yolo/` finds no reader.
- **Fix:** remove from the template to prevent future misuse.

## 3.5 Architecture & Robustness (A)

### A-1 — HIGH — Runtime settings silently no-op on objects constructed at startup
- **Locations:** `main.py:200-206` (constructed once with config values): `DrowsyEMA(alpha=DrowsyEmaAlpha)`, `PerclosTracker(window_seconds=PerclosWindowSeconds)`, `BlinkMonitor(...)`, three `AlertLatch(clear_seconds=ClearGraceSeconds)`; `main.py:152-153` (`InferenceThread(pose_every_n=..., yolo_every_n=...)`); `main.py:219` (`FramePeriod`).
- **Impact:** `update_settings` can change module globals (`main.py:501-503`) but these captured values never move. Changing `PerclosWindowSeconds`, `DrowsyEmaAlpha`, `ClearGraceSeconds`, `EarMinBlinkSeconds`, `YoloEveryN` via `/api/v1/settings` is accepted, reported "updated", and **does nothing**.
- **Fix:** (a) expose only knobs that are honored, or (b) add `configure()` to each tracker/latch (BlinkMonitor already has one) and call it in the `update_settings` handler.

### A-2 — HIGH — Title/visibility bugs in `main.py` housekeeping
- `main.py:538-540` — `main._infer_version` stored as an attribute of the function object. Fragile; prevents clean `main()` re-entry.
- `main.py:842-843` — `if "_heartbeat_stop" in dir():` — a reflective existence check for a local variable.
- `main.py:804` — snapshot filename `snap_{int(time.time())}.jpg` collides on a second press within the same second; silently overwrites.
- `main.py:552-554` — only downscales when `w > FrameWidth`; smaller cameras leave the panel misaligned for arbitrary widths.
- `main.py:122-125` — `--api` silently rewrites `--headless`; printing an "[info]" instead of failing fast. Acceptable, but the user is told after the fact.

### A-3 — MEDIUM — 30 Hz `notify_all()` thundering herd
- **Locations:** `yolo/monitoring.py:121`, `yolo/api.py:735`; both wake *all* waiters on every publish (up to 30/s), including MJPEG clients whose predicate will be false.
- **Fix:** batched/epoch-based signaling or a `notify_one`-with-flag scheme; at minimum coalesce publishes to ~DisplayFps.

### A-4 — MEDIUM — Per-frame JPEG encoding even with zero clients
- **Location:** `yolo/api.py:725-735` (`publish_frame` encodes every frame, called from `main.py:758` on the display thread). ~3–6 ms of `cv2.imencode` per frame regardless of whether `/frame.jpg` or `/video.mjpg` has a consumer.
- **Fix:** encode lazily on demand, keep last JPEG, or track an active-client flag.

### A-5 — MEDIUM — Module-level mutable state and caches
- `yolo/telegram.py:22-31` — module-global queue/cache; `TriggerTelegramPhoto` comment says "drop oldest" but `put_nowait` drops the **newest** (`:186`).
- `yolo/hud.py:46,64,83` — `_font_cache`, `_panel_cache`, `_vignette_cache` with whole-cache `clear()` on size overflow (`:77-78`, `:103-104`) → resolution flicker incinerates the cache and forces a repaint.
- `yolo/alarm.py:12-13` — `_IsPlayingAlarm`/`_IsMuted` module globals; acceptable single-process, but the `SetAlarmMuted` non-Windows branch (`:34-35`) has a mirrored flag-clearing branch that must stay in sync.

### A-6 — MEDIUM — CWD-relative asset paths
- **Locations:** `yolo/diagnostics.py:11-14`, `yolo/detector.py:14,26`, `yolo/alarm.py:17-24` (mitigated for alarm), `main.py:141-142`.
- **Impact:** run from a different working directory: models fail to load while diagnostics pass; `alert.mp3` silently missing.
- **Fix:** anchor to `Path(__file__).resolve().parent.parent`.

### A-7 — LOW — Camera thread file-source EOF loops forever
- **Location:** `yolo/pipeline.py:85-94` (see F-4 for the full closure). Also `CameraThread.stop()` joins 2 s while the thread may be in a 2 s backoff wait, then `self._cap.release()` races the worker thread — a potential crash on shutdown.
- **Fix:** EOF-terminal for file sources; add a `join(timeout=...)+release` in a finally inside the thread itself.

### A-8 — LOW — `ComputeHeadPose` has no distortion model and no outlier guard
- **Locations:** `yolo/head_pose.py:62` (`dist_coeffs = zeros`); `calibration.py:78-87` (raw mean, no trimming).
- **Fix:** document the no-lens-distortion assumption; consider MAD-based trimming of calibration samples.

### A-9 — LOW — `summary.py:82` re-imports `json as _json` inside a function; `session_log.py:37` parameter `session_id` unused; `perclos.py:26` frame-count window vs wall-clock "60 s at 30 Hz" claim; `drawing.py:56` copies the full frame for a label band; `score.py` snake_case vs the codebase's PascalCase convention.

## 3.6 Test Suite (T)

### T-1 — HIGH — Three-way coverage vacuum for services
- No tests at all for: `ConnectionService` (pairing, refresh scheduling, persistence), `AuthService`, `DeviceDiscoveryService`, `LocalBackendProcess`, the entire mobile flow, `AppShell` navigation, session start/stop in the shell.
- `test/app_shell_widget_test.dart` — misnamed; never pumps `AppShell`; two tests assert a local closure calls itself (`:33-49`). The two meaningful tests (preset round-trip `:60-97`, calibration progress `:99-126`) are good.
- `test/widget_test.dart` — gutted default counter test, an empty `main()`.

### T-2 — MEDIUM — Most algorithmic Flutter code is untested
- `monitoring_client_test.dart` (63 lines) covers URL normalization + initial state only. The MJPEG multipart parser (`monitoring_client.dart:262-346`), snapshot smoother/hysteresis (`:17-130`), `_apply` server-restart recovery (`:400-410`), pairing exchange, and `forgetDevice` have zero coverage.

### T-3 — MEDIUM — int/double fragility asymmetrically guarded
- Snapshot parsing handles int-as-double (`monitoring_snapshot_test.dart:95-106`), but history rows use `as double?` on values Python `round()` emits as JSON ints (`trip_log_screen.dart:45,248,448`; `home_screen.dart:669`) — a `TypeError` swallowed by `fetchTripHistory`'s `catch (_) { return []; }` (`monitoring_client.dart:495`) renders as "No trip history yet".

### T-4 — MEDIUM — Flaky-by-construction API test
- `test_api.py:111-128` expects HTTPError 400/401 but the handler's teardown races the client's 2 s read → `ConnectionAbortedError`. Either the server's error path for the master-token revoke case is wrong, or the test timeout is too aggressive. Watch and fix whichever it is; a client receiving a *reset* instead of a *400* is a real contract violation.

### T-5 — NIT — Python unit tests are strong overall
- Real servers on ephemeral ports, real `MonitoringStore` semantics, MediaPipe shape normalization exercised. Keep the bar.

---

*(Parts 3.7—3.11 and the remediation plan continue in Part 3.)*
## 3.7 Python HUD Visual (V)

### V-1 — HIGH — HUD FPS bar is mathematically capped at 50%
- **Location:** `yolo/hud.py:182` — `min(state.fps / 60.0, 1.0)`; `config.py:174` — `DisplayFps = 30`.
- **Impact:** the FPS bar is half-full in *perfect health*. In headless/API mode `draw_fps` stays `0.0` (`main.py:716,751`), so the bar reads empty even at full rate.

### V-2 — MEDIUM — Gauge center is 19.5 px off the panel's optical center
- **Location:** `yolo/hud.py:150` — gauge `cx = W - panel_w + 118`; panel half-width = `275/2 = 137.5`.
- **Impact:** for a 275 px panel the gauge is 19.5 px left of center. The "ATTENTION" semicircle sits off-balance under the panel title — invisible to most, unbearable to you.

### V-3 — MEDIUM — Asymmetric panel gutters
- **Location:** `yolo/hud.py:171,186` — content starts at `+20` left but closes at `−28` right (`W - 28`). Sparkline and value bars inherit the lopsidedness.

### V-4 — MEDIUM — Every HUD color is a hardcoded literal
- **Locations:** `yolo/hud.py:73` (panel `(18,18,24,220)`), `:74` (title `(200,200,210)`), `:138` (canvas `(10,10,14)`), `:152-153` (Material green/amber/red), `:155` (track `(60,60,70)`), `:176` (spark `(100,200,255)`), `:183,187,190` (bar labels/fills), `:197` (banner), `:207` (FACE LOST), `:218` (ring).
- **Fix:** centralize into a `HudColors` token set in `config.py` (or a dedicated `hud_theme.py`) so `NightMode` and brand styling can touch them.

### V-5 — MEDIUM — `NightMode` dims the overlay but not the video
- **Location:** `yolo/hud.py:220-228` — halves overlay RGB channels only. The camera feed stays full-brightness and deltas the panel by an arbitrary 50%.

### V-6 — LOW — Font fallback collapse + hardcoded pulse constants
- `hud.py:35-43` — falls back to a bitmap `load_default()` font on systems without DejaVu/Segoe/Arial.
- `hud.py:196` — 2 Hz pulse; `:198-203` — banner thickness `int(4 + 4*sev*pulse)`; all magic.
- `hud.py:210-218` — face-lost thumbnail at fixed 120×90 with a hardcoded 6 px margin.

## 3.8 Flutter UI/UX (U)

### U-1 — CRITICAL — Two competing design systems in one app
- `theme.dart:5-62` (Stitch palette: bg `0xFF0E1416`, primary `0xFF4CD7F6`, used by all **mobile**) vs `theme.dart:65-108` (`AppColors`: bg `0xFF0a0e14`, accent `0xFF22d3ee`, used by all **desktop**).
- Two different surface stacks, two different accent cyans, and two `severity()` mappers with *different* level-1 colors (Stitch green vs AppColors cyan). `Stitch.severity` is dead code (`theme.dart:56-61`); `AppColors.alertAmber` and `AppColors.offlineYellow` are the same hex `0xFFfbbf24` under two names (`:82,:84`).

### U-2 — CRITICAL — Declared fonts are never bundled; the app renders in Roboto
- `pubspec.yaml` has **no `fonts:` section**; yet `main.dart:108` sets a global `fontFamily: 'Inter'`, and `'JetBrains Mono'` appears in **68+** explicit references across mobile screens (`connection_setup_screen.dart:331,355,362,…`, `mobile_settings_screen.dart:134,191,204,…`, `mobile_history_screen.dart:140,214,234,…`, `mobile_post_trip_screen.dart:113,289,346,…`, `mobile_live_monitor_screen.dart:100,180,283,…`, `mobile_app_shell.dart:171,312`, plus desktop text styles in `theme.dart:114`).
- **Impact:** the entire Stitch typography — the personality of the mobile UI — silently dissolves to Roboto on every run.
- **Fix:** vendor `Inter` + `JetBrains Mono` (license-compatible, e.g. Google Fonts), add a `fonts:` section, or delete every `fontFamily:` reference. There is no third option.

### U-3 — HIGH — 19 distinct `fontSize` literals (235 occurrences) vs 11 unused tokens
- Sizes: 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 30, 32, 36, 44, 48. `AppTextStyles.dataLg/dataMd/dataSm` (`theme.dart:153-167`) have **zero** usages.
- Several spots rebuild identical `TextStyle` objects per frame (`app_shell.dart:294-300`, `mobile_post_trip_screen.dart:432-435`).

### U-4 — HIGH — Card radius schism and a zero-alpha border
- `MaterialApp.cardTheme` radius **12** (`main.dart:123-124`) while hand-rolled cards use **16** everywhere (home/trip_log/trip_analytics) and `Card` widgets at 12 (`live_monitor_screen.dart:523,590,627`). Two corner sizes side by side.
- `calibration_settings_screen.dart:692` — `Color(0x444748)` is **six** hex digits = alpha `0x00` = an invisible border. (Someone typed a 3-short form into a 4-slot.)

### U-5 — HIGH — Breakpoint "single source of truth" is fiction
- `theme.dart:192-197` `AppBreakpoints` claims to fix "880 vs 1100"; screens hardcode `< 700` (home:233), `< 900` (live_monitor:74, calibration:293, trip_analytics:110), `< 650` (live_monitor:313), `< 600` (calibration:379,464), `< 1100` (home:62). `AppBreakpoints.compact` (:600) has **zero** usages.

### U-6 — HIGH — Copy-pasted responsive branches (same UI written twice)
- `home_screen.dart:80-116` vs `:118-161` (the whole stat-card row), `:238-262` vs `:318-343` (hero pill + headline + button), `:725-766` vs `:782-818` (entire `_TripRow`, interactive vs "non-interactive" twin).
- `live_monitor_screen.dart:315-381` vs `:383-436` (entire video header with Mute/Calibrate/HUD actions).
- `calibration_settings_screen.dart:298-331` vs `:339-372` (SYSTEM MODULES + 3 toggles), `:382-416` vs `:418-455` (header + Reset), `:466-487` vs `:489-512` (calibration card).
- `trip_analytics_screen.dart:112-159` vs `:161-201` (all four KPI cards).
- **Fix:** extract the two variants into a single widget parameterized by `LayoutBuilder` constraints; delete one copy.

### U-7 — HIGH — Rebuild storms
- `app_shell.dart:37-38` — a 1 Hz `Timer.periodic` that `setState`s the **entire shell** (sidebar + header + active page) 60×/minute.
- `mobile_app_shell.dart:48-62` — `setState` per telemetry tick (~15-30 Hz) over the whole mobile shell.
- `monitoring_client.dart:69-104` — `smooth()` rebuilds a full 31-field snapshot every tick to change a display string **no UI reads** (see U-12).

### U-8 — HIGH — Hardcoded layout numerals (representative)
- `home_screen.dart:66` `EdgeInsets.fromLTRB(32,24,32,48)` + `:69` `maxWidth: 1400`; `:222` `padding: EdgeInsets.all(40)`; `:402-406` ghost shield `SizedBox(width:48)` + `Icon(size:120)` at `opacity:0.1`.
- `live_monitor_screen.dart:442` `aspectRatio: 16/10`; `:613` `blinksPerMin / 30`; `:619-620` `ear / 0.4`, `ear < 0.2`; `:759-761` bars `(pitch, |·|, 30)`, `(yaw, |·|, 40)`, `(roll, |·|, 20)`.
- `mobile_live_monitor_screen.dart:111` fixed `width: 320` card (overflows phones < ~370 px); `:121-122` `128×128`; `:541-546` `dashCount=60`, `gapAngle=0.04`, and `3.14159` written out **six times** (`:544,546,571,574,575,581`) instead of `math.pi`.
- `calibration_settings_screen.dart:521-531` `200×200` ring box with `180×180` painter; `:641,:645` dot radii 5/3.
- `app_shell.dart:347-359` sidebar `width:80`, logo `40×40`, icons `22`, spacers 32/40; `:529` header `height:64`.

### U-9 — MEDIUM — Magic metrics duplicated from the backend
- `live_monitor_screen.dart:613-620` re-implements blink-rate and EAR thresholds in UI code instead of using snapshot fields. Machine values belong to the pipeline; the UI should only *display*.

### U-10 — MEDIUM — Dead or decorative UI
- `theme.dart:89-100` `primaryGradient`/`cardGradient` unused; `Stitch.severity` unused; `Stitch` tokens `surfaceDim, surfaceBright, onBackground, onSecondary, onSecondaryContainer, onTertiary, onTertiaryContainer, primaryContainer, onPrimaryContainer, surfaceVariant, primaryFixedDim, outline` — zero usages.
- `monitoring_client.dart:412-421` `fetchPairing()` never called from any screen.
- `app_shell.dart:733` — the file ends with a `// ─── Scroll-to-Top FAB ───` banner and **no widget underneath**.
- `home_screen.dart:27` `_loadingHistory` set/cleared but never rendered.
- `mobile_history_screen.dart:177` `onTap: () {}` (dead tap target).
- `mobile_settings_screen.dart:219,377` dead buttons (see F-6).
- `_GridPainter` (`live_monitor_screen.dart:966-981`) is the only painter without a `const` constructor.

### U-11 — MEDIUM — Icon & wording inconsistency
- Three settings icons: `settings_input_component_outlined` (sidebar `app_shell.dart:330,336`), `settings_outlined` (header `:568`), filled `Icons.settings` (mobile `mobile_app_shell.dart:263`).
- Mute button uses `volume_up` when *muted* (`live_monitor_screen.dart:360-362`) — an inverted affordance.
- Six `msg!` force-unwraps + string matching `msg!.contains('reconnected')` to color the connection banner (`app_shell.dart:276-299`) — the banner logic is one brittle string-match away from incoherence.

### U-12 — MEDIUM — Computed-but-unread client state
- `monitoring_client.dart:141` `errorMessage`, `:165` `isStale`, `:170` `displayedStatus` — none read by any screen. The MJPEG-is-dead-but-SSE-alive failure mode is invisible in the UI (the video area silently shows the placeholder).

### U-13 — MEDIUM — Hardcoded history timestamp math
- `trip_log_screen.dart:286` `15` px fonts and others in text types; `home_screen.dart:669` `trip['duration_s'] as double?` — int/double cast risk (see T-3). `mobile_history_screen.dart:167` uses the safe `as num?` — the two screens disagree on the correct cast for the same field.

### U-14 — LOW — Divider color is text color
- `home_screen.dart:901` `Divider(color: AppColors.textMuted)` — a horizontal rule the color of body copy instead of `outline`.

### U-15 — LOW — Product-name drift in chrome
- `web/index.html:32` `<title>driver_monitor</title>` and `:21` `<meta name="description" content="A new Flutter project.">` (the template placeholder, committed); `android:label="driver_monitor"`; iOS `CFBundleDisplayName "Driver Monitor"`; `windows/runner/main.cpp:30` `window.Create(L"driver_monitor")`; default 1280×720.
- The only place that knows the product is WakeGuard is `main.dart:101`.

## 3.9 Flutter Platform Config (P)

### P-1 — CRITICAL — Android has no `INTERNET` permission
- `flutter_app/android/app/src/main/AndroidManifest.xml` (46 lines): no `<uses-permission android:name="android.permission.INTERNET"/>`, yet `usesCleartextTraffic="true"` sits at line 6 as if it mattered.
- **Impact:** the mobile companion cannot make a single HTTP call on Android. The whole networking UI is a rain dance.

### P-2 — CRITICAL — iOS blocks cleartext pairing traffic
- `ios/Runner/Info.plist` has no `NSAppTransportSecurity`/`NSAllowsArbitraryLoads` exception → `http://192.168.x.x:8765` refuses to load on iOS.

### P-3 — MEDIUM — Release builds signed with the debug key
- `android/app/build.gradle.kts:34-36` — template `// TODO: Add your own signing config` left in; `applicationId "com.example.driver_monitor"` (`:19`) is the example ID.

### P-4 — MEDIUM — pubspec declares fonts it does not ship (see U-2) and `analysis_options.yaml` sets `avoid_print: false`
- The print-lint is explicitly disabled, and zero `print()`/`debugPrint` calls exist in `lib/` anyway — the guard was disabled and then never needed. Reconsider before someone needs it.

## 3.10 Documentation & README Drift (M)

- **M-1** — Structure tree (`README.md:69-108`) omits `yolo/db.py`, `yolo/db_sync.py`, `yolo/score.py`, the whole `supabase/` directory, `scripts/export_vault.py`, `scripts/migrate_to_supabase.py` — i.e. the entire ~1,200-line cloud layer is an undocumented wing of the house.
- **M-2** — `YoloEveryN` default: README table (`:284`) **1**, `settings.example.json:4` **1**, `config.py:173` **2** (comment admits "was 1 = 80-120ms starve"). Two documents describe the previous world.
- **M-3** — Endpoint list (`:190-202`) omits `/sessions/history`, `/sessions/{id}/telemetry`, and all six auth/device endpoints the mobile companion lives on.
- **M-4** — "70+ unit tests" (`:374`) vs actual 144.
- **M-5** — `PerclosWindowSeconds` "60 s at 30 Hz → 1800 samples" assumes a locked 30 Hz frame rate; the tracker counts frames (see A-9).
- **M-6** — Config table lists `PilHud` as a toggle; the PIL HUD is the *only* HUD. `settings.example.json` covers ~11 of ~35 knobs (no safety penalty, night mode, face-lost timers, hysteresis).
- **M-7** — `.env.example:1` — the `[TEMPLATE]` line is not dotenv syntax; harmless, but it migrated into `.env` itself (`.env:1`) and looks unfinished.
- **M-8** — `scripts/export_vault.py:161` emits `> Summary: [[../{base}]]` — Obsidian wiki-links cannot resolve relative `../` paths; the summary link is broken by construction. (Personal tool, committed to a product repo.)

## 3.11 Repository & Git Hygiene (R)

- **R-1** — `supabase/migrations/003_debug_registration.sql` is committed and creates a **real test user** (`test-trigger-debug@example.com`, password `testpass` via `crypt(...)`) inside a `DO $$` block; the `EXCEPTION WHEN OTHERS` handler can orphan that user if the failure happens after the INSERT. Debug+hardcoded-password, living in schema history.
- **R-2** — Migrations `002`, `003`, `004`, `005` all recreate the same `handle_new_user` trigger with textual variations; no applied-migration tracking — repo and DB can drift silently.
- **R-3** — Committed binaries `best.pt` + `face_landmarker.task` + `alert.mp3` with no Git LFS; `.gitignore:33-34` even carries the commented-out `# best.pt` and a "use Git LFS" note that was never executed. Every retraining run permanently grows history.
- **R-4** — Unmerged prior audit: `fix/ocd-audit-2026-08-28` (see Appendix C).
- **R-5** — `.env` holds real credentials (untracked ✓) but still carries the `[TEMPLATE]` marker line; rotation per P0.1 of the prior audit is still outstanding.
- **R-6** — Local git identity (`arv1903`) and absence of any `codebuff-team` commit — AGENTS.md identity guardrail satisfied.
- **R-7** — Working tree ~3 GB, dominated by the desynced `venv/` (see B-2).
---

# 4. Comprehensive Remediation Plan

Sequenced so that each sprint lands independent, verifiable value. Work on
`fix/ocd-hardening` (rebase, don't merge the old branch wholesale — cherry-pick
the two audit commits, then stack these).

**Working rule for every item:** follow TDD (RED → GREEN → REFACTOR); keep files
≤ 800 lines; honor the existing PascalCase-function style for Python and the
`@dataclass(frozen=True)` snapshot idiom.

## 4.0 Operation 0 — Absorb the existing fix pack (first day, 1-2 h)

1. Create `fix/ocd-hardening` from `main`.
2. Cherry-pick `fix/ocd-audit-2026-08-28` commits:
   - `4634011` fix: OCD audit pack P0-P5
   - `cd2620f` docs: OCD audit fix-pack spec
3. Resolve against the current `main`; **keep** these from the branch:
   - `main.py` imports (`json`, `verify_jwt`) — fixes F-2
   - `requirements.txt` — remove `opencv-python`, pin `numpy<2` (verify, B-3)
   - `yolo/pairing.py` token-write lock, `yolo/db.py` JWT alg pinning — S-5, A-1-write-hazard
   - `db_sync`/`summary` `avg_perclos` purity, CRLF-safe offsets — D-1, D-2
   - `scripts/check_secrets.py`
4. Do **not** blindly keep the branch's 241-line `calibration_settings_screen` rewrite until its behavior diff is reviewed (it churns 33 files; scope it separately).

## 4.1 P0 — Security (sprint 1, should land before anything is demoed)

| Task | Ref | Files | Verify |
|---|---|---|---|
| Default-deny auth; add `--api-open` (explicit opt-in) or require `--api-token` for `--api` | S-1 | `yolo/api.py`, `main.py` | `test_api.py`: no-token requests → 401 |
| Remove/replace CORS `*` (loopback origin only, or no CORS at all); reject browser `Origin` headers | S-1 | `yolo/api.py:106-115` | curl with `Origin: https://evil.example` → blocked |
| Wire `POST /api/v1/auth/refresh → db.auth_refresh` or delete the client refresh path entirely | S-2 | `yolo/api.py`, `yolo/db.py`, `flutter_app/lib/services/*` | integration test: refresh round-trip against a stub; or remove `_scheduleRefresh` |
| Stop interpolating `exc` into HTTP bodies; log server-side with `logging.exception` | S-3 | `yolo/api.py:321,350,372,421` | test asserts body contains stable code, not `exc` |
| Replace the `auth_register` debug block with one structured log line | S-4 | `yolo/db.py:190-197` | grep: no `args[`/`traceback.print_exc` in yolo/ |
| Pin JWT algorithms to `{"ES256","RS256"}`; lock JWKS refetch | S-5 | `yolo/db.py` | `test_db.py` extended: `alg=none` and `HS256` rejected |
| Raise pairing code to `token_hex(6)` (48 bits) and document the invariants | S-6 | `yolo/pairing.py`, `test_pairing.py` | test: code length 12; lockout unchanged |
| Add `scripts/check_secrets.py` to CI-precommit and rotate the real `.env` credentials | R-5 | `.env`, CI | fresh service key; `.env` no longer matches any public reference |

**Exit gate:** `pytest` green; a browser running on the same machine cannot read `/frame.jpg` nor POST `/session/stop`.

## 4.2 P1 — Core Functionality (sprint 2)

| Task | Ref | Files | Verify |
|---|---|---|---|
| Replace `"now()"` literals with `datetime.now(timezone.utc).isoformat()` in device register + heartbeat | F-1 | `yolo/api.py:314,341` | new test: `POST /device/register` inserts a row (stub DB) |
| Move the in-process heartbeat into `yolo/api.py` (or fix the three missing imports + `dir()` check) | F-2 | `main.py:326-406`, `yolo/api.py` | `python main.py --api --headless` with cached device.json → no NameError |
| Add `--max-seconds` to `main.py`; terminate headless runs at file EOF; EOF-terminal camera for file sources | F-4 | `main.py`, `yolo/pipeline.py:85-94` | `replay_eval` completes end-to-end on `testdata` clip |
| Fix mobile STOP path to `/api/v1/session/stop`, await, surface errors | F-3 | `mobile_live_monitor_screen.dart:484`, `monitoring_client.dart` | widget test asserts correct URL; manual: phone ends trip, desktop shell flips to idle (also fixes F-7) |
| Derive desktop `_isSessionActive` from `snapshot.tripActive` | F-7 | `app_shell.dart:111-167` | widget test: publish snapshot with tripActive=false → shell shows idle |
| Replace fabricated post-trip chart/incident log with real `fetchSessionTelemetry` + `alerts_by_type`/`alert_times`; pass `sessionStartTime`; real FPS | F-5, F-8 | `mobile_post_trip_screen.dart`, `mobile_live_monitor_screen.dart`, `mobile_app_shell.dart` | widget test with seeded snapshot |
| Wire mobile settings sliders/toggles to `/api/v1/settings`; hydrate from backend; implement LOGOUT | F-6 | `mobile_settings_screen.dart`, `auth_service.dart` | widget test asserts commands emitted with correct payloads |

**Exit gate:** a phone can pair, monitor, change thresholds, end the trip, and see a truthful post-trip report; the desktop reflects external session state.

## 4.3 P2 — Data Integrity (sprint 3)

| Task | Ref | Files | Verify |
|---|---|---|---|
| Single semantic for the PERCLOS column — rename to `max_perclos` end-to-end (schema + all three writers + readers) | D-1 | `001_initial_schema.sql` (+ backfill migration), `db_sync.py:325`, `summary.py:88-99`, `migrate_to_supabase.py:89` | query both live and migrated rows: value == max of its telemetry |
| Reset `_stats_*` in `bind_session` | D-2 | `db_sync.py:87-94` | test: two back-to-back sessions — second summary excludes first's samples |
| Move `_compute_session_stats` under a lock; snapshot lists first | D-3 | `db_sync.py:264-298,300-329` | concurrency stress test |
| Cap requeues (3 attempts → drop+log or SQLite dead-letter); bound `_pending` | D-4 | `db_sync.py:294-295` | test with an always-failing stub DB: queue stays finite |
| Make summary/history/telemetry/eval robust to malformed lines | D-5 | `summary.py:33,165`, `eval.py:30` | test: log with garbage line → graceful empty, not 500 |
| Do not delete unparseable SQLite rows | D-6 | `db.py:312-318` | test: corrupt row survives drain |
| `WriteQueue` lives or dies: either wire it into `db_sync` (dead-letter channel) or delete it and its tests | A-9/R-dead | `db.py` | `rg "WriteQueue"` → only intended use |

**Exit gate:** two trips produce two independent, correct Supabase summaries.

## 4.4 P3 — Dependencies & Tooling (sprint 4)

| Task | Ref | Files | Verify |
|---|---|---|---|
| Exactly one OpenCV package; floor ≥ 5.0.0; make `RQDecomp3x3` unpack tolerant regardless | B-1 | `requirements.txt`, `yolo/head_pose.py:74` | fresh venv: `pip check` clean; pose test passes on 4.x and 5.x |
| Re-sync the venv (`pip install -r requirements-dev.txt`); add a CI import-chain smoke test | B-2 | CI, venv | all 144 tests pass |
| Resolve the numpy floor empirically on a clean venv; document the decision | B-3 | `requirements.txt` | mediapipe smoke test at the pinned numpy |
| Add `Pillow>=10` explicitly | B-4 | `requirements.txt` | `pip check` |
| Raise the Flutter SDK floor to the resolved versions | B-5 | `pubspec.yaml` | `flutter analyze` clean on floor versions |
| Remove unused `SUPABASE_ANON_KEY` from the template | B-6 | `.env.example` | grep |

Plus upstream hygiene: Lint with `ruff` (enable F401/F841), type-check `yolo/` with `pyright` in CI, and add `pyproject.toml` while you're at it.

**Exit gate:** a fresh clone + fresh venv installs and runs `pytest` green with zero warnings-as-errors.

## 4.5 P4 — Robustness & Dead Code (sprint 5)

| Task | Ref | Files | Verify |
|---|---|---|---|
| Reconfigure startup-captured knobs on `update_settings` or restrict the API to honored keys | A-1 | `main.py:200-206,501-517`, `yolo/*` | test: change `PerclosWindowSeconds` → tracker window actually moves |
| Replace function-attribute `_infer_version`, `dir()` existence check, per-second snapshot filenames, conditional downscale | A-2 | `main.py:538-540,842-847,552-554,804` | refactor tests |
| Coalesce `notify_all` / conditional signaling in store + frame condition | A-3 | `monitoring.py:121`, `api.py:735` | SSE + MJPEG client tests on real connections |
| Lazy JPEG encode; only encode when a client is subscribed | A-4 | `api.py:725-735` | perf microbenchmark |
| Fix "drop oldest" comment lie; guard module-state races; make the telegram queue behave as documented | A-5 | `telegram.py:184-186` | test: full queue → oldest dropped, newest kept (or re-document) |
| Model/config paths anchored to the repo root | A-6 | `diagnostics.py`, `detector.py`, `main.py:141-142` | run from another CWD |
| EOF-terminal camera for file sources; safe shutdown ordering | A-7 | `pipeline.py:85-106` | replay + repeated start/stop stress |
| `session_log` `_kwargs`/unused param cleanup; `perclos` frame-window documentation or time-based window | A-9 | `session_log.py`, `perclos.py` | tests |
| Replace `except Exception: pass` episodes with `logging` + structure (inventory in prior plan P4.1) | A | across `yolo/` | `rg "except Exception: *pass"` near zero |

**Exit gate:** `ruff` clean; no `except Exception: pass` without a comment; start/stop the pipeline 50× without a crash.

## 4.6 P5 — UI / UX / Visual (sprint 6)

### Python HUD
| Task | Ref |
|---|---|
| Fix FPS bar normalization (`fps / max(1, DisplayFps)`) and FPS in headless/API mode | V-1, `hud.py:182` |
| Center the gauge on the panel (`cx = W - panel_w + panel_w/2`) | V-2, `hud.py:150` |
| Equalize gutters (20/20, not 20/28) | V-3, `hud.py:171,186` |
| Extract `HudColors` token set; make `NightMode` dim video + overlay coherently | V-4, V-5 |
| Harden font fallback (verified font paths; fallback to a bundled TTF) | V-6 |

### Flutter — unify the design system
| Task | Ref |
|---|---|
| Pick one palette (recommend: keep `AppColors`, migrate the six mobile screens off Stitch) OR ship both as a `ThemeMode`-aware theme; delete the dead `Stitch.severity` | U-1, `theme.dart` |
| Bundle Inter + JetBrains Mono in `pubspec.yaml` and delete nothing — or delete all 78 `fontFamily` refs | U-2 |
| Collapse 19 font sizes to ≤ the 11 tokens; use the existing `AppTextStyles` (and delete the unused ones) | U-3 |
| One card radius (12 or 16) via theme; fix `Color(0x444748)` → `Color(0x44474448)` | U-4 |
| Make `AppBreakpoints` real: single source of truth, used by every screen, or delete it | U-5 |
| Extract the duplicated responsive branches into one parameterized widget each | U-6 |
| Scope the 1 Hz shell tick to a clock widget; throttle mobile shell setState to display rate | U-7 |
| Replace magic layout numbers with named constants (`kSidebarWidth`, `kCardRadius`, `kGutter`, `kGaugeSize`) | U-8 |
| Stop duplicating backend thresholds in UI code; render `snap.ear`, `snap.blinksPerMin` | U-9 |
| Delete dead code (gradients, `fetchPairing`, `_loadingHistory`, `onTap: () {}`, dangling banner) | U-10 |
| One settings icon; fix the mute icon inversion; replace the `msg!.contains` banner with an enum | U-11 |
| Render `errorMessage`/`isStale` where they matter; surface MJPEG-dead state | U-12 |
| Normalize `as double?`/`as num?` casts site-wide | U-13, T-3 |
| `Divider` color → `outline` token | U-14 |
| Product name WakeGuard in web/android/iOS/Windows chrome | U-15 |

### Platform
| Task | Ref |
|---|---|
| Add `INTERNET` permission to AndroidManifest | P-1 |
| Add iOS ATS exception (scoped to the pairing host range if LAN-only) | P-2 |
| Real signing config + unique applicationId | P-3 |
| Reconsider `avoid_print: false` | P-4 |

**Exit gate:** `flutter analyze` clean; golden tests render with the bundled fonts; mobile screenshots match the Stitch mockup.

## 4.7 P6 — Documentation & Hygiene (sprint 7)

| Task | Ref |
|---|---|
| Update README structure tree with the Supabase layer + scripts | M-1 |
| Fix defaults table to match `config.py`; single-source via a table generated from `config.py` if feasible | M-2 |
| Document all real API endpoints (auth, device, sessions, pairing) | M-3 |
| "144 tests"; PERCLOS wording; `PilHud` removal; complete `settings.example.json` | M-4–M-6 |
| Remove `[TEMPLATE]` from `.env.example` and `.env` | M-7 |
| Fix the `export_vault.py` Obsidian link | M-8 |
| Rewrite `003_debug_registration.sql` → `00x`-style final state; consolidate `002-005` into one clean migration; add schema-version tracking (e.g. `schema_migrations` table + checksum) | R-1, R-2 |
| Move model files to Git LFS (or `git rm --cached` + documented download) | R-3 |
| Add a CONTRIBUTING + `AGENTS.md`-aligned test/lint commands table | R |

**Exit gate:** a fresh contributor can read one README and know the whole surface.

---

# 5. Fix Matrix (issue → fix → files → verification)

| ID | Severity | One-line fix | Primary files | Primary verification | Sprint |
|---|---|---|---|---|---|
| S-1 | CRIT | Default-deny auth; no CORS `*` | `yolo/api.py`, `main.py` | 401 on no-token; browser-origin probe blocked | P0 |
| S-2 | CRIT | Wire or delete `/auth/refresh` | `yolo/api.py`, `auth_service.dart` | refresh round-trip test, or no route references | P0 |
| S-3 | HIGH | No `exc` in bodies | `yolo/api.py` | body has stable code | P0 |
| S-4 | HIGH | One log line, no debug block | `yolo/db.py` | grep clean | P0 |
| S-5 | HIGH | Pin JWT algs; lock JWKS | `yolo/db.py` | algs tests | P0 |
| S-6 | MED | `token_hex(6)`; document invariants | `yolo/pairing.py` | code-length test | P0 |
| F-1 | CRIT | ISO timestamps, not `'now()'` | `yolo/api.py` | register inserts row | P1 |
| F-2 | CRIT | Fix imports/heartbeat home | `main.py`, `yolo/api.py` | smoke run w/ device.json | P1 |
| F-3 | CRIT | Correct mobile STOP path | `mobile_live_monitor_screen.dart` | URL-assert widget test | P1 |
| F-4 | CRIT | EOF-terminal + `--max-seconds` | `yolo/pipeline.py`, `main.py` | `replay_eval` completes | P1 |
| F-5 | CRIT | Real telemetry, not Random(42) | `mobile_post_trip_screen.dart` | seeded widget test | P1 |
| F-6 | HIGH | Wire settings; implement logout | `mobile_settings_screen.dart` | command-payload test | P1 |
| F-7 | HIGH | Derive active from snapshot | `app_shell.dart` | snapshot-switch test | P1 |
| F-8 | HIGH | Real FPS + session clock | `mobile_live_monitor_screen.dart` | seeded snapshot test | P1 |
| D-1 | HIGH | One PERCLOS semantic | `001`, `db_sync.py`, `summary.py`, `migrate` | cross-writer query test | P2 |
| D-2 | HIGH | Reset stats in bind | `db_sync.py` | two-session test | P2 |
| D-3 | HIGH | Stats under lock | `db_sync.py` | stress test | P2 |
| D-4 | HIGH | Bound requeues | `db_sync.py` | always-fail stub test | P2 |
| D-5 | MED | Tolerate malformed lines | `summary.py`, `eval.py` | garbage-line test | P2 |
| D-6 | LOW | Keep corrupt SQLite rows | `db.py` | drain test | P2 |
| B-1 | CRIT | One OpenCV pkg, floor 5 | `requirements.txt`, `head_pose.py` | `pip check`; 4.x+5.x pose test | P3 |
| B-2 | CRIT | Sync venv; CI import gate | CI, venv | 144 green | P3 |
| B-3 | HIGH | One real numpy floor | `requirements.txt` | mediapipe smoke at pin | P3 |
| B-4 | MED | Pillow explicit | `requirements.txt` | `pip check` | P3 |
| B-5 | MED | Real SDK floor | `pubspec.yaml` | analyze clean | P3 |
| A-1 | HIGH | Reconfigure runtime knobs | `main.py`, `*.py` | window-move test | P4 |
| A-2 | HIGH | Kill function-attr/`dir()`/snapshot collide | `main.py` | refactor tests | P4 |
| A-3 | MED | Coalesce signaling | `monitoring.py`, `api.py` | live SSE/MJPEG tests | P4 |
| A-4 | MED | Lazy JPEG | `api.py` | benchmark | P4 |
| A-5 | MED | Honest queue semantics | `telegram.py` | queue test | P4 |
| A-6 | MED | Root-anchored paths | `diagnostics.py`, `detector.py` | run from other CWD | P4 |
| A-7 | LOW | EOF / safe shutdown | `pipeline.py` | 50× start/stop | P4 |
| V-1 | HIGH | FPS bar / DisplayFps | `hud.py` | render test | P5 |
| V-2 | MED | Center gauge | `hud.py` | pixel-assert test | P5 |
| V-3 | MED | Symmetric gutters | `hud.py` | pixel-assert test | P5 |
| V-4/5 | MED | `HudColors` + night coherence | `hud.py`, `config.py` | render tests | P5 |
| U-1 | CRIT | One design system | `theme.dart`, mobile screens | golden tests | P5 |
| U-2 | CRIT | Ship the fonts | `pubspec.yaml` | golden renders non-Roboto | P5 |
| U-3 | HIGH | 19 → ≤11 sizes | all screens, `theme.dart` | lint + goldens | P5 |
| U-4 | HIGH | One radius; fix alpha | `main.dart`, `calibration:692` | goldens | P5 |
| U-5 | HIGH | Real breakpoints | `theme.dart`, screens | layout tests | P5 |
| U-6 | HIGH | De-dup responsive twins | home/live/calibration/analytics | widget tests | P5 |
| U-7 | HIGH | Kill rebuild storms | `app_shell.dart`, `mobile_app_shell.dart` | frame-count assertions | P5 |
| U-8 | HIGH | Named layout constants | screens | lint | P5 |
| U-10 | MED | Delete dead UI | `monitoring_client`, screens | `rg` | P5 |
| U-11 | MED | Icons/affordance/banner-enum | `app_shell/live_monitor` | screenshot review | P5 |
| U-12 | MED | Surface client errors | `monitoring_client.dart`, screens | widget tests | P5 |
| U-15 | MED | Product name | web/android/ios/windows | grep | P5 |
| P-1 | CRIT | INTERNET permission | AndroidManifest | device call | P5 |
| P-2 | CRIT | iOS ATS | Info.plist | device call | P5 |
| P-3 | MED | Signing + applicationId | `build.gradle.kts` | release build | P5 |
| M-1..8 | MED/LOW | README/config/verbatim truth | `README.md`, templates | doc review | P6 |
| R-1/2 | HIGH | Purge debug migration; consolidate | migrations | fresh project apply | P6 |
| R-3 | MED | LFS models | git | clone-size check | P6 |

---

# 6. Acceptance Checklist

### Must-pass gate (after sprints 0–2)
- [ ] `pytest -q` → **144 passed, 0 failed** on a clean `pip install -r requirements-dev.txt`
- [ ] `pip check` reports no conflicts; exactly one OpenCV package
- [ ] Browser on same machine cannot read `/frame.jpg` or issue commands against `--api` (no token)
- [ ] Device registration + heartbeat insert real rows; discovery lists a live device
- [ ] Phone can pair → monitor → change a threshold → end the trip; desktop mirror flips to idle
- [ ] `scripts/replay_eval.py --source testdata/sample.mp4 --labels testdata/labels.jsonl` **completes** and prints P/R/F1
- [ ] Post-trip report on mobile shows real telemetry/fps/incident data

### Must-pass gate (after sprints 3–4)
- [ ] Two adjacent trips produce independent Supabase summaries; `max_perclos` is a max on every path
- [ ] `rg "except Exception: *(pass|\n)"` returns only intentional, commented cases
- [ ] 50× sequential pipeline start/stop with no crash; MJPEG+SSE clients stay coherent across a backend restart
- [ ] Change `PerclosWindowSeconds` at runtime → the tracker's window actually changes

### Must-pass gate (after sprints 5–6)
- [ ] `flutter analyze` clean (with the print lint re-enabled)
- [ ] Mobile goldens render in JetBrains Mono; desktop in Inter; one palette; one card radius
- [ ] No `Random(42)`-or-hardcoded metric in any screen; no `onTap: () {}` on a visible button
- [ ] Android + iOS builds run networked against the backend

### Must-pass gate (after sprint 7)
- [ ] README matches reality (structure, endpoints, defaults, 144 tests)
- [ ] `003_debug_registration.sql` gone; migrations consolidated; schema version tracked
- [ ] Models on LFS or documented download; `.env` rotated and template-clean

---

*(Appendices follow in Part 4.)*
---

# 7. Appendix

## A. Verifiable Experiments Performed (this audit)

1. **`RQDecomp3x3` return arity and Euler mapping** (the head-pose lynchpin):
   - OpenCV 5.0.0 (`cv2.__version__ == "5.0.0"`): returns **6** values.
   - `Rx(−20°) → [−20, 0, 0]`, `Ry(+30°) → [0, 30, 0]`, `Rz(+15°) → [0, 0, 15]`.
   - So `head_pose.py:74` (`euler_angles, _, _, _, _, _ = ...`) and the
     pitch/yaw/roll mapping are **correct on OpenCV 5** — and would throw
     `ValueError` on OpenCV 4.x (`RQDecomp3x3` returns 3 there), which is the
     trap the mixed-open-package manifest sets.
   - Sign convention confirmed: rotation-with-nose-down maps to negative pitch
     in this y-down frame, matching `(SmoothedPitch - neutral_pitch) < -HeadDownPitch`.
2. **Test suite execution:** `144 tests collected; 141 passed; 3 failed` in 49.41 s
   (2 × missing PyJWT, 1 × `ConnectionAbortedError` in the revoke test).
3. **Dependency inspection:** `pip list` — both OpenCV 5.0.0.93 packages present;
   `supabase` and `PyJWT` absent; Pillow present (transitive).
4. **Git archaeology:** `git status` clean; `git ls-files` — `.env`/`settings.json`
   untracked; `git rev-list --objects` confirm committed model binaries;
   `git log main..fix/ocd-audit-2026-08-28` → the 2-commit fix pack.
5. **Config-claim cross-check:** `YoloEveryN` — README `1`, `settings.example.json` `1`,
   `config.py` `2` (three-way disagreement).

## B. Test Suite Output (condensed)

```
=========================== short test summary info ===========================
FAILED tests/test_api.py::test_pairing_revoke_requires_a_companion_token - Co...
FAILED tests/test_db.py::TestVerifyJwt::test_verifies_valid_token - ModuleNot...
FAILED tests/test_db.py::TestVerifyJwt::test_rejects_expired_token - ModuleNo...
3 failed, 141 passed in 49.41s
```

## C. Findings Convergence with `fix/ocd-audit-2026-08-28`

The prior branch's `plans/OCD_AUDIT_FIXES_2026-08-28.md` independently produced the
same families — confirmation this is a real register, not a single auditor's delusion:

| Prior ID | Equivalent here |
|---|---|
| P0.1 `.env` real secrets | R-5 |
| P0.2 pairing token direct write | S-6-adjacent, A-1 (write hazard `api.py:409`) |
| P0.3 JWT HS256 downgrade | S-5 |
| P0.4 opencv/numpy supply chain | B-1, B-3 |
| P1.1 LoadSettings range validation | A-1, H-10 |
| P1.4 knob-list drift | M-2 |
| P2.1 `avg_perclos` stores maximum | D-1 |
| P2.2 `dir()` in finally | A-2 |
| P2.3 heartbeat self-POST | F-2 |
| P2.6 CRLF offset drift | db_sync offset fragility |
| P2.7 telegram cooldown snapshot | A-5 |
| P3.1 severity map ×3 | V-4, U-1-adjacent (`hud.py:109`, `monitoring.py:16`, Flutter) |
| P3.2 landmark normalization ×3 | (acknowledged; low risk) |
| P3.4 migrations 002-005 same trigger | R-2 |
| P4.2 `WriteQueue._persist_remaining` dead | D-6-adjacent / A-9 |
| P5.5 README staleness | M-1..6 |

**Still open even on the branch:** `"now()"` literals (F-1), CORS `*` (S-1), missing
`/auth/refresh` route (S-2), replay-eval hang (F-4), font bundling (U-2), fabricated
mobile data (F-5/F-8).

## D. Unused Imports & Dead Symbols (exhaustive)

### Python
- `main.py` / `yolo/*`: no unused imports found in the audited modules (verified
  read-through; notably `WriteQueue` at `main.py:60` is imported but only used by
  tests — a dead import in production).
- **Dead symbols:** `calibration.RunCalibration` (test-only), `summary.WriteReport`
  (never called), `db.WriteQueue._persist_remaining` (never called), the
  `pairing_codes` schema table (no code path), `script`-side `migrate_to_supabase`
  duplicates `db_sync` logic.

### Flutter (unused imports, per file)
| File | Unused import |
|---|---|
| `flutter_app/lib/screens/home_screen.dart:1` | `dart:async` |
| `flutter_app/lib/screens/trip_log_screen.dart:1` | `dart:async` |
| `flutter_app/lib/screens/mobile/connection_setup_screen.dart:1` | `dart:async` |
| `flutter_app/lib/screens/mobile/mobile_history_screen.dart:1` | `dart:async` |
| `flutter_app/lib/screens/mobile/mobile_settings_screen.dart:1` | `dart:async` |
| `flutter_app/lib/services/auth_service.dart:1` | `dart:async` |
| `flutter_app/lib/services/device_discovery_service.dart:1` | `dart:async` |

(No `print()`/`debugPrint` calls exist in `lib/`, despite `avoid_print: false`.)

## E. Hardcoded Color Inventory (outside themes)

| Hex/literal | Meaning | Locations (representative) |
|---|---|---|
| `33444748` | border @20% | `app_shell.dart:423`; `live_monitor_screen.dart:334,400,726,757,889,1123`; `trip_analytics_screen.dart:271,298` |
| `44444748` | border @27% | `app_shell.dart:533`; `calibration_settings_screen.dart:208` |
| `444748` | **6-digit = alpha 0, invisible border** | `calibration_settings_screen.dart:692` |
| `22444748` | border @13% | `trip_analytics_screen.dart:669` |
| `FF22d3ee` | duplicate of `AppColors.accent` | `trip_analytics_screen.dart:132,136,179,182`; `home_screen.dart:893` |
| `40000000` | shadow @25% | `mobile_settings_screen.dart:578` |
| `Colors.white/white70/white54/black87/black(+α)` | unthemed HUD | `live_monitor_screen.dart:205,215,222,235,264,266,281,288,469,953,970`; `app_shell.dart:681`; `calibration:645`; `mobile_live_monitor:316` |

Python HUD (`hud.py`) hardcoded RGB: `(18,18,24)`, `(200,200,210)`, `(10,10,14)`,
`(76,175,80)/(255,193,7)/(244,67,54)`, `(60,60,70)`, `(100,200,255)`, `(150,150,160)`,
`(100,180,255)`, `(255,152,0)`, `(80,80,255)/(0,200,0)` (drawing.py labels).

---

## Closing judgment

The architecture deserves a better degree of completion. The pipeline, the alert
arbitration, the pairing and SSE contracts, the cross-version MediaPipe handling —
these are serious, experienced decisions. What they hide behind is a layer of
unfinished integration: a cloud feature chain that cannot write a row, a companion
app that cannot stop a trip or make a network call, a replay harness that cannot
finish, fonts that do not ship, and a diagnosis of all of it that has sat on a
branch for three days. None of these are hard. All of them are *uncomfortable to
finish*. This plan is the uncomfortable version, written down, sequenced, and
verifiable — with a merge as step one.

*Report generated 2026-08-31. Companion vault note: `notes/OCD Codebase Audit - 2026-08-31.md`.*
