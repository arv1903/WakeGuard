"""
Driver Drowsiness & Distraction Detection — Configuration Constants.

All tunable thresholds, dimensions, and layout values live here.
"""

import json
import math
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
        if isinstance(current, bool) and not isinstance(value, bool):
            # bool is subclass of int, so check explicitly to prevent 1/0 abuse
            raise ValueError(f"Setting {key} must be boolean, got {value!r}")
        if not isinstance(current, bool) and isinstance(current, (int, float)) and not isinstance(value, (int, float)):
            raise ValueError(f"Setting {key} must be numeric, got {value!r}")
        if isinstance(current, str) and not isinstance(value, str):
            raise ValueError(f"Setting {key} must be a string, got {value!r}")
        setattr(module, key, value)


def UpdateThresholds(updates: dict) -> dict:
    """Validated bulk update of live thresholds (used by /api/v1/settings).

    Validates types and ranges before mutating module globals. Returns the
    sanitized dict of actually-changed keys.

    Raises ValueError with a human-readable message on the first bad entry.
    """
    module = sys.modules[__name__]
    sanitized = ValidateRuntimeSettings(updates)
    for key, value in sanitized.items():
        setattr(module, key, value)
    return sanitized


_RUNTIME_SETTING_ALIASES = {
    "ear_threshold": "EarClosedThreshold",
    "microsleep_duration": "MicrosleepSeconds",
    "pitch_threshold": "HeadDownPitch",
    "yaw_threshold": "HeadYawThreshold",
    "roll_threshold": "HeadRollThreshold",
    "logging_enabled": "SessionLoggingEnabled",
    "night_mode": "NightMode",
    "perclos_threshold": "PerclosAlertThreshold",
    "yolo_drowsy_threshold": "YoloDrowsyThreshold",
    "blink_rate_threshold": "BlinkRateAlertPerMin",
    "safety_penalty_per_alert": "SafetyScorePenaltyPerAlert",
}


def ValidateRuntimeSettings(updates: dict) -> dict:
    """Return canonical, validated live settings without mutating config."""
    module = sys.modules[__name__]
    canonical = {}
    for key, value in updates.items():
        if key in {"telegram_enabled", "alarm_enabled"}:
            if not isinstance(value, bool):
                raise ValueError(f"Setting {key} must be boolean, got {value!r}")
            canonical[key] = value
            continue
        name = _RUNTIME_SETTING_ALIASES.get(key, key)
        if not hasattr(module, name):
            raise ValueError(f"Unknown setting: {key}")
        current = getattr(module, name)
        if isinstance(current, bool):
            if not isinstance(value, bool):
                raise ValueError(f"Setting {key} must be boolean, got {value!r}")
            canonical[name] = value
        elif isinstance(current, (int, float)):
            try:
                fv = float(value)
            except (TypeError, ValueError):
                raise ValueError(f"Setting {key} must be numeric, got {value!r}") from None
            if not math.isfinite(fv):
                raise ValueError(f"Setting {key} must be finite")
            # Range guards for safety-critical thresholds
            if name == "EarClosedThreshold" and not 0.05 <= fv <= 0.5:
                raise ValueError(f"ear_threshold {fv} out of range [0.05,0.5]")
            if name == "MicrosleepSeconds" and not 0.3 <= fv <= 5.0:
                raise ValueError(f"microsleep_duration {fv} out of range [0.3,5.0]")
            if name == "HeadDownPitch" and not 5 <= fv <= 45:
                raise ValueError(f"pitch_threshold {fv} out of range [5,45]")
            if name == "HeadYawThreshold" and not 10 <= fv <= 60:
                raise ValueError(f"yaw_threshold {fv} out of range [10,60]")
            if name == "HeadRollThreshold" and not 5 <= fv <= 30:
                raise ValueError(f"roll_threshold {fv} out of range [5,30]")
            if name == "SafetyScorePenaltyPerAlert" and not 0 <= fv <= 20:
                raise ValueError(f"safety_penalty_per_alert {fv} out of range [0,20]")
            if name == "PerclosAlertThreshold" and not 0.0 <= fv <= 1.0:
                raise ValueError(f"perclos_threshold {fv} out of range [0,1]")
            if name == "YoloDrowsyThreshold" and not 0.0 <= fv <= 1.0:
                raise ValueError(f"yolo_drowsy_threshold {fv} out of range [0,1]")
            if name == "BlinkRateAlertPerMin" and not 1.0 <= fv <= 30.0:
                raise ValueError(f"blink_rate_threshold {fv} out of range [1,30]")
            canonical[name] = fv
        elif isinstance(current, str):
            if not isinstance(value, str):
                raise ValueError(f"Setting {key} must be a string, got {value!r}")
            canonical[name] = value
        else:
            raise ValueError(f"Setting {key} cannot be updated at runtime")
    return canonical

# ── Telegram ──────────────────────────────────────
TelegramCooldown = 30.0

# ── Session Logging ────────────────────────────────
SessionLogPath = "logs/session.jsonl"
SessionLoggingEnabled = True

# ── Calibration ────────────────────────────────────
CalibrationDuration = 4.0      # seconds of neutral-pose sampling
CalibrationCountdown = 3.0     # seconds of on-screen countdown before sampling
ProfilePath = "profiles/driver.json"

# ── MediaPipe Face Landmark Indices ────────────────
# Nose tip, chin, left-eye outer, right-eye outer,
# left-mouth corner, right-mouth corner
LandmarkIndices = [1, 152, 33, 263, 61, 291]

# ── Generic 3D Face Model for solvePnP ────────────
FaceModelPoints = (
    (0.0, 0.0, 0.0),
    (0.0, 63.6, -12.5),
    (-43.3, -32.7, -26.0),
    (43.3, -32.7, -26.0),
    (-29.0, 31.5, -18.0),
    (29.0, 31.5, -18.0),
)

def focal_length(width: int) -> float:
    """Shared focal length helper (was duplicated 4× as w*1.05)."""
    return width * 1.05

# ── Head-Pose Thresholds (degrees) ────────────────
HeadDownPitch = 20.0
HeadYawThreshold = 30.0
HeadRollThreshold = 10.0

# ── Alert Timer Durations (seconds) ───────────────
HeadDownTime = 2.0
HeadAwayTime = 1.5
CombinedDrowsyTime = 1.5

# ── Face-Lost Detection ──────────────────────────
# When the face completely disappears from view (common during microsleep),
# we track how long it's been gone and escalate based on the last known state.
FaceLostDrowsyTime = 1.5    # fast trigger if last state was drowsy/head-down
FaceLostCleanTime = 3.0     # slower trigger if last state was clean/alert

# ── Performance ───────────────────────────────────
HeadPoseEveryN = 2                # run MediaPipe every N frames

# ── Performance / Pipeline ─────────────────────────
CaptureWidth = 640            # camera capture width (display upscales)
CaptureHeight = 480           # camera capture height
YoloEveryN = 2                # run YOLO every N frames (2 = ~15 fps on CPU, was 1 = 80-120ms starve)
DisplayFps = 30               # display loop target FPS (GUI mode)

# ── EAR / Blink / Microsleep ───────────────────────
EarClosedThreshold = 0.20     # EAR below this = eyes closed
EarMinBlinkSeconds = 0.10     # shorter closures are noise, not blinks
MicrosleepSeconds = 1.5       # continuous closed beyond this = microsleep
BlinkRateAlertPerMin = 8.0    # abnormally slow blink rate after observation window
BlinkRateAlertTime = 10.0

# ── YOLO Drowsiness Thresholds ────────────────────
YoloDrowsyThreshold = 0.5         # fire YOLO-only alert above this
YoloDrowsyWeak = 0.3              # lower bar when head-down is also true
YoloDrowsyDuration = 4.0

# ── PERCLOS / Fatigue ─────────────────────────────
PerclosWindowSeconds = 60.0   # rolling window
PerclosAlertThreshold = 0.5   # % of window with eyes closed → alert
PerclosAlertTime = 5.0        # seconds of sustained high PERCLOS to fire
DrowsyEmaAlpha = 0.9          # EMA smoothing of YOLO drowsy confidence
EyesClosedYoloConf = 0.3      # YOLO drowsy conf treated as "eyes closed"

# ── Focus / Attention Zones ───────────────────────

# ── Attention Score Weights ───────────────────────
AttentionYawWeight = 30.0
AttentionPitchWeight = 40.0
AttentionEyeWeight = 50.0
AttentionFocusedMin = 80.0
AttentionUnfocusedMin = 50.0

# ── Frame & Layout ────────────────────────────────
FrameWidth = 1280
FrameHeight = 720
HudPanel = 275
PoseSmoothAlpha = 0.35
AttentionSmoothAlpha = 0.85

# ── HUD Rendering ──────────────────────────────────
NightMode = False             # dim the overlay for night driving

# ── Safety Score ──────────────────────────────────
SafetyScorePenaltyPerAlert = 3.0  # points deducted per alert from avg_attention

# ── Alert hysteresis ───────────────────────────────
ClearGraceSeconds = 2.0       # alert stays on this long after condition clears

# ── Alert Messages ────────────────────────────────
AlertMessages = {
    "combined": "HEAD NODDING - DROWSY!",
    "face_lost": "FACE LOST — POSSIBLE MICROSLEEP!",
    "head_away": "DISTRACTED - WATCH ROAD!",
    "yolo": "DROWSINESS DETECTED!",
    "perclos": "FATIGUE DETECTED - SUSTAINED EYE CLOSURE!",
    "microsleep": "MICROSLEEP - EYES CLOSED! WAKE UP!",
    "low_blink": "LOW BLINK RATE - TAKE A BREAK!",
}
