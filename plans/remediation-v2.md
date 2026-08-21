# Remediation Plan V2 — Driver Drowsiness Detection

**Checkpoint:** `checkpoint-2026-08-21-v2` (tag on main, 865974d)
**Goal:** Fix all P0 demo blockers + correctness/performance regressions identified in 2026-08-21 audit before demo (1-2 days), then P1 polish in next sprint.
**Verified baseline:** `git diff 83e08af..HEAD` shows 26 files changed, 1073 inserts — many P1 items already partially done but P0 correctness/performance/responsiveness remain.

## Execution model
- Single branch `main` (direct mode, no GH PR workflow for now)
- Each step = one logical code area, self-contained, verified via `pytest` + `flutter analyze` + manual `python main.py --help` sanity.
- Dependency graph: Step 1 (correctness) → Step 2 (perf) → Step 3 (Flutter responsive) → Step 4 (Flutter state) → Step 5 (design/a11y) → Step 6 (dead code duplication). Steps 3-4 can parallelise, 5-6 can parallelise after 3.

---

## Step 1 — P0 Correctness & Logic Bugs (blocks all)
**Files:** `yolo/eyes.py`, `yolo/head_pose.py`, `yolo/config.py`, `yolo/pipeline.py`, `main.py`, `yolo/api.py`, `yolo/alarm.py`, `yolo/telegram.py`, `yolo/perclos.py`, `yolo/session_log.py`

### Tasks
- [ ] `yolo/eyes.py:23` — `ComputeEAR` returns `0.0` on `<468` → return `None` instead; caller treats `None` as `eyes_closed=False`. Update `BlinkMonitor.update` signature to accept `float|None` and guard.
- [ ] `yolo/head_pose.py:42` — handle MediaPipe wrapper `.landmark` vs plain list consistently with `pipeline._normalized_landmarks` (reuse helper or inline branch). Add test.
- [ ] `main.py:479-480` — guard EAR-based eye closure with `pose_valid` (or `face_found`), not just `result.ear is not None`. Fix spurious microsleep when face occluded.
- [ ] `main.py:314-354` — replace direct `blinks._closed_threshold` and `globals()["EarClosedThreshold"]` mutation with `BlinkMonitor.configure()` + `config.update_thresholds()` validated helper. Validate payload types, return `400` on bad values (string, NaN). Ensure `PerclosTracker` window not bypassed.
- [ ] `yolo/config.py:12-28` — extend `LoadSettings` validation to string keys (ProfilePath, SessionLogPath) and enum-like checks; reject `int` for string settings.
- [ ] `yolo/api.py:200-203` — expand pairing local-only check to handle `::ffff:127.0.0.1`, `127.x.x.x`, and header spoof guards; document Docker/reverse-proxy caveat.
- [ ] `yolo/alarm.py:39-49` — fix non-Windows stub to respect `SetAlarmMuted` clearing `_IsPlayingAlarm` flag correctly.
- [ ] `yolo/telegram.py:170` — stop mutating global `TelegramCooldown` per request; make per-call `Cooldown` param local.
- [ ] `yolo/session_log.py:11-62` — handle `OSError` on disk full (`open`/`write`), prevent double-close in `main.py:661`.
- [ ] `main.py:111-114` — warn when `--api` silently forces `headless=True` instead of silent override.
- [ ] `yolo/stats.py:27` naming — clarify `mean()` returns ms, rename or doc.

**Exit criteria:** `pytest tests/test_eyes.py tests/test_pipeline.py -v` passes; new regression tests for wrapper EAR None case.

## Step 2 — P0 Performance Throttles
**Files:** `yolo/pipeline.py`, `yolo/latest.py`, `yolo/perclos.py`, `yolo/hud.py`, `yolo/config.py`, `flutter_app/lib/services/monitoring_client.dart`, `flutter_app/lib/screens/trip_analytics_screen.dart`

### Tasks
- [ ] `yolo/pipeline.py:150-152` — avoid per-frame `mp.Image` copy: reuse RGB buffer or `mp.Image.create_from_file` pattern; benchmark allocation before/after.
- [ ] `yolo/config.py:78` — set `YoloEveryN=2` default (or document i5-8250U profile) to avoid 80-120ms per frame CPU starve.
- [ ] `yolo/latest.py:13-22` — replace spin-lock poll `sleep(0.005)` with `threading.Condition` (like `MonitoringStore`). Update `pipeline.py:128` and `main.py:369`.
- [ ] `yolo/perclos.py:29` — incremental running count instead of `sum(self._samples)` each frame (54k ops/s waste).
- [ ] `yolo/hud.py:92` vignette 16-step ellipse loop + `_GaugePainter MaskFilter.blur` — cache or reduce blurs; profile 30fps cost.
- [ ] `yolo/hud.py:46-52` — memoize `_font(size)` per size.
- [ ] `yolo/hud.py:59-69` `_static_panel` cache key ignores `panel_w` — include it.
- [ ] `flutter_app/services/monitoring_client.dart:272-303` — avoid `toBytes()` copy loop in `_feedMjpegBytes`; use view without copy (BytesBuilder view).
- [ ] `flutter_app/screens/trip_analytics_screen.dart:40-62` — throttle telemetry to 1 Hz (sample, not every snapshot at 30fps).

**Exit criteria:** CPU profiling shows <5% improvement on LatestValue poll; no visible stutter on Intel UHD at 1280p.

## Step 3 — P0 Flutter Responsiveness & Broken Buttons
**Files:** `flutter_app/lib/screens/*.dart`, `flutter_app/lib/theme.dart`, `flutter_app/lib/widgets`

### Tasks
- [ ] `trip_analytics_screen.dart:93-120` — wrap KPI Row in `LayoutBuilder` + `Wrap` or horizontal `SingleChildScrollView`; add `isCompact` check.
- [ ] `calibration_settings_screen.dart:68-95` — same for threshold cards Row(Expanded x2).
- [ ] `live_monitor_screen.dart:215-266` — make top action bar `Wrap` or `SingleChildScrollView(horizontal)`; ensure scroll affordance.
- [ ] `home_screen.dart:178-258` — make `_HeroCard` responsive: `LayoutBuilder` or column on `isCompact`; adjust shield size/position.
- [ ] `app_shell.dart:120` — normalize breakpoints: single `AppBreakpoints` class (600/900/1100); fix sidebar 880 vs home 1100 mismatch.
- [ ] `app_shell.dart:139` — keep Settings reachable when idle (always show sidebar or header nav); add hint when nav disabled.
- [ ] `home_screen.dart:480-512` — make `_TripRow` clickable (`onTap` → trip detail) or remove `InkWell` affordance + hoverColor.
- [ ] `home_screen.dart:614` — fix `_HoverLift` pointer cursor only on interactive cards (pass `clickable` flag).
- [ ] `home_screen.dart:220` — add `Tooltip("Backend disconnected")` to disabled `_GlowingButton`.
- [ ] `calibration_settings_screen.dart:334-378` — fix `_SliderRowState` `didUpdateWidget` to sync `_value` when parent resets.
- [ ] `live_monitor_screen.dart:646-658` — cancel `_pendingTimer` in `dispose()` to fix leak.

**Exit criteria:** `flutter analyze` no overflow warnings; manual test resizing to 800px, 1000px, 1400px shows no `RenderFlex overflowed` redscreens (remove `flutter_app/test/app_shell_widget_test.dart` overflow suppression).

## Step 4 — Flutter State & Robustness
**Files:** `flutter_app/lib/services/monitoring_client.dart`, `flutter_app/lib/screens/live_monitor_screen.dart`, `flutter_app/lib/screens/trip_analytics_screen.dart`, `flutter_app/lib/services/local_backend.dart`, `flutter_app/lib/main.dart`

### Tasks
- [ ] `live_monitor_screen.dart` — pick one rebuild mechanism: either `addListener+setState` OR `ValueNotifier`; remove double rebuild on every snapshot.
- [ ] `monitoring_client.dart:168-169` vs `api.py:255` — align `isStale>3s` vs SSE `25s` timeout; set stale to `>30s` or show "Waiting for data" instead of "Disconnected".
- [ ] `local_backend.dart:29-39` — wire `api-port` from `MonitoringClient.baseUrl` instead of hardcoded 8765.
- [ ] `flutter_app/lib/main.dart:37` — add `ErrorWidget.builder` + `FlutterError.onError` to avoid white-screen on `fromJson` crash.
- [ ] `monitoring_client.dart:385-395` — fix stale-update guard + `displayedStatus` 2-frame hysteresis after reconnect (show critical immediately).
- [ ] `flutter_app/lib/screens/trip_analytics_screen.dart:40-62` — deduplicate `addListener` + `ListenableBuilder` double rebuild.

**Exit criteria:** No duplicate rebuilds observed in Flutter DevTools; stale banner not shown during normal SSE wait.

## Step 5 — Design / A11y / HUD Fixes
**Files:** `flutter_app/lib/theme.dart`, `flutter_app/lib/screens/*.dart`, `yolo/hud.py`, `yolo/drawing.py`, `flutter_app/analysis_options.yaml`

### Tasks
- [ ] Add `Semantics(label:)` to all 5 screen buttons/interactive areas.
- [ ] Replace deprecated `withValues(alpha:)` vs `withOpacity` — keep `withOpacity` for Flutter 3.27 compatibility or migrate correctly; fix analyzer warnings (choose one and suppress other via `// ignore` if needed).
- [ ] Fix contrast: lift `textMuted` from `0xFF484f58` to `0xFF8b949e` or adjust `surface0` for WCAG AA 4.5:1.
- [ ] Replace `Colors.white54/white70/black87` with `AppColors` theme tokens.
- [ ] Normalize radius/spacing tokens: define `AppSpacings` + `AppRadius`.
- [ ] Resolve double attention smoothing: remove Flutter `_SnapshotSmoother` or make opt-in toggle; keep single source (backend EMA).
- [ ] `hud.py:203-204` — fix `Image.eval(overlay, lambda v: v//2)` halving alpha; instead multiply RGB only or use proper alpha compositing.
- [ ] Wrap `Scaffold` in `SafeArea` for Android gesture nav.
- [ ] Fix legacy `DrawHud` `addWeighted(0.56)` washout: adaptive brightness or deprecate legacy path.

**Exit criteria:** `flutter analyze` passes without warnings; Lighthouse-like contrast check >=4.5:1; no invisible HUD at noon.

## Step 6 — Dead Code & Duplication Cleanup
**Files:** `yolo/drawing.py`, `yolo/hud.py`, `yolo/head_pose.py`, `yolo/summary.py`, `yolo/config.py`, `flutter_app/lib/screens/post_trip_summary_dialog.dart`, `flutter_app/lib/widgets`

### Tasks
- [ ] Gate `drawing.DrawHud` behind `kDebugMode` or delete; main.py branches on `PilHud` — remove legacy path if unused.
- [ ] Extract `focal = w * 1.05` to `yolo/geometry.py` constant/helper; replace 4 duplicates.
- [ ] Extract `safety_score = avg_attention - len(alerts)*3` to `yolo/score.py`; unify Flutter and Python.
- [ ] Clean `yolo/__init__.py` empty marker or add exports.
- [ ] Fill `flutter_app/lib/widgets` or remove empty dir; replace `widget_test.dart` placeholder.
- [ ] Add real implementation or remove: `logging_enabled`, `BlinkRateAlertPerMin`, `NightMode`, `HeadPitchFocused*` — either wire them or delete config entries.

**Exit criteria:** No duplicated magic numbers; single source of truth for safety score.

## Verification Plan (after all steps)
- [ ] `pytest -q` all tests pass (including new regression tests for EAR None, head_pose wrapper, config validation)
- [ ] `flutter analyze` zero warnings
- [ ] `flutter test` passes without overflow suppression
- [ ] Manual smoke: `python main.py --help`, `python -m yolo.config` (if exists), resize Flutter to 800/1000/1400px, test calibration flow end-to-end, test mute/calibration shortcuts.
- [ ] Performance: `python -c "import yolo.pipeline"` smoke, no allocation spike.

## Anti-patterns to avoid
- Don't add `// ignore` without fixing root cause (a11y, contrast)
- Don't suppress `RenderFlex overflowed` in tests — fix layout
- Don't mutate `blinks._closed_threshold` directly — use configure API
- Don't halve alpha in NightMode — only dim RGB
- Don't poll `LatestValue` with `sleep` — use `Condition`

## Rollback per step
Each step is a single commit; revert via `git revert <sha>` if verification fails.
