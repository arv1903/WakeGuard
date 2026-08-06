"""
Driver Drowsiness & Distraction Detection — Configuration Constants.

All tunable thresholds, dimensions, and layout values live here.
"""

# ── Telegram ──────────────────────────────────────
TelegramCooldown = 30.0

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
DisplayFps = 30               # display loop target FPS
TelegramThreaded = True       # send photos on a background worker

# ── YOLO Drowsiness Thresholds ────────────────────
YoloDrowsyThreshold = 0.5         # fire YOLO-only alert above this
YoloDrowsyWeak = 0.3              # lower bar when head-down is also true
YoloDrowsyDuration = 4.0

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

# ── Alert Messages ────────────────────────────────
AlertMessages = {
    "combined": "HEAD NODDING - DROWSY!",
    "face_lost": "FACE LOST — POSSIBLE MICROSLEEP!",
    "head_away": "DISTRACTED - WATCH ROAD!",
    "yolo": "DROWSINESS DETECTED!",
}
