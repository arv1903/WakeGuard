"""
Driver Drowsiness & Distraction Detection — Configuration Constants.

All tunable thresholds, dimensions, and layout values live here.
"""

# ── Telegram ──────────────────────────────────────
TelegramCooldown = 30.0

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
YoloEveryN = 1                # run YOLO every N frames (1 = every frame)
DisplayFps = 30               # display loop target FPS (GUI mode)

# ── EAR / Blink / Microsleep ───────────────────────
EarClosedThreshold = 0.20     # EAR below this = eyes closed
EarMinBlinkSeconds = 0.10     # shorter closures are noise, not blinks
MicrosleepSeconds = 1.5       # continuous closed beyond this = microsleep
BlinkRateAlertPerMin = 8.0    # (reserved) abnormally slow blink rate

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
HeadPitchFocusedMin = -10.0
HeadPitchFocusedMax = 15.0
HeadYawFocused = 15.0

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
BarWidth = 155
BarHeight = 11
PoseSmoothAlpha = 0.35
AttentionSmoothAlpha = 0.85

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
}
