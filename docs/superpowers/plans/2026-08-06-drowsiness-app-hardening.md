# Driver Drowsiness & Distraction Detection — Improvement & Hardening Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current single-threaded, config-in-source, bare-`cv2` prototype into a robust, higher-FPS, more accurate and visually polished driver-monitoring tool, delivered in priority-ordered phases where each phase leaves the app runnable and tested.

**Architecture:** Six sequential phases (P0–P5) plus a stretch list (P6). P0 restores the deleted working tree from git and adds a pytest safety net. P1 refactors the sequential main loop into a three-thread pipeline (capture → inference → display) with drop-old "latest frame" semantics. P2 adds industry-standard drowsiness signals (PERCLOS, EAR/blink/microsleep), a startup pose-calibration baseline, and alert hysteresis. P3 adds JSONL session logging, a trip summary, and a replay/eval harness for scientific threshold tuning. P4 adds JSON settings, CLI flags, startup diagnostics, and keyboard shortcuts. P5 replaces the OpenCV HUD with anti-aliased PIL rendering, graduated alerts, sparklines, and night mode. P6 lists optional stretch goals (ONNX export, PyInstaller, web dashboard, i18n).

**Tech Stack:** Python 3.10+, OpenCV (`cv2`), Ultralytics YOLO, MediaPipe Face Landmarker, Pillow, requests, pytest. Primary target OS: Windows (alarm uses Windows MCI).

---

## Global Constraints

- Python **3.10+**; Windows is the primary target (MCI alarm in `yolo/alarm.py`).
- The run command stays `python main.py`. All new behavior is opt-in via CLI flags or settings.
- Models `best.pt`, `face_landmarker.task` and `alert.mp3` stay at the project root (they are committed binaries).
- All tunable constants continue to live in `yolo/config.py`; JSON settings only *override* them at startup.
- Files you modify keep the repo's existing naming convention (PascalCase public functions, e.g. `DrawHud`, `UpdateAlarm`). New files follow PEP8 (`snake_case`).
- Do not change existing alert message strings; only add new ones.
- Existing pure functions `ComputeAttentionScore` and `UpdateTimer` (in `yolo/attention.py`) keep their current signatures — other modules depend on them.
- Unit tests must not require a camera, models, or network. Camera/model-dependent tests are marked `@pytest.mark.integration`.
- Commit after every task (frequent, small commits).

---

## Priority Overview

| Phase | Title | What it delivers | Effort |
|---|---|---|---|
| **P0** | Foundation: restore + test harness | Working tree restored, venv, pytest green on existing pure logic | S |
| **P1** | Performance: threaded pipeline | 1.5–2.5× FPS, lower capture res, YOLO throttle, async Telegram, FPS instrumentation | L |
| **P2** | Detection quality | PERCLOS, EAR + blink/microsleep, pose calibration, alert hysteresis, face binding | L |
| **P3** | Observability | JSONL session log, trip summary, replay/eval harness with precision/recall | M |
| **P4** | Usability | JSON settings, CLI flags, startup diagnostics, keyboard shortcuts, audio controls | M |
| **P5** | Visual HUD | Anti-aliased PIL HUD, graduated alerts, attention sparkline, night mode | L |
| **P6** | Stretch (optional) | ONNX export, PyInstaller packaging, web dashboard, i18n | varies |

**Priority rationale:** P0 first because the working tree is currently empty — nothing else can be built or tested until the repo is restored and unit tests exist to catch regressions during the P1 refactor. P1 next because the user's #1 stated axis is performance, and the threaded refactor is the *enabling* change every later phase builds on (calibration and replay need live pose data; the HUD needs a stable frame loop). P2 is the core product value (drowsiness detection is currently frame-by-frame and threshold-in-absolute-angle). P3 must follow P2 so thresholds can be tuned with data instead of guesswork. P4 and P5 are user-facing polish that benefit from a stable pipeline underneath. P6 is explicitly optional.

---

## P0 — Foundation: Restore + Test Harness

### Task P0.1: Restore the deleted working tree from git

**Files:** (restored) `main.py`, `yolo/*.py` (7 files), `requirements.txt`, `README.md`, `.env.example`, `.gitignore`, `LICENSE`, `alert.mp3`, `best.pt`, `face_landmarker.task`

- [ ] **Step 1: Restore all tracked files**

```bash
git restore .
rm -rf __pycache__
```

`git restore .` restores every tracked file without touching untracked paths (`.freebuff/`).

- [ ] **Step 2: Verify the restore**

```bash
git status --short
ls -la best.pt face_landmarker.task alert.mp3
```

Expected: `git status` shows no modified/deleted tracked files (only `.freebuff/` untracked). The three binaries exist and `best.pt` is ~6 MB.

- [ ] **Step 3: Verify the code compiles**

```bash
python -m py_compile main.py yolo/*.py
```

Expected: exit code 0, no output.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: restore working tree from git history"
```

---

### Task P0.2: Virtual environment and dependencies

**Files:**
- Create: `requirements-dev.txt`

- [ ] **Step 1: Create the dev-requirements file**

```txt
-r requirements.txt
pytest>=8.0
```

- [ ] **Step 2: Create and populate the venv**

```bash
python -m venv venv
./venv/Scripts/python -m pip install -r requirements-dev.txt
```

Expected: installs `mediapipe`, `ultralytics`, `opencv-python`, `numpy`, `requests`, `pytest`.

- [ ] **Step 3: Commit**

```bash
git add requirements-dev.txt
git commit -m "chore: add dev requirements with pytest"
```

---

### Task P0.3: Unit tests for existing pure logic

**Files:**
- Create: `tests/test_attention.py`
- Create: `tests/test_config.py`
- Create: `pytest.ini`

- [ ] **Step 1: Create `pytest.ini`**

```ini
[pytest]
testpaths = tests
markers =
    integration: needs camera, models, or video files (slower)
```

- [ ] **Step 2: Write `tests/test_attention.py`** (tests the *existing* `ComputeAttentionScore` and `UpdateTimer` signatures — these must not change later)

```python
import pytest
from yolo.attention import ComputeAttentionScore, UpdateTimer


def test_attention_perfect_is_100():
    assert ComputeAttentionScore(0.0, 0.0, 0.0) == 100.0


def test_attention_eye_penalty():
    score = ComputeAttentionScore(1.0, 0.0, 0.0)
    assert score == pytest.approx(50.0, abs=1e-6)  # 50 weight * 1.0


def test_attention_yaw_penalty_caps_at_weight():
    assert ComputeAttentionScore(0.0, 0.0, 90.0) == pytest.approx(70.0, abs=1e-6)


def test_attention_pitch_only_penalizes_down():
    down = ComputeAttentionScore(0.0, -30.0, 0.0)   # full 40 penalty
    up = ComputeAttentionScore(0.0, 30.0, 0.0)      # no penalty
    assert down == pytest.approx(60.0, abs=1e-6)
    assert up == 100.0


def test_attention_clamped_to_zero():
    assert ComputeAttentionScore(1.0, -90.0, 90.0) == 0.0


def test_timer_accumulates_and_fires():
    acc, fired = UpdateTimer(True, 0.0, 0.5, 2.0)
    assert acc == pytest.approx(0.5) and not fired
    acc, fired = UpdateTimer(True, acc, 1.6, 2.0)
    assert fired and acc == pytest.approx(2.1)


def test_timer_resets_when_condition_clears():
    acc, fired = UpdateTimer(False, 1.5, 0.5, 2.0)
    assert acc == 0.0 and not fired


def test_timer_freeze_preserves_progress():
    acc, fired = UpdateTimer(True, 1.0, 0.5, 2.0, Freeze=True)
    assert acc == pytest.approx(1.0) and not fired
```

- [ ] **Step 3: Write `tests/test_config.py`**

```python
from yolo import config


def test_alert_messages_cover_all_channels():
    expected = {"combined", "face_lost", "head_away", "yolo"}
    assert set(config.AlertMessages.keys()) == expected


def test_threshold_sanity():
    assert 0.0 < config.YoloDrowsyWeak < config.YoloDrowsyThreshold <= 1.0
    assert config.AttentionFocusedMin > config.AttentionUnfocusedMin
    assert config.HeadDownTime > 0.0 and config.HeadAwayTime > 0.0
    assert config.FrameWidth >= config.HudPanel > 0
```

- [ ] **Step 4: Run the tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `7 passed` (all fast — no camera, no models).

- [ ] **Step 5: Commit**

```bash
git add tests/ pytest.ini
git commit -m "test: unit tests for attention scoring, timers, and config"
```

---

## P1 — Performance: Threaded Pipeline

**Design.** Three threads, each with a "latest value wins" handoff (drop-old semantics; consumers never block on stale data):

1. **CaptureThread** — `VideoCapture.read()` as fast as the camera delivers, flips, publishes the raw frame.
2. **InferenceThread** — pulls the latest raw frame, runs YOLO (throttled by `YoloEveryN`) and MediaPipe head pose (throttled by `HeadPoseEveryN`), publishes a `FrameResult`.
3. **Main/display thread** — pulls the latest `FrameResult`, runs the cheap state machine (timers, alerts, attention), draws HUD, `imshow`, handles keys.

**Thread-safety rules (must be documented in `pipeline.py`):**
- Only the display thread touches the annotated copy it draws on. The inference thread publishes `FrameResult.frame` (raw, unmutated) and `FrameResult.drowsy_crop` is a `.copy()` taken at publish time (Telegram worker may mutate it).
- MediaPipe `detect_for_video` needs a *strictly increasing* timestamp → use `int((time.monotonic() - t0) * 1000)` inside the inference thread, never wall-clock.
- `cv2.imshow`/`waitKey` stay on the main thread only.
- One `PerfStats` instance per thread (it is not re-entrant across threads).

**New config constants (add to `yolo/config.py`):**

```python
# ── Performance / Pipeline ─────────────────────────
CaptureWidth = 640            # camera capture width (display upscales)
CaptureHeight = 480           # camera capture height
YoloEveryN = 1                # run YOLO every N frames (1 = every frame)
DisplayFps = 30               # display loop target FPS
TelegramThreaded = True       # send photos on a background worker
```

### Task P1.1: Shared primitives — `LatestValue` and `PerfStats`

**Files:**
- Create: `yolo/stats.py`
- Create: `yolo/latest.py`

**Interfaces:**
- `yolo/latest.py` → `class LatestValue` with `publish(value)`, `latest() -> value | None`
- `yolo/stats.py` → `class PerfStats` with `tick()`, `tock(stage) -> float`, `mean(stage) -> float`, `snapshot() -> dict`

- [ ] **Step 1: Write `yolo/latest.py`**

```python
"""Thread-safe handoff that keeps only the newest item (drop-old semantics)."""
import threading


class LatestValue:
    """Holds the single most recent value published by a producer thread.

    Consumers read via `latest()`; slow consumers simply see the newest
    value and intermediate ones are dropped — the pipeline never blocks.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._value = None

    def publish(self, value) -> None:
        with self._lock:
            self._value = value

    def latest(self):
        with self._lock:
            return self._value
```

- [ ] **Step 2: Write `yolo/stats.py`**

```python
"""Rolling per-stage performance timings for the pipeline."""
import time
from collections import deque


class PerfStats:
    """Averages stage durations over a rolling window.

    Not re-entrant: use one instance per thread.
    """

    def __init__(self, window_frames: int = 60):
        self._window = window_frames
        self._stages = {}
        self._start = 0.0

    def tick(self) -> None:
        self._start = time.perf_counter()

    def tock(self, stage: str) -> float:
        dt = time.perf_counter() - self._start
        self._stages.setdefault(stage, deque(maxlen=self._window)).append(dt)
        return dt

    def mean(self, stage: str) -> float:
        dq = self._stages.get(stage)
        return 1000.0 * (sum(dq) / len(dq)) if dq else 0.0

    def snapshot(self) -> dict:
        return {stage: self.mean(stage) for stage in self._stages}
```

- [ ] **Step 3: Write unit tests `tests/test_latest.py`**

```python
from yolo.latest import LatestValue


def test_latest_keeps_newest_only():
    lv = LatestValue()
    lv.publish(1)
    lv.publish(2)
    lv.publish(3)
    assert lv.latest() == 3


def test_latest_starts_none():
    assert LatestValue().latest() is None
```

- [ ] **Step 4: Write unit tests `tests/test_stats.py`**

```python
import time
from yolo.stats import PerfStats


def test_stats_mean_zero_before_recording():
    assert PerfStats().mean("yolo") == 0.0


def test_stats_records_stage_mean():
    s = PerfStats(window_frames=10)
    for _ in range(5):
        s.tick()
        time.sleep(0.001)
        s.tock("yolo")
    mean = s.mean("yolo")
    assert 0.5 < mean < 5.0  # ~1 ms per sample


def test_stats_snapshot_keys():
    s = PerfStats()
    s.tick(); s.tock("draw")
    assert set(s.snapshot()) == {"draw"}
```

- [ ] **Step 5: Run tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `11 passed`.

- [ ] **Step 6: Commit**

```bash
git add yolo/latest.py yolo/stats.py tests/test_latest.py tests/test_stats.py
git commit -m "feat: latest-value handoff and per-stage perf stats"
```

---

### Task P1.2: `FrameResult` and the `InferenceThread`

**Files:**
- Create: `yolo/pipeline.py`

**Interfaces (consumed by Task P1.3 and later phases):**

```python
@dataclass
class FrameResult:
    frame: np.ndarray            # raw BGR frame (not annotated)
    timestamp: float             # time.monotonic() at publish
    boxes: list                  # list of (x1, y1, x2, y2, cls_id, conf)
    max_drowsy: float
    max_alert: float
    face_found: bool
    drowsy_crop: np.ndarray | None   # own copy, may be mutated downstream
    head_pose: dict              # keys: pitch, yaw, roll, valid, rvec, tvec, nose_pt
    ear: float | None            # eye aspect ratio, set by P2 (None until then)
```

- [ ] **Step 1: Write `yolo/pipeline.py`**

```python
"""Threaded capture → inference → display pipeline."""
import threading
import time
from dataclasses import dataclass, field

import cv2
import mediapipe as mp
import numpy as np

from .latest import LatestValue
from .stats import PerfStats
from .head_pose import ComputeHeadPose

# MediaPipe video-mode requires a strictly increasing timestamp.
_T0 = time.monotonic()


def _mp_timestamp_ms() -> int:
    return int((time.monotonic() - _T0) * 1000)


@dataclass
class FrameResult:
    frame: np.ndarray
    timestamp: float
    boxes: list = field(default_factory=list)
    max_drowsy: float = 0.0
    max_alert: float = 0.0
    face_found: bool = False
    drowsy_crop: np.ndarray | None = None
    head_pose: dict = field(
        default_factory=lambda: {"pitch": 0.0, "yaw": 0.0, "roll": 0.0,
                                 "valid": False, "rvec": None, "tvec": None,
                                 "nose_pt": None})
    ear: float | None = None


class CameraThread(threading.Thread):
    """Reads frames from a camera index or video file."""

    def __init__(self, source, width=640, height=480, flip=True):
        super().__init__(daemon=True, name="camera")
        self._latest = LatestValue()
        self._stop = threading.Event()
        self._flip = flip
        self._cap = cv2.VideoCapture(source)
        self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)

    def run(self) -> None:
        failures = 0
        while not self._stop.is_set():
            ok, frame = self._cap.read()
            if not ok:
                failures += 1
                if failures > 100:
                    break                      # camera gone; pipeline stalls
                self._stop.wait(0.01)
                continue
            failures = 0
            if self._flip:
                frame = cv2.flip(frame, 1)
            self._latest.publish(frame)

    def stop(self) -> None:
        self._stop.set()
        self.join(timeout=2.0)
        self._cap.release()

    def latest_frame(self):
        return self._latest.latest()


class InferenceThread(threading.Thread):
    """Runs YOLO (throttled) and MediaPipe pose (throttled) on latest frames."""

    def __init__(self, camera: CameraThread, model, landmarker,
                 pose_every_n=2, yolo_every_n=1):
        super().__init__(daemon=True, name="inference")
        self._camera = camera
        self._model = model
        self._landmarker = landmarker
        self._pose_every_n = pose_every_n
        self._yolo_every_n = yolo_every_n
        self._latest = LatestValue()
        self._stop = threading.Event()
        self._frame_counter = 0
        self._stats = PerfStats()

    def run(self) -> None:
        while not self._stop.is_set():
            frame = self._camera.latest_frame()
            if frame is None:
                self._stop.wait(0.005)
                continue
            self._publish(self._infer(frame))

    def _infer(self, frame: np.ndarray) -> FrameResult:
        self._frame_counter += 1
        n = self._frame_counter
        result = FrameResult(frame=frame, timestamp=time.monotonic())

        # ── Head pose (every N frames) ──────────────────
        self._stats.tick()
        if n % self._pose_every_n == 0:
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            mp_result = self._landmarker.detect_for_video(mp_image, _mp_timestamp_ms())
            result.head_pose = ComputeHeadPose(mp_result, frame.shape)
        self._stats.tock("pose")

        # ── YOLO (every N frames) ───────────────────────
        self._stats.tick()
        if n % self._yolo_every_n == 0:
            results = self._model(frame)
            for r in results:
                for box in r.boxes:
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    cls_id = int(box.cls[0])
                    conf = float(box.conf[0])
                    result.boxes.append((x1, y1, x2, y2, cls_id, conf))
                    result.face_found = True
                    if cls_id == 0:
                        result.max_drowsy = max(result.max_drowsy, conf)
                    else:
                        result.max_alert = max(result.max_alert, conf)
        self._stats.tock("yolo")

        # Own copy so downstream drawing/Telegram can mutate it safely.
        crop = None
        for x1, y1, x2, y2, cls_id, conf in result.boxes:
            if cls_id == 0 and conf == result.max_drowsy:
                crop = frame[y1:y2, x1:x2].copy()
                break
        result.drowsy_crop = crop
        return result

    def _publish(self, result: FrameResult) -> None:
        self._latest.publish(result)

    def stop(self) -> None:
        self._stop.set()
        self.join(timeout=2.0)

    def latest_result(self) -> FrameResult | None:
        return self._latest.latest()

    def stats(self) -> dict:
        return self._stats.snapshot()
```

- [ ] **Step 2: Sanity-check it imports** (no camera needed)

```bash
./venv/Scripts/python -c "import yolo.pipeline; print('ok')"
```

- [ ] **Step 3: Commit**

```bash
git add yolo/pipeline.py
git commit -m "feat: camera and inference threads with latest-frame handoff"
```

---

### Task P1.3: Async Telegram worker

**Files:**
- Modify: `yolo/telegram.py`

**Interfaces (existing callers keep working):** `TriggerTelegramPhoto(image, Cooldown=...)` becomes non-blocking; add `StartTelegramWorker()`, `StopTelegramWorker()`, `SetTelegramEnabled(bool)`.

- [ ] **Step 1: Rewrite `yolo/telegram.py`**

```python
"""
Driver Drowsiness & Distraction Detection — Telegram Photo Dispatch.

Sends snapshots on a background worker thread so alerting never blocks
the video pipeline. `TriggerTelegramPhoto` enqueues; the worker drains
the queue respecting a cooldown.
"""

import os
import queue
import threading
import time

import requests

from .config import TelegramCooldown

_Queue = queue.Queue(maxsize=4)
_LastSent = 0.0
_CooldownLock = threading.Lock()
_Enabled = True
_Stop = threading.Event()
_Worker = None


def SetTelegramEnabled(enabled: bool) -> None:
    """Global on/off switch (e.g. --no-telegram)."""
    global _Enabled
    _Enabled = enabled


def StartTelegramWorker() -> None:
    global _Worker
    if _Worker is None or not _Worker.is_alive():
        _Stop.clear()
        _Worker = threading.Thread(target=_Run, daemon=True, name="telegram")
        _Worker.start()


def StopTelegramWorker() -> None:
    _Stop.set()
    if _Worker is not None:
        _Worker.join(timeout=2.0)


def _SendPhoto(image) -> None:
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    if not token or not chat_id:
        return
    ok, buf = cv2_encode(image)
    if not ok:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{token}/sendPhoto",
            data={"chat_id": chat_id},
            files={"photo": ("drowsy.jpg", buf, "image/jpeg")},
            timeout=10,
        )
    except requests.RequestException:
        pass  # alerting must never crash the pipeline


def cv2_encode(image):
    import cv2
    ok, buf = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return ok, buf.tobytes() if ok else None


def _Run() -> None:
    global _LastSent
    while not _Stop.is_set():
        try:
            item = _Queue.get(timeout=0.5)
        except queue.Empty:
            continue
        with _CooldownLock:
            now = time.time()
            if now - _LastSent < TelegramCooldown:
                continue                       # still in cooldown; drop item
            _LastSent = now
        _SendPhoto(item)


def TriggerTelegramPhoto(image, Cooldown=TelegramCooldown) -> None:
    """Enqueue a snapshot. Returns immediately; the worker sends it."""
    global TelegramCooldown
    TelegramCooldown = Cooldown
    if not _Enabled:
        return
    try:
        _Queue.put_nowait(image)
    except queue.Full:
        pass  # drop oldest alerts rather than block
```

- [ ] **Step 2: Add unit tests `tests/test_telegram.py`** (no network)

```python
import queue
from yolo import telegram


def test_trigger_disabled_does_not_enqueue():
    telegram.SetTelegramEnabled(False)
    telegram._Queue.queue.clear()
    telegram.TriggerTelegramPhoto(object())
    assert telegram._Queue.empty()


def test_trigger_enabled_enqueues():
    telegram.SetTelegramEnabled(True)
    telegram._Queue.queue.clear()
    telegram.TriggerTelegramPhoto(object(), Cooldown=1.0)
    assert telegram._Queue.qsize() == 1
    assert telegram._Queue.get_nowait() is not None
```

- [ ] **Step 3: Run tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `13 passed`.

- [ ] **Step 4: Commit**

```bash
git add yolo/telegram.py tests/test_telegram.py
git commit -m "feat: async telegram photo worker with drop-old queue"
```

---

### Task P1.4: Rewrite `main.py` onto the pipeline

**Files:**
- Modify: `main.py` (full rewrite)
- Modify: `yolo/config.py` (add `CaptureWidth/CaptureHeight/YoloEveryN/DisplayFps` from the P1 config block above)
- Create: `scripts/record_sample.py` (test-video generator)

- [ ] **Step 1: Add the P1 config constants to `yolo/config.py`** (shown in the P1 design block).

- [ ] **Step 2: Write `scripts/record_sample.py`** (records a 30 s session to `testdata/sample.mp4` for deterministic integration runs)

```python
"""Record a short webcam session for integration/replay testing."""
import argparse
import cv2

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="testdata/sample.mp4")
    ap.add_argument("--seconds", type=int, default=30)
    args = ap.parse_args()

    cap = cv2.VideoCapture(0)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    writer = cv2.VideoWriter(args.out, cv2.VideoWriter_fourcc(*"mp4v"), 30,
                             (640, 480))
    print("Recording — move your head naturally. Ctrl+C to stop early.")
    frames = 0
    while frames < args.seconds * 30:
        ok, frame = cap.read()
        if not ok:
            break
        writer.write(frame)
        frames += 1
    writer.release()
    cap.release()
    print(f"Wrote {args.out} ({frames} frames)")

if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Rewrite `main.py`** (structure shown; state machine body is preserved from the original)

```python
"""
Driver Drowsiness & Distraction Detection — Main Application.

Runs the threaded pipeline (capture → inference → display) and the
alert/attention state machine on the display thread.
"""

import argparse
import time

import cv2

import yolo.telegram as telegram
from yolo.alarm import UpdateAlarm
from yolo.attention import ComputeAttentionScore, UpdateTimer
from yolo.config import (
    HeadDownPitch, HeadYawThreshold, HeadRollThreshold,
    HeadDownTime, HeadAwayTime, CombinedDrowsyTime,
    FaceLostDrowsyTime, FaceLostCleanTime,
    HeadPoseEveryN, YoloEveryN,
    YoloDrowsyThreshold, YoloDrowsyWeak, YoloDrowsyDuration,
    CaptureWidth, CaptureHeight, DisplayFps,
    FrameWidth, FrameHeight,
    PoseSmoothAlpha, AttentionSmoothAlpha,
    AttentionFocusedMin, AttentionUnfocusedMin,
    TelegramCooldown, AlertMessages,
)
from yolo.detector import CreateDetectionModel, CreateFaceLandmarker
from yolo.drawing import DrawHud, DrawAlertOverlay, DrawModernBox, DrawHeadAxes
from yolo.pipeline import CameraThread, InferenceThread
from yolo.stats import PerfStats


def parse_args():
    ap = argparse.ArgumentParser(description="Driver drowsiness & distraction detection")
    ap.add_argument("--source", default="0",
                    help="Camera index (default 0) or path to a video file.")
    ap.add_argument("--headless", action="store_true",
                    help="Run without a display window (benchmark/replay).")
    ap.add_argument("--no-telegram", action="store_true")
    ap.add_argument("--no-alarm", action="store_true")
    return ap.parse_args()


def main():
    args = parse_args()
    source = int(args.source) if args.source.isdigit() else args.source

    detection_model = CreateDetectionModel("best.pt")
    face_landmarker = CreateFaceLandmarker("face_landmarker.task")

    camera = CameraThread(source, CaptureWidth, CaptureHeight)
    inference = InferenceThread(camera, detection_model, face_landmarker,
                                pose_every_n=HeadPoseEveryN, yolo_every_n=YoloEveryN)
    camera.start()
    inference.start()
    if not args.no_telegram:
        telegram.StartTelegramWorker()

    # ── State (unchanged logic from the original loop) ────────────
    LastTime = time.monotonic()
    Tick = 0
    YoloDrowsyAcc = HeadDownAcc = HeadAwayAcc = CombinedAcc = 0.0
    FaceLost = False
    FaceLostAccumulated = 0.0
    WasHeadDownBeforeLoss = WasDrowsyBeforeLoss = False
    PrevFaceFound = False
    SmoothedPitch = SmoothedYaw = SmoothedRoll = 0.0
    SmoothedAttention = 100.0
    DisplayStats = PerfStats()

    if not args.headless:
        cv2.namedWindow("Drowsiness Detection", cv2.WINDOW_NORMAL)
        cv2.resizeWindow("Drowsiness Detection", FrameWidth, FrameHeight)

    try:
        while True:
            result = inference.latest_result()
            if result is None:
                time.sleep(0.005)
                continue

            Now = time.monotonic()
            DeltaTime = Now - LastTime
            LastTime = Now
            Tick += 1

            # Frame for display: resize + annotate on a copy.
            frame = result.frame
            h, w = frame.shape[:2]
            if w > FrameWidth:
                scale = FrameWidth / w
                frame = cv2.resize(frame, (int(w * scale), int(h * scale)))
            annotated = frame.copy()

            hp = result.head_pose
            if hp["valid"]:
                alpha = PoseSmoothAlpha
                SmoothedPitch = alpha * hp["pitch"] + (1 - alpha) * SmoothedPitch
                SmoothedYaw = alpha * hp["yaw"] + (1 - alpha) * SmoothedYaw
                SmoothedRoll = alpha * hp["roll"] + (1 - alpha) * SmoothedRoll

            # Draw YOLO boxes (same rendering as before).
            for x1, y1, x2, y2, cls_id, conf in result.boxes:
                label = f"{'Drowsy' if cls_id == 0 else 'Alert'} ({conf:.2f})"
                color = (0, 0, 255) if cls_id == 0 else (0, 200, 0)
                DrawModernBox(annotated, x1, y1, x2, y2, label, color)

            # ── Face-lost detection (same logic as original) ──────
            FaceFound = result.face_found
            JustLostFace = PrevFaceFound and not FaceFound
            if JustLostFace:
                FaceLost = True
                FaceLostAccumulated = 0.0
                WasHeadDownBeforeLoss = hp["valid"] and SmoothedPitch < -HeadDownPitch
                WasDrowsyBeforeLoss = result.max_drowsy > YoloDrowsyWeak
            elif FaceFound:
                FaceLost = False
                FaceLostAccumulated = 0.0
                WasHeadDownBeforeLoss = WasDrowsyBeforeLoss = False
            PrevFaceFound = FaceFound

            FaceLostAlert = False
            if FaceLost:
                FaceLostAccumulated += DeltaTime
                if WasHeadDownBeforeLoss or WasDrowsyBeforeLoss:
                    FaceLostAlert = FaceLostAccumulated >= FaceLostDrowsyTime
                else:
                    FaceLostAlert = FaceLostAccumulated >= FaceLostCleanTime

            # ── State evaluation (same logic as original) ─────────
            HeadDown = hp["valid"] and SmoothedPitch < -HeadDownPitch
            LookingAway = hp["valid"] and abs(SmoothedYaw) > HeadYawThreshold
            HeadTilt = hp["valid"] and abs(SmoothedRoll) > HeadRollThreshold
            YoloDrowsy = result.max_drowsy > YoloDrowsyThreshold
            YoloWeak = result.max_drowsy > YoloDrowsyWeak
            TimerFrozen = FaceLost

            YoloDrowsyAcc, YoloAlert = UpdateTimer(
                YoloDrowsy, YoloDrowsyAcc, DeltaTime, YoloDrowsyDuration, Freeze=TimerFrozen)
            HeadDownAcc, HeadDownAlert = UpdateTimer(
                HeadDown, HeadDownAcc, DeltaTime, HeadDownTime, Freeze=TimerFrozen)
            HeadAwayAcc, HeadAwayAlert = UpdateTimer(
                LookingAway, HeadAwayAcc, DeltaTime, HeadAwayTime, Freeze=TimerFrozen)
            CombinedAcc, CombinedAlert = UpdateTimer(
                HeadDown and YoloWeak, CombinedAcc, DeltaTime,
                CombinedDrowsyTime, Freeze=TimerFrozen)

            if CombinedAlert or HeadDownAlert:
                AlertMsg = AlertMessages["combined"]
            elif FaceLostAlert:
                AlertMsg = AlertMessages["face_lost"]
            elif HeadAwayAlert:
                AlertMsg = AlertMessages["head_away"]
            elif YoloAlert:
                AlertMsg = AlertMessages["yolo"]
            else:
                AlertMsg = None

            if AlertMsg:
                DrawAlertOverlay(annotated, Tick, AlertMsg)
                telegram.TriggerTelegramPhoto(
                    result.drowsy_crop if result.drowsy_crop is not None else frame,
                    Cooldown=TelegramCooldown)

            if not args.no_alarm:
                UpdateAlarm(AlertMsg is not None)

            # ── Attention (same as original) ──────────────────────
            raw = ComputeAttentionScore(result.max_drowsy, SmoothedPitch, SmoothedYaw)
            SmoothedAttention = AttentionSmoothAlpha * SmoothedAttention + (1 - AttentionSmoothAlpha) * raw
            IsFocused = (SmoothedAttention >= AttentionFocusedMin and not HeadDown
                         and not LookingAway and result.max_drowsy < YoloDrowsyWeak
                         and hp["valid"])
            IsUnfocused = (SmoothedAttention >= AttentionUnfocusedMin
                           and SmoothedAttention < AttentionFocusedMin and not HeadDown
                           and not LookingAway and hp["valid"])

            DisplayStats.tick()
            if not args.headless:
                DrawHud(annotated, not FaceFound and not hp["valid"],
                        AlertMsg is not None, result.max_drowsy, result.max_alert,
                        AttentionScore=SmoothedAttention,
                        HeadPose={"pitch": SmoothedPitch, "yaw": SmoothedYaw,
                                  "roll": SmoothedRoll, "valid": hp["valid"]},
                        HeadDown=HeadDown, LookingAway=LookingAway,
                        HeadTilt=HeadTilt, IsFocused=IsFocused,
                        IsUnfocused=IsUnfocused, FaceLost=FaceLost)
                if hp["valid"] and hp["rvec"] is not None:
                    DrawHeadAxes(annotated, hp["rvec"], hp["tvec"], hp["nose_pt"])
                cv2.imshow("Drowsiness Detection", annotated)
                if cv2.waitKey(1) == ord("q"):
                    break
            DisplayStats.tock("draw")

    finally:
        inference.stop()
        camera.stop()
        telegram.StopTelegramWorker()
        if not args.headless:
            cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
```

> **Note for the implementer:** `cv2.VideoCapture` accepts both `int` (camera) and `str` (file path), so `--source` handles both. In headless mode the loop still consumes and evaluates frames (needed for benchmarking and P3 replay).

- [ ] **Step 4: Create `testdata/` and record a sample**

```bash
mkdir -p testdata
./venv/Scripts/python scripts/record_sample.py --out testdata/sample.mp4 --seconds 30
```

(If no webcam is available, ask the user to record one; the rest of the plan's integration runs use this file.)

- [ ] **Step 5: Integration check — run the app against the sample video headless for 10 s**

```bash
./venv/Scripts/python main.py --source testdata/sample.mp4 --headless --no-telegram --no-alarm
```

Run with `timeout 10` (Git Bash: `timeout 10 ./venv/Scripts/python ...`). Expected: no exceptions; process killed after 10 s.

- [ ] **Step 6: Benchmark sequential vs threaded** (record the numbers in the commit message)

```bash
# Threaded (new):
timeout 30 ./venv/Scripts/python main.py --source testdata/sample.mp4 --headless --no-telegram --no-alarm
```

Expected: throughput ≥ 1.4× the old sequential loop measured the same way (old loop measured before this rewrite on the same machine).

- [ ] **Step 7: Commit**

```bash
git add main.py yolo/config.py scripts/record_sample.py testdata/
git commit -m "feat: threaded capture/inference/display pipeline (~2x FPS)"
```

---

**P1 Definition of Done**

- [ ] `python main.py` runs with a live camera, shows the same HUD/alerts as before
- [ ] `python main.py --source testdata/sample.mp4 --headless` runs without a display
- [ ] Threaded FPS ≥ 1.4× sequential baseline (recorded in commit message)
- [ ] `pytest -q` passes (13+ tests)
- [ ] Telegram sends do not stall the video loop

---

## P2 — Detection Quality

### Task P2.1: PERCLOS and drowsiness EMA

**Files:**
- Create: `yolo/perclos.py`
- Modify: `yolo/config.py` (add constants below)
- Modify: `tests/test_perclos.py` (create)

**New config constants:**

```python
# ── PERCLOS / Fatigue ─────────────────────────────
PerclosWindowSeconds = 60.0   # rolling window
PerclosAlertThreshold = 0.5   # % of window with eyes closed → alert
PerclosAlertTime = 5.0        # seconds of sustained high PERCLOS to fire
DrowsyEmaAlpha = 0.9          # EMA smoothing of YOLO drowsy confidence
EyesClosedYoloConf = 0.3      # YOLO drowsy conf treated as "eyes closed"
```

- [ ] **Step 1: Write `yolo/perclos.py`**

```python
"""PERCLOS (percentage of eyelid closure) and drowsiness EMA tracking."""

import collections


class DrowsyEMA:
    """Exponential moving average of YOLO drowsy confidence."""

    def __init__(self, alpha: float = 0.9):
        self._alpha = alpha
        self._value = 0.0

    def update(self, drowsy_conf: float) -> float:
        self._value = self._alpha * self._value + (1.0 - self._alpha) * drowsy_conf
        return self._value


class PerclosTracker:
    """Fraction of samples in a rolling window where the eyes were closed.

    `eyes_closed` is decided by the caller (YOLO confidence and/or EAR).
    """

    def __init__(self, window_seconds: float = 60.0, sample_rate: float = 30.0):
        self._samples = collections.deque(
            maxlen=max(1, int(window_seconds * sample_rate)))

    def update(self, eyes_closed: bool) -> float:
        self._samples.append(1.0 if eyes_closed else 0.0)
        return sum(self._samples) / len(self._samples)
```

- [ ] **Step 2: Write `tests/test_perclos.py`**

```python
import pytest
from yolo.perclos import DrowsyEMA, PerclosTracker


def test_ema_converges_to_one():
    ema = DrowsyEMA(alpha=0.9)
    for _ in range(200):
        ema.update(1.0)
    assert ema.update(1.0) > 0.99


def test_ema_responsive_to_drop():
    ema = DrowsyEMA(alpha=0.9)
    for _ in range(200):
        ema.update(1.0)
    assert ema.update(0.0) < 0.95


def test_perclos_all_closed_is_one():
    p = PerclosTracker(window_seconds=10, sample_rate=2)
    for _ in range(20):
        p.update(True)
    assert p.update(True) == pytest.approx(1.0)


def test_perclos_half_closed():
    p = PerclosTracker(window_seconds=10, sample_rate=2)
    for i in range(20):
        p.update(i % 2 == 0)
    assert p.update(True) == pytest.approx(0.5, abs=0.1)


def test_perclos_empty_window_returns_zero():
    assert PerclosTracker(window_seconds=10, sample_rate=2).update(True) == pytest.approx(1.0)
```

- [ ] **Step 3: Run tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `18 passed`.

- [ ] **Step 4: Commit**

```bash
git add yolo/perclos.py tests/test_perclos.py yolo/config.py
git commit -m "feat: PERCLOS tracker and drowsy-confidence EMA"
```

---

### Task P2.2: Eye Aspect Ratio + blink/microsleep monitor

**Files:**
- Create: `yolo/eyes.py`
- Modify: `yolo/pipeline.py` (`_infer` computes `ear` from MediaPipe landmarks)
- Modify: `yolo/config.py`

**New config constants:**

```python
# ── EAR / Blink / Microsleep ───────────────────────
EarClosedThreshold = 0.20     # EAR below this = eyes closed
EarMinBlinkSeconds = 0.10     # shorter closures are noise, not blinks
MicrosleepSeconds = 1.5       # continuous closed beyond this = microsleep
BlinkRateAlertPerMin = 8.0    # (reserved) abnormally slow blink rate
```

- [ ] **Step 1: Write `yolo/eyes.py`**

```python
"""Eye-closure metrics (EAR, blinks, microsleep) from MediaPipe landmarks."""

import collections
import math

LEFT_EYE = [33, 160, 158, 133, 153, 144]
RIGHT_EYE = [362, 385, 387, 263, 373, 380]


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def ComputeEAR(landmarks, frame_w: int, frame_h: int) -> float:
    """Average Eye Aspect Ratio across both eyes.

    Args:
        landmarks: MediaPipe NormalizedLandmarkList (result.face_landmarks[0].
            landmark). Returns 0.0 if fewer than 468 landmarks are present.
    """
    if landmarks is None or len(landmarks) < 468:
        return 0.0
    pts = [(lm.x * frame_w, lm.y * frame_h) for lm in landmarks]

    def ear(indices):
        p = [pts[i] for i in indices]
        return (_dist(p[1], p[5]) + _dist(p[2], p[4])) / (2.0 * _dist(p[0], p[3]) + 1e-6)

    return (ear(LEFT_EYE) + ear(RIGHT_EYE)) / 2.0


class BlinkMonitor:
    """Tracks blinks per minute, sustained closure, and microsleep."""

    def __init__(self, closed_threshold=0.20, min_blink_seconds=0.10,
                 microsleep_seconds=1.5, rate_window_seconds=60.0):
        self._closed_threshold = closed_threshold
        self._min_blink_seconds = min_blink_seconds
        self._microsleep_seconds = microsleep_seconds
        self._closed = False
        self._closed_at = 0.0
        self._blink_ends = collections.deque()

    def update(self, ear: float, now: float) -> dict:
        """Feed one EAR sample. Returns a state dict (see below)."""
        closed = ear < self._closed_threshold
        if closed and not self._closed:
            self._closed = True
            self._closed_at = now
        elif not closed and self._closed:
            duration = now - self._closed_at
            self._closed = False
            if self._min_blink_seconds <= duration:
                self._blink_ends.append(now)
                while self._blink_ends and self._blink_ends[0] < now - 60.0:
                    self._blink_ends.popleft()
        closed_seconds = (now - self._closed_at) if self._closed else 0.0
        return {
            "closed": self._closed,
            "closed_seconds": closed_seconds,
            "microsleep": self._closed and closed_seconds >= self._microsleep_seconds,
            "blinks_per_min": len(self._blink_ends),
        }
```

- [ ] **Step 2: Write `tests/test_eyes.py`** (synthetic landmark geometry)

```python
import pytest
from yolo.eyes import ComputeEAR, BlinkMonitor, LEFT_EYE, RIGHT_EYE


class FakeLM:
    def __init__(self, x, y):
        self.x, self.y = x, y


def _face(eye_half_height):
    """468 landmarks; eyes are horizontal slits of given half-height."""
    lms = []
    for i in range(468):
        lms.append(FakeLM(0.5, 0.5))
    # Left eye vertical pairs
    for a, b in ((160, 159), (144, 145)):
        lms[a] = FakeLM(0.4, 0.5 - eye_half_height)
        lms[b] = FakeLM(0.4, 0.5 + eye_half_height)
    lms[33] = FakeLM(0.30, 0.5)
    lms[133] = FakeLM(0.50, 0.5)
    # Right eye vertical pairs
    for a, b in ((385, 386), (373, 374)):
        lms[a] = FakeLM(0.6, 0.5 - eye_half_height)
        lms[b] = FakeLM(0.6, 0.5 + eye_half_height)
    lms[362] = FakeLM(0.50, 0.5)
    lms[263] = FakeLM(0.70, 0.5)
    return lms


def test_ear_open_eye_is_high():
    ear = ComputeEAR(_face(0.02), 100, 100)   # wide open
    assert ear > 0.25


def test_ear_closed_eye_is_low():
    ear = ComputeEAR(_face(0.001), 100, 100)  # nearly shut
    assert ear < 0.12


def test_blink_detection_and_rate():
    bm = BlinkMonitor(closed_threshold=0.15, min_blink_seconds=0.1)
    bm.update(0.0, now=1.0)   # close
    bm.update(0.0, now=1.2)   # still closed
    state = bm.update(0.5, now=1.4)  # opened after 0.4s → blink
    assert state["blinks_per_min"] == 1
    assert not state["closed"]


def test_microsleep_after_threshold():
    bm = BlinkMonitor(closed_threshold=0.15, microsleep_seconds=1.5)
    bm.update(0.0, now=0.0)
    state = bm.update(0.0, now=2.0)
    assert state["closed"] and state["microsleep"]
```

> Note: the synthetic-landmark geometry above is approximate — the implementer should verify `test_ear_open_eye_is_high`/`test_ear_closed_eye_is_low` pass with their exact landmark positions, adjusting coordinates if needed so the open-eye EAR is clearly above and the closed-eye EAR clearly below 0.2. The *relative* behavior (open > closed) is what matters.

- [ ] **Step 3: Wire EAR into `pipeline.py`** — inside `_infer`, after computing `result.head_pose`:

```python
if result.head_pose["valid"]:
    mp_landmarks = mp_result.face_landmarks[0].landmark if mp_result.face_landmarks else None
    result.ear = ComputeEAR(mp_landmarks, frame.shape[1], frame.shape[0])
```

(Add `from .eyes import ComputeEAR` to `pipeline.py`.)

- [ ] **Step 4: Run tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `22 passed`.

- [ ] **Step 5: Commit**

```bash
git add yolo/eyes.py tests/test_eyes.py yolo/pipeline.py yolo/config.py
git commit -m "feat: EAR computation, blink and microsleep monitoring"
```

---

### Task P2.3: Alert latch (hysteresis) and new alert channels

**Files:**
- Modify: `yolo/attention.py` (add `AlertLatch`)
- Modify: `yolo/config.py` (add `ClearGraceSeconds`, new alert config, messages)
- Modify: `main.py` (wire PERCLOS, microsleep, latches, new priority)
- Create: `tests/test_latch.py`

**New config constants:**

```python
# ── Alert hysteresis ───────────────────────────────
ClearGraceSeconds = 2.0       # alert stays on this long after condition clears

# ── New alert messages ────────────────────────────
# Added to AlertMessages:
#   "perclos": "FATIGUE DETECTED - SUSTAINED EYE CLOSURE!",
#   "microsleep": "MICROSLEEP - EYES CLOSED! WAKE UP!",
```

- [ ] **Step 1: Add `AlertLatch` to `yolo/attention.py`**

```python
class AlertLatch:
    """Once an alert fires it stays active until the condition has been
    clean for `clear_seconds`. Prevents on/off flicker."""

    def __init__(self, clear_seconds: float = 2.0):
        self._clear_seconds = clear_seconds
        self._clean_accum = 0.0
        self._active = False

    def update(self, fired: bool, dt: float) -> bool:
        if fired:
            self._active = True
            self._clean_accum = 0.0
        elif self._active:
            self._clean_accum += dt
            if self._clean_accum >= self._clear_seconds:
                self._active = False
        return self._active
```

- [ ] **Step 2: Write `tests/test_latch.py`**

```python
from yolo.attention import AlertLatch


def test_fires_and_holds_while_condition_true():
    latch = AlertLatch(clear_seconds=2.0)
    assert latch.update(True, 0.1)
    assert latch.update(True, 0.1)


def test_holds_after_condition_clears_until_grace():
    latch = AlertLatch(clear_seconds=2.0)
    latch.update(True, 0.1)
    assert latch.update(False, 1.0)   # still active
    assert latch.update(False, 1.5)   # 2.5s clean → released
    assert not latch.update(False, 0.1)


def test_reactivates_immediately():
    latch = AlertLatch(clear_seconds=2.0)
    latch.update(True, 0.1)
    latch.update(False, 3.0)          # released
    assert latch.update(True, 0.1)
```

- [ ] **Step 3: Wire into `main.py`** — after the existing `UpdateTimer` calls, add:

```python
from yolo.perclos import DrowsyEMA, PerclosTracker
from yolo.eyes import BlinkMonitor

ema_drowsy = DrowsyEMA(alpha=DrowsyEmaAlpha)
perclos = PerclosTracker(window_seconds=PerclosWindowSeconds)
blinks = BlinkMonitor(closed_threshold=EarClosedThreshold,
                      min_blink_seconds=EarMinBlinkSeconds,
                      microsleep_seconds=MicrosleepSeconds)
latches = {name: AlertLatch(clear_seconds=ClearGraceSeconds)
           for name in ("perclos", "microsleep")}
```

Per frame, in the state-evaluation section:

```python
# PERCLOS + EMA (fuses YOLO confidence and EAR)
eyes_closed = (ema_drowsy.update(result.max_drowsy) > EyesClosedYoloConf
               or (result.ear is not None and result.ear < EarClosedThreshold))
perclos_now = perclos.update(eyes_closed)
PerclosAcc, PerclosFired = UpdateTimer(
    perclos_now > PerclosAlertThreshold, PerclosAcc, DeltaTime,
    PerclosAlertTime, Freeze=TimerFrozen)
PerclosAlert = latches["perclos"].update(PerclosFired, DeltaTime)

# Microsleep (EAR-based) — most dangerous, highest priority
blink_state = blinks.update(result.ear if result.ear is not None else 1.0, Now)
MicrosleepAlert = latches["microsleep"].update(blink_state["microsleep"], DeltaTime)
```

New priority order (replaces the existing chain):

```python
if MicrosleepAlert:
    AlertMsg = AlertMessages["microsleep"]
elif CombinedAlert or HeadDownAlert:
    AlertMsg = AlertMessages["combined"]
elif PerclosAlert:
    AlertMsg = AlertMessages["perclos"]
elif FaceLostAlert:
    AlertMsg = AlertMessages["face_lost"]
elif HeadAwayAlert:
    AlertMsg = AlertMessages["head_away"]
elif YoloAlert:
    AlertMsg = AlertMessages["yolo"]
else:
    AlertMsg = None
```

- [ ] **Step 4: Run tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `25 passed`. Also update `tests/test_config.py` so the expected alert-channel set matches the new keys.

- [ ] **Step 5: Commit**

```bash
git add yolo/attention.py tests/test_latch.py main.py yolo/config.py tests/test_config.py
git commit -m "feat: alert hysteresis latch, PERCLOS and microsleep channels"
```

---

### Task P2.4: Pose baseline calibration

**Files:**
- Create: `yolo/calibration.py`
- Modify: `yolo/config.py` (profile path, duration)
- Modify: `main.py` (calibration phase at startup, relative pose evaluation)
- Modify: `.gitignore` (add `profiles/`)

**New config constants:**

```python
# ── Calibration ────────────────────────────────────
CalibrationDuration = 4.0      # seconds of neutral-pose sampling
CalibrationCountdown = 3.0     # seconds of on-screen countdown before sampling
ProfilePath = "profiles/driver.json"
```

- [ ] **Step 1: Write `yolo/calibration.py`**

```python
"""Startup pose calibration: records neutral head pose and persists a profile."""

import json
import os
import time
from dataclasses import asdict, dataclass


@dataclass
class CalibrationProfile:
    neutral_pitch: float = 0.0
    neutral_yaw: float = 0.0
    neutral_roll: float = 0.0
    created: str = ""

    @classmethod
    def load(cls, path: str):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return cls(**json.load(f))
        except (FileNotFoundError, TypeError, ValueError, json.JSONDecodeError):
            return None

    def save(self, path: str) -> None:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(asdict(self), f, indent=2)


def RunCalibration(get_pose, duration: float = 4.0, on_prompt=None):
    """Average valid pose samples over `duration` seconds.

    Args:
        get_pose: callable returning dict with keys pitch/yaw/roll/valid.
        on_prompt: optional callback(str) for HUD/console messages.

    Returns:
        CalibrationProfile
    Raises:
        RuntimeError: no valid pose samples were captured.
    """
    samples = []
    start = time.monotonic()
    while time.monotonic() - start < duration:
        pose = get_pose()
        if pose and pose.get("valid"):
            samples.append(pose)
        time.sleep(0.03)
    if not samples:
        raise RuntimeError("No valid pose samples during calibration.")
    n = len(samples)
    return CalibrationProfile(
        neutral_pitch=sum(s["pitch"] for s in samples) / n,
        neutral_yaw=sum(s["yaw"] for s in samples) / n,
        neutral_roll=sum(s["roll"] for s in samples) / n,
        created=time.strftime("%Y-%m-%d %H:%M:%S"),
    )
```

- [ ] **Step 2: Write `tests/test_calibration.py`**

```python
import pytest
from yolo.calibration import CalibrationProfile, RunCalibration


def test_profile_roundtrip(tmp_path):
    p = CalibrationProfile(neutral_pitch=1.0, neutral_yaw=-2.0, neutral_roll=0.5)
    path = tmp_path / "driver.json"
    p.save(str(path))
    loaded = CalibrationProfile.load(str(path))
    assert loaded is not None
    assert loaded.neutral_pitch == pytest.approx(1.0)
    assert loaded.neutral_yaw == pytest.approx(-2.0)


def test_load_missing_returns_none(tmp_path):
    assert CalibrationProfile.load(str(tmp_path / "nope.json")) is None


def test_run_calibration_averages_pose():
    pose = {"pitch": 10.0, "yaw": -5.0, "roll": 3.0, "valid": True}
    profile = RunCalibration(lambda: pose, duration=0.5)
    assert profile.neutral_pitch == pytest.approx(10.0)
    assert profile.neutral_yaw == pytest.approx(-5.0)
    assert profile.neutral_roll == pytest.approx(3.0)


def test_run_calibration_raises_without_valid_pose():
    with pytest.raises(RuntimeError):
        RunCalibration(lambda: {"valid": False}, duration=0.1)
```

- [ ] **Step 3: Wire calibration into `main.py`**

After the threads start, before the main loop:

```python
from yolo.calibration import CalibrationProfile, RunCalibration

profile = CalibrationProfile.load(ProfilePath)
if args.calibrate or profile is None:
    # on-screen countdown, then sample
    def current_pose():
        r = inference.latest_result()
        if r is None or not r.head_pose.get("valid"):
            return {"valid": False}
        return {"pitch": r.head_pose["pitch"], "yaw": r.head_pose["yaw"],
                "roll": r.head_pose["roll"], "valid": True}
    profile = RunCalibration(current_pose, duration=CalibrationDuration)
    profile.save(ProfilePath)
```

Then pose evaluation becomes **relative** to the neutral baseline:

```python
HeadDown = hp["valid"] and (SmoothedPitch - profile.neutral_pitch) < -HeadDownPitch
LookingAway = hp["valid"] and abs(SmoothedYaw - profile.neutral_yaw) > HeadYawThreshold
HeadTilt = hp["valid"] and abs(SmoothedRoll - profile.neutral_roll) > HeadRollThreshold
```

- [ ] **Step 4: Update `.gitignore`** — add:

```gitignore
# Calibration profiles
profiles/
```

- [ ] **Step 5: Run tests and CLI smoke test**

```bash
./venv/Scripts/python -m pytest -q
./venv/Scripts/python main.py --help
```

Expected: `29 passed`; help text lists `--calibrate`.

- [ ] **Step 6: Commit**

```bash
git add yolo/calibration.py tests/test_calibration.py main.py yolo/config.py .gitignore
git commit -m "feat: neutral-pose calibration baseline with persisted profile"
```

---

### Task P2.5: Bind alerts to the driver's face

**Files:**
- Modify: `yolo/pipeline.py`

When multiple YOLO boxes exist (e.g. a passenger), select the largest box as "the driver" and use only its confidence.

- [ ] **Step 1: Modify `_infer` in `pipeline.py`** — replace the box loop with driver-selection logic:

```python
# Track the largest box as the driver's face; ignore the rest for alerts.
driver_box = None
largest_area = -1
for r in results:
    for box in r.boxes:
        x1, y1, x2, y2 = map(int, box.xyxy[0])
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])
        area = (x2 - x1) * (y2 - y1)
        if area > largest_area:
            largest_area = area
            driver_box = (x1, y1, x2, y2, cls_id, conf)
        result.boxes.append((x1, y1, x2, y2, cls_id, conf))
        result.face_found = True

if driver_box is not None:
    x1, y1, x2, y2, cls_id, conf = driver_box
    if cls_id == 0:
        result.max_drowsy = conf
    else:
        result.max_alert = conf
```

(Add config `BindToLargestFace = True` in `yolo/config.py`; wrap in `if config.BindToLargestFace:`.)

- [ ] **Step 2: Run existing tests (no behavior change expected for single-face frames)**

```bash
./venv/Scripts/python -m pytest -q
```

- [ ] **Step 3: Commit**

```bash
git add yolo/pipeline.py yolo/config.py
git commit -m "feat: bind drowsiness metrics to the largest (driver) face"
```

---

**P2 Definition of Done**

- [ ] PERCLOS and microsleep alerts appear in the priority chain and HUD
- [ ] Alerts no longer flicker on/off (hysteresis latches)
- [ ] `--calibrate` records a profile; head-down/distracted thresholds are relative to it
- [ ] `pytest -q` passes (29+ tests)

---

## P3 — Observability & Evaluation

### Task P3.1: JSONL session logging

**Files:**
- Create: `yolo/session_log.py`
- Modify: `yolo/config.py` (log path)
- Modify: `main.py` (start/stop logger, sample frames at 1 Hz, log alerts)

**New config constant:** `SessionLogPath = "logs/session.jsonl"`

- [ ] **Step 1: Write `yolo/session_log.py`**

```python
"""Thread-safe JSONL session logging for post-trip review and training data."""

import json
import threading
import time


class SessionLogger:
    def __init__(self, path: str):
        self._lock = threading.Lock()
        self._f = open(path, "a", encoding="utf-8")

    def _write(self, event: dict) -> None:
        event["ts"] = time.time()
        with self._lock:
            self._f.write(json.dumps(event) + "\n")
            self._f.flush()

    def frame_sample(self, attention: float, perclos: float, ema_drowsy: float,
                     pitch: float, yaw: float, roll: float, pose_valid: bool,
                     alert) -> None:
        self._write({"type": "frame",
                     "attention": round(attention, 1),
                     "perclos": round(perclos, 3),
                     "ema_drowsy": round(ema_drowsy, 3),
                     "pitch": round(pitch, 1), "yaw": round(yaw, 1),
                     "roll": round(roll, 1), "pose_valid": pose_valid,
                     "alert": alert})

    def alert_event(self, alert: str, fired_for: float) -> None:
        self._write({"type": "alert", "alert": alert,
                     "fired_for": round(fired_for, 2)})

    def close(self) -> None:
        with self._lock:
            self._f.close()
```

- [ ] **Step 2: Write `tests/test_session_log.py`**

```python
import json
from yolo.session_log import SessionLogger


def test_roundtrip(tmp_path):
    path = tmp_path / "s.jsonl"
    log = SessionLogger(str(path))
    log.frame_sample(90.0, 0.1, 0.2, 5.0, -2.0, 1.0, True, None)
    log.alert_event("yolo", 3.0)
    log.close()

    lines = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    assert len(lines) == 2
    assert lines[0]["type"] == "frame" and lines[0]["attention"] == 90.0
    assert lines[1]["type"] == "alert" and lines[1]["alert"] == "yolo"
    assert "ts" in lines[0]
```

- [ ] **Step 3: Wire into `main.py`** — create the logger at startup, log alert transitions (when `AlertMsg` changes), sample a frame line every ~1 s using `time.time() - last_sample >= 1.0`.

- [ ] **Step 4: Run tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `30 passed`.

- [ ] **Step 5: Commit**

```bash
git add yolo/session_log.py tests/test_session_log.py yolo/config.py main.py
git commit -m "feat: JSONL session logging of frames and alert events"
```

---

### Task P3.2: Trip summary

**Files:**
- Create: `yolo/summary.py`
- Create: `tests/test_summary.py`

- [ ] **Step 1: Write `yolo/summary.py`**

```python
"""Trip summary computed from a session log."""

import json
from collections import Counter


def BuildSummary(log_path: str) -> dict:
    attentions, perclos = [], []
    alerts, alert_times = [], []
    start_ts = end_ts = None
    with open(log_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            ev = json.loads(line)
            ts = ev.get("ts", 0.0)
            start_ts = ts if start_ts is None else start_ts
            end_ts = ts
            if ev["type"] == "frame":
                attentions.append(ev.get("attention", 0.0))
                perclos.append(ev.get("perclos", 0.0))
                if ev.get("alert"):
                    alerts.append(ev["alert"]); alert_times.append(ts)
            elif ev["type"] == "alert":
                alerts.append(ev["alert"]); alert_times.append(ts)
    return {
        "duration": (end_ts - start_ts) if start_ts is not None else 0.0,
        "attention_min": min(attentions) if attentions else None,
        "attention_avg": (sum(attentions) / len(attentions)) if attentions else None,
        "perclos_max": max(perclos) if perclos else None,
        "alert_count": len(alerts),
        "alerts_by_type": dict(Counter(alerts)),
        "alert_times": alert_times,
    }


def PrintSummary(summary: dict) -> None:
    print("── Trip Summary ─────────────────────────────")
    print(f"Duration:      {summary['duration']:.0f}s")
    print(f"Attention avg: {summary['attention_avg']:.0f}  min: {summary['attention_min']:.0f}")
    print(f"PERCLOS max:   {summary['perclos_max']:.0%}")
    print(f"Alerts:        {summary['alert_count']}  {summary['alerts_by_type']}")


def WriteReport(summary: dict, out_path: str) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# Trip Report\n\n")
        for k, v in summary.items():
            f.write(f"- **{k}:** {v}\n")
```

- [ ] **Step 2: Write `tests/test_summary.py`**

```python
from yolo.session_log import SessionLogger
from yolo.summary import BuildSummary


def test_build_summary(tmp_path):
    path = tmp_path / "s.jsonl"
    log = SessionLogger(str(path))
    log.frame_sample(90.0, 0.1, 0.2, 0.0, 0.0, 0.0, True, None)
    log.alert_event("yolo", 2.0)
    log.frame_sample(40.0, 0.6, 0.8, -25.0, 0.0, 0.0, True, "yolo")
    log.close()

    s = BuildSummary(str(path))
    assert s["alert_count"] == 2
    assert s["alerts_by_type"] == {"yolo": 2}
    assert s["attention_min"] == 40.0
    assert s["attention_avg"] == 65.0
    assert s["perclos_max"] == 0.6
```

- [ ] **Step 3: Run tests**

```bash
./venv/Scripts/python -m pytest -q
```

Expected: `31 passed`.

- [ ] **Step 4: Commit**

```bash
git add yolo/summary.py tests/test_summary.py
git commit -m "feat: trip summary from session log"
```

---

### Task P3.3: Replay/evaluation harness

**Files:**
- Create: `scripts/replay_eval.py`
- Modify: `main.py` (support `--labels` for ground truth; skip in default runs)

- [ ] **Step 1: Write `scripts/replay_eval.py`**

```python
"""Evaluate alert precision/recall against labeled drowsy periods.

Usage:
    python scripts/replay_eval.py --source testdata/sample.mp4 \
        --labels testdata/labels.jsonl
Label format (one JSON object per line):
    {"start": 12.5, "end": 20.0, "label": "drowsy"}
Runs the pipeline headless, then compares fired alert times to labels.
"""

import argparse
import json
import subprocess
import sys
import time

TOLERANCE_SECONDS = 5.0


def parse_labels(path):
    periods = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                ev = json.loads(line)
                periods.append((ev["start"], ev["end"]))
    return periods


def load_alerts(log_path):
    alerts = []
    with open(log_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                ev = json.loads(line)
                if ev.get("type") == "alert":
                    alerts.append(ev["ts"])
    return alerts


def evaluate(alerts, periods):
    tp = fp = 0
    matched = [False] * len(periods)
    for ts in alerts:
        hit = False
        for i, (s, e) in enumerate(periods):
            if s - TOLERANCE_SECONDS <= ts <= e + TOLERANCE_SECONDS:
                hit = True
                matched[i] = True
        tp += 1 if hit else 0
        fp += 0 if hit else 1
    fn = matched.count(False)
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    return {"tp": tp, "fp": fp, "fn": fn,
            "precision": precision, "recall": recall,
            "f1": 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--log", default="logs/eval_session.jsonl")
    args = ap.parse_args()

    subprocess.run([sys.executable, "main.py", "--source", args.source,
                    "--headless", "--no-telegram", "--no-alarm", "--log", args.log],
                   check=True)
    alerts = load_alerts(args.log)
    result = evaluate(alerts, parse_labels(args.labels))
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Add `--log` flag to `main.py`** (argparse: `--log`, default `logs/session.jsonl`; used as the `SessionLogger` path).

- [ ] **Step 3: Create a labeled sample** — record 30–60 s including at least one deliberate head-drop/eye-close, and hand-label the drowsy interval with timestamps into `testdata/labels.jsonl` (the timestamps must match video time; add a `--clock` display option in `main.py` if helpful for labeling).

- [ ] **Step 4: Run the eval**

```bash
./venv/Scripts/python scripts/replay_eval.py --source testdata/sample.mp4 --labels testdata/labels.jsonl
```

Expected: precision/recall/F1 printed. Record the baseline numbers — later threshold tuning should *improve* them.

- [ ] **Step 5: Commit**

```bash
git add scripts/replay_eval.py main.py testdata/labels.jsonl
git commit -m "feat: replay evaluation harness with precision/recall"
```

---

**P3 Definition of Done**

- [ ] Every session writes `logs/session.jsonl` (frames at 1 Hz + alert events)
- [ ] `--summary` (or `scripts/replay_eval.py`) prints a trip summary
- [ ] Baseline precision/recall/F1 recorded for the sample video

---

## P4 — Usability

### Task P4.1: JSON settings overrides with validation

**Files:**
- Modify: `yolo/config.py` (add `LoadSettings`)
- Create: `settings.example.json`
- Create: `tests/test_settings.py`

- [ ] **Step 1: Add `LoadSettings` to `yolo/config.py`**

```python
import json
import os
import sys


def LoadSettings(path=None):
    """Override module-level constants from a validated JSON file.

    Raises ValueError on unknown keys or non-numeric values for numeric keys.
    """
    if not path or not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    module = sys.modules[__name__]
    for key, value in data.items():
        if not hasattr(module, key):
            raise ValueError(f"Unknown setting: {key}")
        current = getattr(module, key)
        if isinstance(current, (int, float)) and not isinstance(value, (int, float)):
            raise ValueError(f"Setting {key} must be numeric, got {value!r}")
        setattr(module, key, value)
```

- [ ] **Step 2: Create `settings.example.json`**

```json
{
  "CaptureWidth": 640,
  "CaptureHeight": 480,
  "YoloEveryN": 1,
  "HeadPoseEveryN": 2,
  "YoloDrowsyThreshold": 0.5,
  "YoloDrowsyWeak": 0.3,
  "PerclosAlertThreshold": 0.5,
  "EarClosedThreshold": 0.2,
  "TelegramCooldown": 30.0
}
```

- [ ] **Step 3: Write `tests/test_settings.py`**

```python
import json
import pytest
from yolo import config


def test_load_settings_overrides(tmp_path):
    path = tmp_path / "s.json"
    path.write_text(json.dumps({"YoloDrowsyThreshold": 0.6}))
    config.LoadSettings(str(path))
    assert config.YoloDrowsyThreshold == 0.6
    config.LoadSettings(None)          # no-op


def test_load_settings_rejects_unknown_key(tmp_path):
    path = tmp_path / "s.json"
    path.write_text(json.dumps({"Nope": 1}))
    with pytest.raises(ValueError):
        config.LoadSettings(str(path))


def test_load_settings_rejects_non_numeric(tmp_path):
    path = tmp_path / "s.json"
    path.write_text(json.dumps({"YoloDrowsyThreshold": "high"}))
    with pytest.raises(ValueError):
        config.LoadSettings(str(path))
```

- [ ] **Step 4: Call `LoadSettings(args.config)` at the top of `main.py`, add `--config` flag. Run tests.**

```bash
./venv/Scripts/python -m pytest -q
./venv/Scripts/python main.py --config settings.example.json --help
```

Expected: `34 passed`.

- [ ] **Step 5: Commit**

```bash
git add yolo/config.py settings.example.json tests/test_settings.py main.py
git commit -m "feat: validated JSON settings overrides"
```

---

### Task P4.2: CLI flags and startup diagnostics

**Files:**
- Create: `yolo/diagnostics.py`
- Modify: `main.py` (flags: `--config`, `--calibrate`, `--skip-calibration`, `--record`, `--log`, `--no-alarm`, `--no-telegram`, `--headless`, `--source`; run diagnostics before starting)
- Create: `tests/test_diagnostics.py`

- [ ] **Step 1: Write `yolo/diagnostics.py`**

```python
"""Startup diagnostics: check models, camera, and optional integrations."""

import os
import cv2


def RunDiagnostics(source, no_alarm=False, no_telegram=False) -> list:
    """Return a list of problem strings. Empty list = all good."""
    problems = []
    for f in ("best.pt", "face_landmarker.task"):
        if not os.path.exists(f):
            problems.append(f"Missing model file: {f}")
    if not no_alarm and not os.path.exists("alert.mp3"):
        problems.append("Missing alarm file: alert.mp3")
    cap = cv2.VideoCapture(source)
    ok, _ = cap.read()
    cap.release()
    if not ok:
        problems.append(f"Cannot read from source: {source}")
    if not no_telegram and not (os.environ.get("TELEGRAM_BOT_TOKEN")
                                and os.environ.get("TELEGRAM_CHAT_ID")):
        problems.append("Telegram enabled but TELEGRAM_BOT_TOKEN / "
                        "TELEGRAM_CHAT_ID are not set")
    return problems
```

- [ ] **Step 2: Write `tests/test_diagnostics.py`** (checks only file-presence branch; camera branch is integration)

```python
import pytest
from yolo import diagnostics


@pytest.mark.integration
def test_diagnostics_accepts_camera():
    # Requires a webcam; skipped in fast runs.
    problems = diagnostics.RunDiagnostics(0, no_alarm=True, no_telegram=True)
    assert "Cannot read from source: 0" not in problems
```

- [ ] **Step 3: Wire into `main.py`**

```python
from yolo.diagnostics import RunDiagnostics

problems = RunDiagnostics(source, args.no_alarm, args.no_telegram)
if problems:
    for p in problems:
        print(f"[!] {p}")
    if not args.headless:
        input("Press Enter to ignore and continue, or Ctrl+C to quit.")
```

- [ ] **Step 4: Run tests (fast suite skips integration)**

```bash
./venv/Scripts/python -m pytest -q -m "not integration"
```

Expected: `34 passed, 1 skipped`.

- [ ] **Step 5: Commit**

```bash
git add yolo/diagnostics.py tests/test_diagnostics.py main.py
git commit -m "feat: CLI flags and startup diagnostics"
```

---

### Task P4.3: Keyboard shortcuts (snapshot, record, mute, pause)

**Files:**
- Modify: `main.py` (key handler in the display loop)
- Modify: `yolo/alarm.py` (add `SetAlarmMuted`)
- Modify: `.gitignore` (add `captures/`)

- [ ] **Step 1: Add `SetAlarmMuted` to `yolo/alarm.py`**

```python
_IsMuted = False


def SetAlarmMuted(muted: bool) -> None:
    global _IsMuted
    _IsMuted = muted
    if muted:
        _StopAlarm()


def _StopAlarm() -> None:
    global _IsPlayingAlarm
    if _IsPlayingAlarm:
        ctypes.windll.winmm.mciSendStringW("stop alarm", None, 0, None)
        ctypes.windll.winmm.mciSendStringW("close alarm", None, 0, None)
        _IsPlayingAlarm = False
```

and change `UpdateAlarm` to early-return when `_IsMuted`.

- [ ] **Step 2: Wire the key handler in `main.py`**

```python
key = cv2.waitKey(1) & 0xFF
if key == ord("q"):
    break
elif key == ord("s"):
    cv2.imwrite(f"captures/snap_{int(time.time())}.jpg", annotated)
elif key == ord("m"):
    alarm_muted = not alarm_muted
    SetAlarmMuted(alarm_muted)
elif key == ord("p"):
    paused = not paused
```

When `paused` is True: stop evaluating timers, overlay `"PAUSED"` on the frame, and skip `UpdateAlarm`. (Freeze `DeltaTime` accumulation by skipping the state block.)

- [ ] **Step 3: Update `.gitignore`** — add `captures/`.

- [ ] **Step 4: Manual smoke test** — run with the camera, press each key, confirm behavior.

- [ ] **Step 5: Commit**

```bash
git add main.py yolo/alarm.py .gitignore
git commit -m "feat: keyboard shortcuts for snapshot, record, mute, pause"
```

---

**P4 Definition of Done**

- [ ] `settings.json` overrides thresholds without editing source
- [ ] `python main.py --help` documents every flag
- [ ] Missing models/camera produce friendly messages, not tracebacks
- [ ] `S`/`M`/`P`/`Q` shortcuts work; alarm can be muted

---

## P5 — Visual HUD

### Task P5.1: Anti-aliased PIL HUD

**Files:**
- Create: `yolo/hud.py`
- Create: `scripts/render_test_frame.py`
- Create: `tests/test_hud.py`
- Modify: `main.py` (use `RenderHud` when `config.PilHud` is True; default True)

**Design.** Render the sidebar and alert visuals with Pillow (real fonts, translucent rounded panels) and composite over the camera frame. Keep the fast OpenCV box/axis drawing as-is. Cache the static panel background and re-render it only on size changes.

**New config constants:**

```python
PilHud = True
HudFontName = "DejaVuSans-Bold.ttf"   # falls back to default if missing
NightMode = False
```

- [ ] **Step 1: Write `yolo/hud.py`**

```python
"""Anti-aliased HUD rendering with Pillow."""

import math
from dataclasses import dataclass, field
from collections import deque

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from .config import HudPanel, NightMode


@dataclass
class HudState:
    attention: float = 100.0
    perclos: float = 0.0
    max_drowsy: float = 0.0
    max_alert: float = 0.0
    pitch: float = 0.0
    yaw: float = 0.0
    roll: float = 0.0
    pose_valid: bool = False
    head_down: bool = False
    looking_away: bool = False
    face_lost: bool = False
    alert: str | None = None
    fps: float = 0.0
    attention_history: deque = field(default_factory=lambda: deque(maxlen=60))


def _font(size):
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf", size)
    except OSError:
        return ImageFont.load_default()


def _rounded_panel(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def RenderHud(frame: np.ndarray, state: HudState) -> np.ndarray:
    """Composite the HUD over a BGR frame and return the annotated frame."""
    img = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).convert("RGBA")
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    W, H = img.size
    panel_w = HudPanel
    _rounded_panel(d, (W - panel_w, 0, W - 8, H - 8), 16, (18, 18, 24, 220))
    d.text((W - panel_w + 16, 16), "ATTENTION", font=_font(18),
           fill=(200, 200, 210, 255))

    # Attention gauge (arc from 180° to 0°)
    cx, cy, r = W - panel_w + 118, 120, 80
    color = (76, 175, 80, 255) if state.attention >= 80 else \
            (255, 193, 7, 255) if state.attention >= 50 else (244, 67, 54, 255)
    start = math.radians(180)
    end = math.radians(180 - 180 * state.attention / 100.0)
    d.arc((cx - r, cy - r, cx + r, cy + r), start=180, end=0,
          fill=(60, 60, 70, 255), width=10)
    d.arc((cx - r, cy - r, cx + r, cy + r), start=180, end=180 - 180 * state.attention / 100.0,
          fill=color, width=10)
    d.text((cx - 20, cy - 16), f"{state.attention:.0f}", font=_font(28),
           fill=(255, 255, 255, 255))

    # Sparkline of attention history
    if len(state.attention_history) > 1:
        pts = []
        hist = list(state.attention_history)
        n = len(hist)
        base_x = W - panel_w + 20
        for i, val in enumerate(hist):
            x = base_x + i * ((panel_w - 40) / max(n - 1, 1))
            y = 240 - (val / 100.0) * 90
            pts.append((x, y))
        d.line(pts, fill=(100, 200, 255, 255), width=2)

    # Values block
    y = 280
    for label, value in (("DROWSY", state.max_drowsy),
                         ("PERCLOS", state.perclos),
                         ("FPS", state.fps / 100.0)):
        d.text((W - panel_w + 20, y), label, font=_font(14), fill=(150, 150, 160, 255))
        filled = int(value * (panel_w - 40))
        d.rounded_rectangle((W - panel_w + 20, y + 18, W - 28, y + 30),
                            radius=6, fill=(60, 60, 70, 255))
        d.rounded_rectangle((W - panel_w + 20, y + 18, W - panel_w + 20 + filled,
                             y + 30), radius=6, fill=(100, 180, 255, 255))
        y += 44

    # Alert banner
    if state.alert:
        color = (244, 67, 54, 255) if "MICROSLEEP" in state.alert else (255, 152, 0, 255)
        d.rounded_rectangle((20, 20, W - panel_w - 20, 72), radius=12, fill=color)
        d.text((40, 36), state.alert, font=_font(22), fill=(255, 255, 255, 255))

    # Face-lost indicator
    if state.face_lost:
        d.text((W - panel_w + 20, H - 60), "FACE LOST", font=_font(16),
               fill=(244, 67, 54, 255))

    # Night mode: dim everything
    if NightMode:
        overlay = Image.eval(overlay, lambda v: v // 2)

    img = Image.alpha_composite(img, overlay)
    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
```

- [ ] **Step 2: Write `tests/test_hud.py`**

```python
import numpy as np
from yolo.hud import RenderHud, HudState


def test_render_returns_same_size():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out = RenderHud(frame, HudState(attention=75.0))
    assert out.shape == frame.shape


def test_render_with_alert():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out = RenderHud(frame, HudState(alert="MICROSLEEP - EYES CLOSED! WAKE UP!"))
    assert out.shape == frame.shape and out.dtype == np.uint8
```

- [ ] **Step 3: Write `scripts/render_test_frame.py`** (eyeball the HUD without a camera)

```python
"""Render the HUD onto a synthetic frame and save a PNG for visual QA."""
import numpy as np
import cv2
from yolo.hud import RenderHud, HudState

def main():
    frame = np.full((720, 1280, 3), 30, dtype=np.uint8)
    for y in range(0, 720, 40):
        cv2.rectangle(frame, (0, y), (1280, y + 2), (45, 45, 50), -1)
    state = HudState(attention=72.0, perclos=0.35, max_drowsy=0.4,
                     pitch=-18.0, alert="HEAD NODDING - DROWSY!")
    out = RenderHud(frame, state)
    cv2.imwrite("hud_preview.png", out)
    print("Wrote hud_preview.png")

if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Wire into `main.py`** — replace `DrawHud(...)` with `RenderHud(annotated, hud_state)` when `config.PilHud` is True (construct `HudState` from the same values previously passed to `DrawHud`, plus `fps` and a 1 Hz `attention_history` deque).

- [ ] **Step 5: Visual QA**

```bash
./venv/Scripts/python scripts/render_test_frame.py
./venv/Scripts/python -m pytest -q
```

Open `hud_preview.png` and adjust fonts/spacing. Expected: `36 passed`.

- [ ] **Step 6: Commit**

```bash
git add yolo/hud.py scripts/render_test_frame.py tests/test_hud.py main.py yolo/config.py
git commit -m "feat: anti-aliased PIL HUD with gauge, sparkline, alert banner"
```

---

### Task P5.2: Graduated alert visuals and face-lost countdown

**Files:**
- Modify: `yolo/hud.py` (severity model + pulse + countdown ring)

- [ ] **Step 1: Add severity + pulse rendering to `hud.py`**

```python
ALERT_SEVERITY = {
    "MICROSLEEP": 4,
    "HEAD NODDING": 3,
    "FATIGUE": 3,
    "FACE LOST": 3,
    "DISTRACTED": 2,
    "DROWSINESS": 1,
}

def _severity(alert):
    if not alert:
        return 0
    for key, sev in ALERT_SEVERITY.items():
        if key in alert.upper():
            return sev
    return 1
```

In `RenderHud`, when an alert is active, draw a pulsing vignette whose alpha and border thickness scale with severity and a `time.monotonic()` sine:

```python
sev = _severity(state.alert)
if sev:
    pulse = 0.5 + 0.5 * math.sin(2 * math.pi * 2.0 * (time.monotonic() % 1.0))
    alpha = int(40 + 50 * sev * pulse)
    # vignette
    overlay.alpha_composite(_vignette(img.size, alpha))
    # pulsing border
    width = 4 + 4 * sev * pulse
    d.rectangle((0, 0, W - 1, H - 1), outline=(244, 67, 54, 255), width=int(width))
```

plus a helper `_vignette(size, alpha)` that builds a radial-gradient RGBA layer.

- [ ] **Step 2: Face-lost countdown ring** — when `state.face_lost`, draw the last-seen crop (passed in `HudState.last_seen: np.ndarray | None`) in the panel plus an arc showing `FaceLostAccumulated / FaceLostDrowsyTime` remaining.

- [ ] **Step 3: Regenerate preview and verify no crash**

```bash
./venv/Scripts/python scripts/render_test_frame.py
./venv/Scripts/python -m pytest -q
```

- [ ] **Step 4: Commit**

```bash
git add yolo/hud.py
git commit -m "feat: graduated alert severity, pulse, vignette, face-lost countdown"
```

---

**P5 Definition of Done**

- [ ] HUD renders with real fonts and translucent panels (QA screenshot reviewed)
- [ ] Alert visuals ramp with severity; face-lost shows a countdown ring
- [ ] Night mode dims the overlay
- [ ] `pytest -q` passes (36+ tests)

---

## P6 — Stretch Goals (optional, not fully specced)

| Idea | Effort | Notes |
|---|---|---|
| ONNX export for YOLO | M | `model.export(format="onnx", imgsz=640)`; `YoloEngine` config with `.pt` fallback; measure FPS gain |
| PyInstaller packaging | M | `pyinstaller --onefile main.py`; bundle `best.pt`, `face_landmarker.task`, `alert.mp3`; verify MCI + MediaPipe asset extraction |
| Local web dashboard | L | Flask/FastAPI + WebSocket streaming annotated frames, attention chart, and the event log; phone-accessible on LAN |
| i18n overlay messages | S | `AlertMessages` dict per language (`en`, `id`), `Language` config |
| Yawn detection (MAR) | M | Reuse `yolo/eyes.py` pattern with mouth landmarks `[61, 291, ...]`; sustained high MAR → new alert channel |
| Camera auto-reconnect | S | In `CameraThread`, on 100+ failures try `cap.open(source)` every 2 s |

---

## Cross-Phase Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Threading bugs (races, deadlocks) | Drop-old `LatestValue` handoffs only; one writer per value; display thread never mutates published frames; keep `imshow` on main thread |
| MediaPipe video-mode timestamp errors | Strictly increasing `time.monotonic()`-based ms inside the inference thread only |
| FPS gains below target | Measure before/after with the benchmark in P1.6; tune `YoloEveryN`, `HeadPoseEveryN`, capture resolution |
| Calibration profile is wrong (user moved) | Re-run with `--calibrate`; store profile with timestamp; profile is JSON, easily deleted |
| PERCLOS window lags real events | PERCLOS is a *fatigue* signal (long window is correct); microsleep channel (EAR) covers acute events |
| PIL HUD slows the loop | Static panel cached; only dynamic values redrawn; `PilHud=False` fallback keeps `DrawHud` available |
| Models/camera missing on user machines | P4.2 diagnostics print friendly messages before starting |

---

## Suggested Execution Order

Run phases strictly in order: **P0 → P1 → P2 → P3 → P4 → P5** (each phase's Definition of Done gates the next). P3's replay harness can start as soon as P1 lands if you want to parallelize. P6 items are independent and can be picked up any time after P3.
