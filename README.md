# 🚗 Driver Drowsiness & Distraction Detection (WakeGuard)

Real-time driver monitoring system that fuses a **YOLO eye-state classifier** with **MediaPipe Face Mesh landmark tracking** to detect drowsiness and distraction. A multi-threaded capture → inference → display pipeline evaluates **PERCLOS**, **EAR-based microsleep**, head-pose deviation, and an EMA-smoothed attention metric, then escalates through a priority-ordered alert state machine with hysteresis — driving an audible alarm, a Telegram alert (full-frame snapshot + timestamped geolocation), and an anti-aliased HUD rendered beside the camera feed. Optional **Supabase cloud sync** stores sessions, telemetry, and alert events for the Flutter companion dashboard.

---

## ✨ Features

| Feature | Description |
|---|---|
| **Eye-state classification** | Ultralytics YOLO (`best.pt`) detects eye regions and classifies them **Drowsy** (class 0) / **Alert** (class 1) with confidence scores |
| **Facial landmark tracking** | MediaPipe Face Landmarker extracts 468 normalized landmarks per frame (compatible with MediaPipe 0.10.x **and** 1.0+ — see [MediaPipe API compatibility](#-mediapipe-api-compatibility)) |
| **Head-pose estimation** | Perspective-*n*-point (`solvePnP`) pose recovery over six 2D→3D correspondences, decomposed into **pitch / yaw / roll** Euler angles |
| **Neutral-pose calibration** | Per-driver calibration profiles (sample means of the neutral pose) enable *relative* head-pose thresholds that are robust to seating geometry |
| **EAR blink/microsleep monitor** | Eye Aspect Ratio (EAR) computed from periocular landmark pairs; sustained closure beyond a threshold triggers a **microsleep** alert |
| **Blink-rate monitor** | Abnormally *slow* blink rate over an observation window raises its own alert (`BlinkRateAlertPerMin`) |
| **PERCLOS fatigue scoring** | Rolling-window percentage-of-eyelid-closure over fused YOLO+EAR closure evidence |
| **Attention scoring** | Weighted 0–100 score blending eye confidence, pitch, and yaw penalties with EMA smoothing |
| **Safety score** | Post-trip 0–100 score = avg attention − penalty × alert count (`yolo/score.py`, tunable via `SafetyScorePenaltyPerAlert`) |
| **Alert hysteresis** | Latches hold alerts active through a configurable grace period, eliminating on/off flicker |
| **Face-lost detection** | Escalates to a **FACE LOST** alert when the face vanishes (microsleep head-drop) instead of going silent |
| **Startup 3-2-1 countdown** | Evaluation is held for `StartupCountdownSeconds` (3 s) after a session starts — lets the driver settle and the camera auto-exposure converge before any alert can fire |
| **Multi-channel alert arbitration** | Six independent accumulator-based timers with a fixed priority chain |
| **Telegram dispatch** | Background worker sends the **full camera frame** with a caption (alert type, ISO timestamp, geolocation) plus a `sendLocation` pin; bounded queue + cooldown |
| **Supabase cloud sync (optional)** | Background tail-reader batches JSONL telemetry into `sessions`, `telemetry`, and `alert_events` tables; offline writes spool to a local SQLite queue and drain on reconnect |
| **Session logging & trip summaries** | Thread-safe JSONL telemetry (1 Hz samples + alert transitions) with `--summary` reporting |
| **Replay/eval harness** | Headless replay of a session log against labeled drowsy periods; precision / recall / F₁ evaluation |
| **JSON settings overrides** | Validated `--config settings.json` overrides of every tunable constant |
| **Startup diagnostics + CLI** | Model/camera/Telegram checks and `--headless`, `--record`, `--calibrate`, `--skip-calibration` flags |
| **Anti-aliased PIL HUD** | Gauge, sparkline, severity-pulsing alert banner, face-lost countdown ring — rendered **beside** the video, never over it |
| **Performance throttling** | YOLO and MediaPipe run on configurable frame strides; results persist across throttled frames to prevent false face-loss flapping |
| **Flutter integration API** | Optional local HTTP/SSE status service with account auth, device pairing, and versioned monitoring snapshots for a Flutter desktop dashboard or mobile companion |

### Alert Channels & Priority

| Channel | Trigger predicate | Persistence (τ) | Overlay |
|---|---|---|---|
| **Microsleep** | Continuous closure $\Delta t_c \ge \tau_{\mu s}$ | 1.5 s | `MICROSLEEP - EYES CLOSED! WAKE UP!` |
| **Combined / Head-nod** | $\theta_p - \theta_{p,0} < -\Theta_p$ ∧ $c > \Theta_{y,weak}$ ∨ sustained head-down | 1.5 s / 2.0 s | `HEAD NODDING - DROWSY!` |
| **PERCLOS / Fatigue** | $P(t) > \Theta_p$ sustained | 5.0 s | `FATIGUE DETECTED - SUSTAINED EYE CLOSURE!` |
| **Face lost** | Face absent; prior state drowsy / clean | 1.5 s / 3.0 s | `FACE LOST — POSSIBLE MICROSLEEP!` |
| **Distracted** | $\lvert \theta_y - \theta_{y,0} \rvert > \Theta_y$ | 1.5 s | `DISTRACTED - WATCH ROAD!` |
| **YOLO-only** | $c > \Theta_{y}$ | 4.0 s | `DROWSINESS DETECTED!` |

Priority (highest → lowest): **microsleep → combined/head-nod → PERCLOS → face-lost → distracted → YOLO-only**.

---

## 🏗️ Architecture

Three cooperating threads decouple capture from inference from rendering — slow stages never block fast ones:

```
┌──────────────┐   latest frame   ┌──────────────────┐   FrameResult   ┌─────────────────────┐
│ CameraThread │ ───────────────▶ │ InferenceThread  │ ───────────────▶ │ Display thread      │
│  cv2.Video   │  (drop-old)      │  YOLO  (YoloEveryN)                │ state machine:      │
│  Capture     │                  │  MediaPipe (HeadPoseEveryN)        │ timers, latches,    │
└──────────────┘                  │  → FrameResult                     │ attention, HUD,     │
                                  └──────────────────┘                 │ Telegram, recorder  │
                                                                       └──────────┬──────────┘
                          ┌────────────────────────────────────────────────┼──────────────┐
                          ▼                        ▼                       ▼              ▼
                    ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐  ┌────────────┐
                    │ Telegram     │   │ SessionLogger│   │ JsonlTailReader →  │  │ VideoWriter│
                    │ worker       │   │ (JSONL, 1 Hz)│   │ Supabase (offline  │  │ (--record) │
                    │              │   │              │   │ spool: SQLite)     │  │            │
                    └──────────────┘   └──────────────┘   └────────────────────┘  └────────────┘
```

Inter-thread handoff uses a **drop-old `LatestValue` slot** (see `yolo/latest.py`): consumers always read the newest item and intermediate frames are discarded, so a slow consumer can never block a producer. Detection results are *persisted across throttled frames* in `InferenceThread`, preventing the face-lost logic from flapping when YOLO/MediaPipe skip frames. When Supabase is configured, a background `JsonlTailReader` tails the JSONL log and batches rows into the cloud — the display thread is never touched, and writes made offline are persisted to a local SQLite queue and drained once connectivity returns.

---

## 📁 Project Structure

```
.
├── main.py                  # Entry point: CLI, state machine, display loop
├── best.pt                  # YOLO eye-state detection model
├── face_landmarker.task     # MediaPipe face landmark model
├── alert.mp3                # Audible alarm sound
├── requirements.txt         # Python dependencies
├── requirements-dev.txt     # Dev dependencies (pytest)
├── settings.example.json    # Template for JSON config overrides
├── .env.example             # Template for Telegram / Supabase / location credentials
├── scripts/
│   ├── record_sample.py     # Record a labelled sample video from the webcam
│   ├── replay_eval.py       # Replay a session log against label periods
│   ├── render_test_frame.py # Render the HUD onto a synthetic frame (QA)
│   ├── migrate_to_supabase.py # Import existing JSONL logs into Supabase
│   └── export_vault.py      # Export Freebuff threads to Markdown (tooling)
├── evaluation/              # YOLO dataset, validation charts, plot_metrics.py
├── supabase/migrations/     # SQL schema migrations (apply in order)
├── flutter_app/             # Flutter companion dashboard (desktop + mobile)
├── tests/                   # pytest suite (unit tests for every module)
├── profiles/                # Saved calibration profiles + pairing tokens
├── logs/                    # JSONL session logs
└── yolo/
    ├── pipeline.py          # Threaded capture→inference→display pipeline
    ├── detector.py          # YOLO + MediaPipe model initialisation
    ├── head_pose.py         # solvePnP head-pose estimation
    ├── eyes.py              # EAR computation, blink & microsleep monitor
    ├── perclos.py           # PERCLOS rolling window + drowsiness EMA
    ├── attention.py         # Attention scoring, accumulator timers, latches
    ├── score.py             # Safety score (avg attention − alert penalty)
    ├── calibration.py       # Neutral-pose calibration profiles
    ├── session_log.py       # Thread-safe JSONL session logging
    ├── summary.py           # Trip summary builder
    ├── eval.py              # Precision/recall/F₁ alert evaluation
    ├── telegram.py          # Async Telegram dispatch (full frame + location)
    ├── db.py                # Supabase client, JWT verify, offline write queue
    ├── db_sync.py           # JSONL → Supabase background tail-reader
    ├── alarm.py             # Windows MCI looping MP3 alarm
    ├── hud.py               # Anti-aliased PIL HUD (side-by-side canvas)
    ├── drawing.py           # cv2 HUD, boxes, pose axes, alert overlays
    ├── diagnostics.py       # Startup environment checks
    ├── envfile.py           # Dependency-free .env loader
    ├── config.py            # All tunable constants + LoadSettings
    ├── latest.py            # Drop-old thread handoff slot
    ├── monitoring.py        # Versioned state snapshots for clients
    ├── api.py               # Local HTTP/SSE/MJPEG API + auth/pairing endpoints
    ├── pairing.py           # One-time pairing codes and client tokens
    ├── discovery.py         # UDP LAN discovery beacon (mobile auto-find)
    └── stats.py             # Rolling per-stage performance timings
```

---

## 📋 Requirements

- **Python 3.10+** (developed and tested on 3.14)
- **Windows** (alarm uses Windows MCI; see [Adapting for Linux/macOS](#-adapting-for-linux--macos))
- **Webcam** (built-in or USB)
- MediaPipe **0.10.x or 1.0+** (both supported)
- *(Optional)* **Flutter 3.27+** for the companion dashboard
- *(Optional)* A **Supabase** project for cloud sync

---

## 📦 Installation

### Prerequisites

| Component | Minimum | Check with |
|---|---|---|
| Python | 3.10 | `python --version` |
| pip | 24 | `pip --version` |
| Git | any | `git --version` |
| Webcam | any DirectShow-capable device | — |

> **Windows note:** use a Python install from [python.org](https://www.python.org/downloads/) (or `winget install Python.Python.3.12`) and tick *Add python.exe to PATH* during setup.

### Step 1 — Get the code

```bash
git clone https://github.com/your-username/driver-drowsiness-detection.git
cd driver-drowsiness-detection
```

The two model files (`best.pt`, `face_landmarker.task`) and the alarm sound (`alert.mp3`) are tracked in the repository root — no separate download is needed.

### Step 2 — Create a virtual environment

```powershell
# Windows (PowerShell / CMD)
python -m venv venv
venv\Scripts\activate
```

```bash
# Linux / macOS
python3 -m venv venv
source venv/bin/activate
```

You should see `(venv)` at the start of your prompt. All later commands assume the venv is active.

### Step 3 — Install dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

This installs OpenCV, Ultralytics (YOLO), MediaPipe, NumPy, requests, Supabase, and PyJWT. First YOLO run may download nothing extra — weights are local.

For development (running the test suite):

```bash
pip install -r requirements-dev.txt
```

> **Torch note:** Ultralytics pulls in PyTorch automatically. On machines with an NVIDIA GPU you can optionally install a CUDA build afterwards for faster inference: `pip install torch --index-url https://download.pytorch.org/whl/cu121`. CPU-only works fine at the default `YoloEveryN` stride.

### Step 4 — Configure environment variables

Copy the template and fill in what you need — everything in `.env` is **optional**; the app runs fine without any of it:

```bash
copy .env.example .env        # Windows
# cp .env.example .env        # Linux / macOS
```

| Variable | Required | Purpose |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | for Telegram alerts | Bot token from [@BotFather](https://t.me/BotFather) |
| `TELEGRAM_CHAT_ID` | for Telegram alerts | Your chat ID (from [@userinfobot](https://t.me/userinfobot)) |
| `DRIVER_LOCATION_LAT` / `DRIVER_LOCATION_LON` / `DRIVER_LOCATION_NAME` | no | Exact GPS override; otherwise IP geolocation is used |
| `SUPABASE_URL` | for cloud sync | Your project URL (`https://<ref>.supabase.co`) |
| `SUPABASE_SERVICE_KEY` | for cloud sync | Service-role key (server-side only — never ship to the app) |
| `SUPABASE_JWT_SECRET` | legacy projects only | HS256 fallback when JWKS is unavailable |
| `DRIVER_API_TOKEN` | for LAN API | Bearer token required when binding the API to `0.0.0.0` |

The loader is dependency-free (`yolo/envfile.py`) and never overrides variables already set in the OS environment.

### Step 5 — (Optional) Supabase cloud sync

1. Create a project at [supabase.com](https://supabase.com).
2. Apply the schema migrations in order from `supabase/migrations/` (SQL editor → paste → run): `001_initial_schema.sql` first, then `002` … `005`.
3. Put `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` in `.env` (Step 4).
4. On startup you'll see `[db] Supabase connected — session data will be synced to the database`. Without it the app simply stays file-based.

To import existing JSONL logs into the cloud:

```bash
python scripts/migrate_to_supabase.py --email you@example.com --password secret
```

### Step 6 — Verify the installation

```bash
# Dependency sanity + model loading + camera probe
python main.py --help

# Run the offline test suite (no camera needed)
python -m pytest -q          # 184 unit tests
```

Then plug in / enable your webcam and do a short headless smoke run:

```bash
python main.py --headless --no-telegram --no-alarm --skip-calibration
```

Startup diagnostics will report anything missing (models, camera, credentials) with a `[!]` line before the session starts.

### Step 7 — First run

```bash
python main.py
```

Press the **start** action (or `S`-hotkey flow below); hold still and look straight ahead for the 4-second **neutral-pose calibration**, then drive. The calibration profile is saved to `profiles/driver.json` and reused on every later start — use `--calibrate` to redo it.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `ImportError: supabase package is not installed` | Supabase env vars are set but the package is missing → `pip install supabase`, or remove the vars to stay file-based |
| Camera opens but frames are black | Another app holds the webcam, or the index is wrong → try `--source 1` |
| `[!] Telegram enabled but … not set` | You didn't set both `TELEGRAM_BOT_TOKEN` **and** `TELEGRAM_CHAT_ID` — or run with `--no-telegram` |
| Alarm makes no sound | Windows MCI requires a default audio device; test `alert.mp3` in a media player |
| YOLO is slow (low FPS) | Set `YoloEveryN: 2` in `settings.json`, lower `CaptureWidth/Height`, or install a CUDA torch build |
| `LAN binding requires a token` (API) | Pass `--api-token CHANGE_ME` when using `--api-host 0.0.0.0` |

### Install the Flutter dashboard (optional)

```bash
cd flutter_app
flutter create .            # generate platform runners (first time only)
flutter pub get
flutter run -d windows --dart-define=API_URL=http://127.0.0.1:8765
```

Start the backend with `python main.py --api` in a second terminal. For a **mobile companion**, set `API_URL` to the desktop's LAN address and use **Pair device** (see [Flutter Client API](#flutter-client-api-optional)).

---

## 🚀 Usage

```bash
python main.py
```

On first session start the application **auto-calibrates** the neutral head pose (hold still, look straight ahead, 4 s). The window shows the camera feed with the HUD panel to its **right**; the camera is never occluded. Between trips the app idles and waits for a session start (via the API/hotkey), so the camera is only captured while a trip is active.

### CLI

| Flag | Effect |
|---|---|
| `--source ID\|PATH` | Camera index (default `0`) or video file for replay |
| `--headless` | No display window (benchmark / replay / CI smoke) |
| `--no-telegram` | Disable Telegram dispatch |
| `--no-alarm` | Disable the audible alarm |
| `--calibrate` | Force re-running neutral-pose calibration |
| `--skip-calibration` | Skip auto-calibration when no profile exists |
| `--log PATH` | JSONL session log path (default `logs/session.jsonl`) |
| `--summary LOG_PATH` | Print a trip summary from a log and exit |
| `--config PATH` | JSON settings file overriding `config.py` defaults |
| `--record PATH` | Record the annotated canvas (video + HUD) to an MP4 |
| `--api` | Expose the monitoring API (implies `--headless`) |
| `--api-host HOST` | API bind host (default `127.0.0.1`; LAN binding requires `--api-token`) |
| `--api-port PORT` | API bind port (default `8765`; `0` selects a free port) |
| `--api-token TOKEN` | Bearer token for API access (or env `DRIVER_API_TOKEN`) |

### Hotkeys

| Key | Action |
|---|---|
| `Q` | Quit |
| `S` | Save a full-canvas snapshot to `captures/` |
| `M` | Mute / unmute the alarm |
| `P` | Pause evaluation (frame frozen, panel preserved) |
| `R` | Toggle manual recording (when `--record` not set) |

### Flutter Client API (optional)

Start the monitoring API for a Flutter desktop or mobile client:

```bash
# Desktop-only: Flutter connects through localhost
python main.py --api

# Mobile companion on the same LAN: bind explicitly and require a token
python main.py --api --api-host 0.0.0.0 --api-token CHANGE_ME
```

The API is dependency-free and exposes the latest state and camera frame at:

```text
GET  /api/v1/health
GET  /api/v1/status
GET  /api/v1/events?after=<sequence>
GET  /api/v1/frame.jpg
GET  /api/v1/video.mjpg
GET  /api/v1/device
GET  /api/v1/sessions/current
GET  /api/v1/sessions/current/summary
GET  /api/v1/sessions/history
GET  /api/v1/sessions/<id>/telemetry
GET  /api/v1/pairing
GET  /api/v1/pairings              (deployment token only)
GET  /api/v1/device/discover
POST /api/v1/pairing/exchange
POST /api/v1/pairing/revoke
POST /api/v1/pairings/revoke      (deployment token only)
```

Account & device endpoints (backed by Supabase when configured):

```text
POST /api/v1/auth/register        # create account (email + password)
POST /api/v1/auth/login           # returns access + refresh JWT
POST /api/v1/auth/refresh         # rotate session tokens
POST /api/v1/auth/pair            # link a device to the logged-in user
POST /api/v1/device/register      # register this desktop device (JWT required)
POST /api/v1/device/heartbeat     # keepalive with current API host/port
```

`/events` returns one Server-Sent Event containing the next monitoring snapshot; clients reconnect using the returned sequence number. Each API process also publishes a `server_id`, allowing clients to recover when the backend restarts and its sequence counter resets. The API accepts authenticated control requests for alarm mute/unmute, trip analytics start/stop, settings updates, and calibration. It binds to `127.0.0.1` by default, and LAN binding is rejected unless `--api-token` is supplied. Use `/frame.jpg` for polling clients or `/video.mjpg` for a persistent latest-frame MJPEG stream; slow clients never block detection because old frames are dropped.

Pairing is local-first: `GET /api/v1/pairing` reveals a short-lived, QR-compatible pairing URI only to a local desktop client. The companion sends that one-time code to `POST /api/v1/pairing/exchange` and receives a bearer token valid for 24 hours. Failed exchanges are bounded by a temporary lockout to slow code guessing. A companion can revoke its own token with authenticated `POST /api/v1/pairing/revoke`; the Flutter **Forget paired device** action clears local credentials and requests that revocation. The original `--api-token` remains valid for administration and cannot be revoked through this endpoint.

#### Zero-Touch Discovery (mobile)

When bound to the LAN, the backend also answers a UDP discovery broadcast so the mobile app never needs a typed address:

- Desktop: `python main.py --api --api-host 0.0.0.0 --api-token CHANGE_ME` starts a discovery beacon on `udp/48765` automatically.
- Phone: the setup screen broadcasts `WG-DISCOVER` to `udp/48765` on open and lists every WakeGuard backend that answers — tap one, sign in, done.
- The backend's IP is taken from the UDP reply's *source address*, never from the payload, so a spoofed packet cannot redirect the client to itself.
- Manual entry remains as a fallback: AP isolation, VPNs, and enterprise Wi-Fi can block broadcasts. Allow inbound `udp/48765` once in the firewall (rule names: `WakeGuard Discovery`, plus `WakeGuard API` on tcp/8765).

#### QR Pairing (mobile, discovery-free)

For networks where broadcast discovery is blocked, the desktop can display a pairing QR code instead:

- Desktop: **Settings → Companion Devices → SHOW PAIRING QR**. The dialog fetches the one-time code from `GET /api/v1/pairing`, renders it as a QR (payload: `{"v":1,"code":...,"host":...,"port":...}`), shows a countdown from `expires_at`, and auto-rotates when the window lapses.
- Phone: **Scan QR Code** on the setup screen opens the in-app camera. The scanned payload points the client at the desktop's LAN address and exchanges the code via the unauthenticated `POST /api/v1/pairing/exchange` for a 24-hour scoped bearer token.
- The code is single-use, rotates on every successful exchange, and failed exchanges are rate-limited by the existing `PairingManager` lockout.

#### Paired-Device Management (desktop admin)

The desktop's **Companion Devices** card lists every live companion token:

- `GET /api/v1/pairings` (deployment token only) returns `{devices: [{token_preview, device_name, issued_at, expires_at}]}` — an 8-character preview, never the secret itself.
- `POST /api/v1/pairings/revoke` with `{token_preview}` (deployment token only) revokes that device; companion tokens get `403` on both endpoints.
- The phone labels its pairing during `POST /api/v1/pairing/exchange` via the optional `device_name` field.

### Flutter Dashboard

The shared Flutter client lives in [`flutter_app/`](flutter_app/). It supports responsive desktop/mobile layouts, API reconnection, stale-state detection, status gauges, a persistent MJPEG camera feed, and authenticated controls.

```bash
cd flutter_app
flutter pub get
flutter run -d windows --dart-define=API_URL=http://127.0.0.1:8765
```

For a mobile companion, set `API_URL` to the backend machine's LAN address and use **Pair device** in connection settings. Reveal the code on the local desktop, then enter it on the phone; the app exchanges it for a short-lived token. Manual bearer-token entry remains available for administration. Flutter SDK validation must be run on a machine with Flutter installed.

### Telegram & Location (optional)

Each alert sends the **full camera frame** with a caption `🚨 <type>` / `🕒 <ISO timestamp>` / `📍 <name> (lat, lon)`, followed by a `sendLocation` map pin. Coordinates come from `DRIVER_LOCATION_*` if set, else free IP geolocation (ip-api.com) cached for 10 minutes with a bounded 2 s lookup. Dispatch is rate-limited by `TelegramCooldown` (30 s). See [Installation → Step 4](#step-4--configure-environment-variables) for the `.env` keys.

### Supabase Cloud Sync (optional)

When `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` are set:

- A background `JsonlTailReader` tails `logs/session.jsonl` and batches rows into the **`sessions`**, **`telemetry`**, and **`alert_events`** tables, tagged with the current `session_id`, device, and user.
- Every session start binds the tail-reader to the new session; stop unbinds it.
- If the network (or Supabase) is down, writes spool into a local **SQLite queue** (`yolo/db.py: WriteQueue`) and are replayed in order when connectivity returns — nothing is lost mid-trip.
- JWTs presented to the API are verified against the project's **JWKS** (ES256) with an HS256 `SUPABASE_JWT_SECRET` fallback for legacy projects.
- Schema lives in `supabase/migrations/`; import historical JSONL logs with `scripts/migrate_to_supabase.py`.

Without Supabase configured, every helper returns `None` and the system stays fully file-based — no other behavior changes.

---

## ⚙️ Configuration

Every tunable constant lives in **[`yolo/config.py`](yolo/config.py)** and can be overridden at runtime with a validated JSON file (unknown keys or type-mismatched values raise `ValueError`):

```json
{
  "HeadDownPitch": 18.0,
  "EarClosedThreshold": 0.22,
  "HudPanel": 300
}
```

```bash
python main.py --config settings.json
```

| Section | Key Constants | Default |
|---|---|---|
| Head pose | `HeadDownPitch`, `HeadYawThreshold`, `HeadRollThreshold` | 20°, 30°, 10° |
| Alert timers | `HeadDownTime`, `HeadAwayTime`, `CombinedDrowsyTime` | 2.0 s, 1.5 s, 1.5 s |
| Face lost | `FaceLostDrowsyTime`, `FaceLostCleanTime` | 1.5 s, 3.0 s |
| YOLO | `YoloDrowsyThreshold`, `YoloDrowsyWeak`, `YoloDrowsyDuration` | 0.5, 0.3, 4.0 s |
| EAR / microsleep | `EarClosedThreshold`, `EarMinBlinkSeconds`, `MicrosleepSeconds` | 0.20, 0.10 s, 1.5 s |
| Blink rate | `BlinkRateAlertPerMin`, `BlinkRateAlertTime` | 8.0 /min, 10 s |
| PERCLOS | `PerclosWindowSeconds`, `PerclosAlertThreshold`, `PerclosAlertTime` | 60 s, 0.5, 5.0 s |
| Attention | `AttentionFocusedMin`, `AttentionUnfocusedMin`, `AttentionSmoothAlpha` | 80, 50, 0.85 |
| Safety score | `SafetyScorePenaltyPerAlert` | 3.0 points/alert |
| Hysteresis | `ClearGraceSeconds` | 2.0 s |
| Pipeline | `CaptureWidth/Height`, `YoloEveryN`, `HeadPoseEveryN`, `DisplayFps` | 640×480, 1, 2, 30 |
| Startup | `StartupCountdownSeconds` | 3.0 s (0 disables) |
| Layout | `FrameWidth`, `FrameHeight`, `HudPanel` | 1280, 720, 275 px |
| Misc | `PilHud`, `NightMode`, `SessionLoggingEnabled`, `SessionLogPath`, `ProfilePath`, `TelegramCooldown` | True, False, True, `logs/session.jsonl`, `profiles/driver.json`, 30 s |

---

## 🧠 Algorithmic Core

### Head-Pose Estimation (Perspective-*n*-Point)

MediaPipe yields 468 normalized landmarks $\{\ell_i\}_{i=1}^{468}$; six of them — nose tip (1), chin (152), eye corners (33, 263), mouth corners (61, 291) — form 2D image points $\mathbf{p}_i = (\ell_{i,x} \cdot w,\ \ell_{i,y} \cdot h)$. With the intrinsic matrix

$$\mathbf{K} = \begin{bmatrix} f & 0 & c_x \\ 0 & f & c_y \\ 0 & 0 & 1 \end{bmatrix}, \qquad f = 1.05\,w,\quad (c_x, c_y) = (w/2,\ h/2),$$

and a generic 3D face model $\{\mathbf{P}_i\}$, OpenCV's `solvePnP` (EPnP) recovers the rigid transform $[\mathbf{R} \mid \mathbf{t}]$ by minimising the reprojection residual

$$\min_{\mathbf{R},\mathbf{t}} \sum_i \left\| \mathbf{p}_i - \pi\big(\mathbf{K}, [\mathbf{R} \mid \mathbf{t}], \mathbf{P}_i\big) \right\|^2,$$

where $\pi$ is the perspective projection. $\mathbf{R}$ is extracted via Rodrigues and decomposed into **pitch** $\theta_p$, **yaw** $\theta_y$, **roll** $\theta_r$ through `RQDecomp3x3`. Sign conventions: $\theta_p > 0$ = looking up, $\theta_p < 0$ = down (drowsiness); $|\theta_y| > 0$ = looking away (distraction).

Because seating geometry varies per driver, calibration records the neutral pose as the arithmetic mean over $N$ valid samples

$$\theta_{0} = \frac{1}{N}\sum_{i=1}^{N}\theta^{(i)},$$

and all detection uses the **relative** deviation $\Delta\theta = \theta - \theta_0$. Pose estimates are exponentially smoothed with factor $\alpha_P = 0.35$:

$$\bar\theta_t = \alpha_P\,\theta_t + (1-\alpha_P)\,\bar\theta_{t-1}.$$

### Eye Aspect Ratio (EAR)

For each eye, the six periocular landmarks $\{p_1 \dots p_6\}$ (left: indices 33,160,158,133,153,144; right: 362,385,387,263,373,380) define

$$\text{EAR}_e = \frac{\lVert p_2 - p_6 \rVert + \lVert p_3 - p_5 \rVert}{2\,\lVert p_1 - p_4 \rVert + \varepsilon},$$

with the Euclidean norm $\lVert \cdot \rVert$ and $\varepsilon = 10^{-6}$ guarding against division by zero. The reported value is the mean over both eyes: $\text{EAR} = \tfrac{1}{2}(\text{EAR}_L + \text{EAR}_R)$. The scalar is robust to subject distance because both numerator and denominator scale linearly with it.

**Closure / blink / microsleep classification** — let $\Delta t_c$ be the duration of a continuous closure episode $(\text{EAR} < \theta_E = 0.20)$:

- **Closure predicate**: $c_t = \mathbb{1}[\text{EAR}_t < \theta_E]$
- **Blink**: $\tau_{blink} \le \Delta t_c < \tau_{\mu s}$ ($0.10 \le \Delta t_c < 1.5$ s)
- **Microsleep**: $\Delta t_c \ge \tau_{\mu s} = 1.5$ s (a microsleep is *not* also counted as a blink)
- **Blink rate**: $r(t) = \lvert \{ t_i : t - t_i < 60 \text{ s} \} \rvert$ — falling below `BlinkRateAlertPerMin` (8/min) sustained for `BlinkRateAlertTime` (10 s) raises its own alert

### Drowsiness EMA & PERCLOS

The YOLO drowsy confidence $c_t$ is low-pass filtered with an exponential moving average ($\alpha_E = 0.9$):

$$E_t = \alpha_E\,E_{t-1} + (1-\alpha_E)\,c_t.$$

Fused **eyes-closed** evidence combines the EMA with EAR:

$$\text{closed}_t \iff E_t > \theta_{Y} \;(0.3) \;\lor\; \text{EAR}_t < \theta_E.$$

**PERCLOS** (percentage of eyelid closure) is the fraction of closed samples in a rolling window of $N = \lfloor W \cdot f_s \rfloor = 1800$ samples ($W = 60$ s at $f_s = 30$ Hz):

$$P(t) = \frac{1}{N}\sum_{i=t-N+1}^{t}\mathbb{1}[\text{closed}_i].$$

A **fatigue alert** fires when $P(t) > \Theta_P = 0.5$ is sustained for $\tau_P = 5$ s.

### Attention & Safety Scores

A 0–100 attention score starts at 100 and subtracts three penalties (weights $w_y = 30$, $w_p = 40$, $w_e = 50$):

$$A = \mathrm{clamp}\!\left(\;100 - w_y\min\!\Big(1,\tfrac{\lvert \theta_y \rvert}{45°}\Big) - w_p\min\!\Big(1,\tfrac{\lvert \min(\theta_p, 0) \rvert}{30°}\Big) - w_e\, c,\; 0,\; 100 \right),$$

then EMA-smoothed with $\alpha_A = 0.85$. Zones: **Focused** $\bar A \ge 80$, **Unfocused** $50 \le \bar A < 80$, **Low** $\bar A < 50$.

The post-trip **safety score** (`yolo/score.py`) is deliberately simple:

$$S = \mathrm{clamp}\big(\bar A - n_{\text{alerts}} \cdot \text{SafetyScorePenaltyPerAlert},\ 0,\ 100\big),$$

with penalty 3.0 points per alert — tunable via settings JSON, shared as a single source of truth by the Python summary and the Flutter dialog.

### Accumulator Timers & Alert Hysteresis

Each alert channel uses an accumulator with a configurable persistence requirement $\tau$:

$$A_t = \begin{cases} 0 & \text{condition false} \\ A_{t-1} + \Delta t & \text{condition true, not frozen} \\ A_{t-1} & \text{frozen (face lost)} \end{cases}, \qquad \text{fire} \iff A_t \ge \tau.$$

Freezing preserves timer progress through face-loss episodes without premature firing. A separate **latch** implements hysteresis for the PERCLOS and microsleep channels: once fired, the alert stays active until the condition has been clean for $\tau_{clear} = 2.0$ s, eliminating on/off flicker.

### Face-Lost State Machine

On the transition *face present → absent*, the system snapshots the last known state; the alert fires when the absence time satisfies $t_{lost} \ge \tau_{risky} = 1.5$ s (prior state drowsy/head-down) or $t_{lost} \ge \tau_{clean} = 3.0$ s (prior state clean). The machine is frozen during the startup countdown so warm-up frames can never seed it.

### Session Metrics & Evaluation

From the JSONL telemetry, the trip summary computes the arithmetic mean and extrema of the attention and PERCLOS series, e.g. $\bar{x} = \frac{1}{n}\sum_{i=1}^{n} x_i$. The replay harness (`scripts/replay_eval.py`) evaluates fired alerts against labeled drowsy periods episode-wise with tolerance $\epsilon_t = 5$ s and reports

$$P = \frac{TP}{TP + FP}, \qquad R = \frac{TP}{TP + FN}, \qquad F_1 = \frac{2PR}{P + R}.$$

---

## 🧪 Testing

```bash
python -m pytest -q        # 184 unit tests across all modules
```

The suite covers EAR geometry, PERCLOS/EMA math, latch semantics, timer freezing, calibration round-trips, session-log schema, eval metrics, settings validation, the env loader, the threaded pipeline (including MediaPipe 0.10.x vs 1.0+ landmark shapes), the side-by-side HUD canvas, Telegram caption/location dispatch, Supabase write-queue spooling, JSONL→Supabase sync, the API/auth/pairing handlers, and UDP discovery.

---

## 📊 Model Evaluation

`evaluation/` contains the Roboflow-exported YOLO dataset, a `plot_metrics.py` script that re-renders validation charts with clean class names, and the resulting figures (confusion matrices, PR/F1/P/R confidence curves) under `evaluation/charts/`:

```bash
python evaluation/plot_metrics.py --model best.pt --data evaluation/dataset/data.yaml
```

---

## 🔄 MediaPipe API Compatibility

MediaPipe **< 1.0** returns `face_landmarks[0]` as a `NormalizedLandmarkList` wrapper exposing a `.landmark` attribute; **1.0+** returns a plain `list[NormalizedLandmark]`. `pipeline._normalized_landmarks` normalizes both shapes, so the application runs unchanged on either version. The inference thread also guards every frame with a bounded retry loop, so a transient per-frame failure can never silently kill the video feed.

---

## 🔧 Adapting for Linux / macOS

The alarm system uses **Windows MCI** (`ctypes.windll.winmm`). To run on other platforms, replace `yolo/alarm.py` with:

```python
# Example using playsound (pip install playsound)
import threading
from playsound import playsound

_IsPlayingAlarm = False

def UpdateAlarm(Active):
    global _IsPlayingAlarm
    if Active and not _IsPlayingAlarm:
        _IsPlayingAlarm = True
        threading.Thread(target=playsound, args=("alert.mp3",), daemon=True).start()
    elif not Active:
        _IsPlayingAlarm = False
```

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgements

- [Ultralytics YOLO](https://github.com/ultralytics/ultralytics)
- [MediaPipe](https://github.com/google-ai-edge/mediapipe)
- [OpenCV](https://opencv.org/)
- [Pillow](https://python-pillow.org/) (anti-aliased HUD rendering)
- [Supabase](https://supabase.com/) (optional cloud sync)
