"""
Driver Drowsiness & Distraction Detection — Main Application.

Orchestrates YOLO eye-state detection and MediaPipe head-pose estimation
in a real-time camera loop with HUD overlay and alerts.

Face-Lost Detection:
When the driver's head drops below the camera's view (common during
microsleep), the system remembers the last known state and escalates
to a FACE LOST alert instead of going silent.
"""

import time
import cv2
import mediapipe as mp
from dotenv import load_dotenv

from yolo.config import (
    HeadDownPitch,
    HeadYawThreshold,
    HeadRollThreshold,
    HeadDownTime,
    HeadAwayTime,
    CombinedDrowsyTime,
    FaceLostDrowsyTime,
    FaceLostCleanTime,
    HeadPoseEveryN,
    YoloDrowsyThreshold,
    YoloDrowsyWeak,
    YoloDrowsyDuration,
    FrameWidth,
    FrameHeight,
    PoseSmoothAlpha,
    AttentionSmoothAlpha,
    AttentionFocusedMin,
    AttentionUnfocusedMin,
    TelegramCooldown,
    AlertMessages,
)
from yolo.alarm import UpdateAlarm
from yolo.telegram import TriggerTelegramPhoto
from yolo.drawing import (
    DrawHud,
    DrawAlertOverlay,
    DrawModernBox,
    DrawHeadAxes,
    ExtractDrowsyCrop,
)
from yolo.head_pose import ComputeHeadPose
from yolo.attention import ComputeAttentionScore, UpdateTimer
from yolo.detector import CreateDetectionModel, CreateFaceLandmarker

# ── Load environment ────────────────────────────────────────
load_dotenv()

# ── Models ──────────────────────────────────────────────────
DetectionModel = CreateDetectionModel("best.pt")
FaceLandmarker = CreateFaceLandmarker("face_landmarker.task")

# ── Camera ──────────────────────────────────────────────────
Camera = cv2.VideoCapture(0)
Camera.set(cv2.CAP_PROP_FRAME_WIDTH, FrameWidth)
Camera.set(cv2.CAP_PROP_FRAME_HEIGHT, FrameHeight)

cv2.namedWindow("Drowsiness Detection", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Drowsiness Detection", FrameWidth, FrameHeight)

# ── State ───────────────────────────────────────────────────
LastTime = time.time()
Tick = 0

# Accumulator-based timers (seconds accumulated)
YoloDrowsyAcc = 0.0
HeadDownAcc = 0.0
HeadAwayAcc = 0.0
CombinedAcc = 0.0

# Face-lost tracking
FaceLost = False
FaceLostAccumulated = 0.0
WasHeadDownBeforeLoss = False
WasDrowsyBeforeLoss = False
PrevFaceFound = False  # needed to detect the transition

HeadPose = {
    "pitch": 0.0, "yaw": 0.0, "roll": 0.0,
    "valid": False, "rvec": None, "tvec": None, "nose_pt": None,
}
HpFrameCounter = 0

SmoothedAttention = 100.0
SmoothedPitch = 0.0
SmoothedYaw = 0.0
SmoothedRoll = 0.0

# ── Main Loop ───────────────────────────────────────────────
while True:
    Success, Frame = Camera.read()
    if not Success:
        break

    # Delta time for accumulator-based timers
    Now = time.time()
    DeltaTime = Now - LastTime
    LastTime = Now

    Tick += 1
    Frame = cv2.flip(Frame, 1)

    # Resize if needed
    h, w = Frame.shape[:2]
    if w > FrameWidth:
        scale = FrameWidth / w
        Frame = cv2.resize(Frame, (int(w * scale), int(h * scale)))

    # ── Head-Pose (every Nth frame) ─────────────────────────
    HpFrameCounter += 1
    if HpFrameCounter % HeadPoseEveryN == 0:
        rgb = cv2.cvtColor(Frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = FaceLandmarker.detect_for_video(mp_image, Tick * 33)
        HeadPose = ComputeHeadPose(result, Frame.shape)
        if HeadPose["valid"]:
            alpha = PoseSmoothAlpha
            SmoothedPitch = alpha * HeadPose["pitch"] + (1 - alpha) * SmoothedPitch
            SmoothedYaw = alpha * HeadPose["yaw"] + (1 - alpha) * SmoothedYaw
            SmoothedRoll = alpha * HeadPose["roll"] + (1 - alpha) * SmoothedRoll

    # ── YOLO Detection ──────────────────────────────────────
    results = DetectionModel(Frame)
    Annotated = Frame.copy()

    MaxDrowsy = 0.0
    MaxAlert = 0.0
    FaceFound = False
    DrowsyCrop = None

    for r in results:
        for box in r.boxes:
            FaceFound = True
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])

            label = f"{'Drowsy' if cls_id == 0 else 'Alert'} ({conf:.2f})"
            color = (0, 0, 255) if cls_id == 0 else (0, 200, 0)

            if cls_id == 0:
                MaxDrowsy = max(MaxDrowsy, conf)
                DrowsyCrop = ExtractDrowsyCrop(Frame, x1, y1, x2, y2)
            else:
                MaxAlert = max(MaxAlert, conf)

            DrawModernBox(Annotated, x1, y1, x2, y2, label, color)

    # ── Face-Lost Detection ─────────────────────────────────
    # Detect the transition: face was present, now lost.
    JustLostFace = PrevFaceFound and not FaceFound

    if JustLostFace:
        # Snapshot the last known state at the moment of loss.
        FaceLost = True
        FaceLostAccumulated = 0.0
        WasHeadDownBeforeLoss = HeadPose["valid"] and SmoothedPitch < -HeadDownPitch
        WasDrowsyBeforeLoss = MaxDrowsy > YoloDrowsyWeak
    elif FaceFound:
        # Face returned — reset face-lost state.
        FaceLost = False
        FaceLostAccumulated = 0.0
        WasHeadDownBeforeLoss = False
        WasDrowsyBeforeLoss = False

    # Remember for next frame's transition detection.
    PrevFaceFound = FaceFound

    # Accumulate face-lost time and check threshold.
    FaceLostAlert = False
    if FaceLost:
        FaceLostAccumulated += DeltaTime
        if WasHeadDownBeforeLoss or WasDrowsyBeforeLoss:
            FaceLostAlert = FaceLostAccumulated >= FaceLostDrowsyTime
        else:
            FaceLostAlert = FaceLostAccumulated >= FaceLostCleanTime

    # ── State Evaluation ────────────────────────────────────
    hp = HeadPose
    HeadDown = hp["valid"] and SmoothedPitch < -HeadDownPitch
    LookingAway = hp["valid"] and abs(SmoothedYaw) > HeadYawThreshold
    HeadTilt = hp["valid"] and abs(SmoothedRoll) > HeadRollThreshold
    YoloDrowsy = MaxDrowsy > YoloDrowsyThreshold
    YoloWeak = MaxDrowsy > YoloDrowsyWeak

    # Freeze existing timers when face is lost (preserve progress).
    TimerFrozen = FaceLost

    YoloDrowsyAcc, YoloAlert = UpdateTimer(
        YoloDrowsy, YoloDrowsyAcc, DeltaTime, YoloDrowsyDuration,
        Freeze=TimerFrozen,
    )
    HeadDownAcc, HeadDownAlert = UpdateTimer(
        HeadDown, HeadDownAcc, DeltaTime, HeadDownTime,
        Freeze=TimerFrozen,
    )
    HeadAwayAcc, HeadAwayAlert = UpdateTimer(
        LookingAway, HeadAwayAcc, DeltaTime, HeadAwayTime,
        Freeze=TimerFrozen,
    )
    CombinedAcc, CombinedAlert = UpdateTimer(
        HeadDown and YoloWeak, CombinedAcc, DeltaTime, CombinedDrowsyTime,
        Freeze=TimerFrozen,
    )

    # ── Alert Priority ──────────────────────────────────────
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
        DrawAlertOverlay(Annotated, Tick, AlertMsg)
        TriggerTelegramPhoto(
            DrowsyCrop if DrowsyCrop is not None else Frame,
            Cooldown=TelegramCooldown,
        )

    UpdateAlarm(AlertMsg is not None)

    # ── Attention Score ─────────────────────────────────────
    raw = ComputeAttentionScore(MaxDrowsy, SmoothedPitch, SmoothedYaw)
    SmoothedAttention = AttentionSmoothAlpha * SmoothedAttention + (1 - AttentionSmoothAlpha) * raw

    IsFocused = (
        SmoothedAttention >= AttentionFocusedMin
        and not HeadDown
        and not LookingAway
        and MaxDrowsy < YoloDrowsyWeak
        and hp["valid"]
    )
    IsUnfocused = (
        SmoothedAttention >= AttentionUnfocusedMin
        and SmoothedAttention < AttentionFocusedMin
        and not HeadDown
        and not LookingAway
        and hp["valid"]
    )

    # ── Draw HUD ────────────────────────────────────────────
    SmoothedHp = {
        "pitch": SmoothedPitch,
        "yaw": SmoothedYaw,
        "roll": SmoothedRoll,
        "valid": hp["valid"],
    }
    DrawHud(
        Annotated,
        not FaceFound and not hp["valid"],
        AlertMsg is not None,
        MaxDrowsy,
        MaxAlert,
        AttentionScore=SmoothedAttention,
        HeadPose=SmoothedHp,
        HeadDown=HeadDown,
        LookingAway=LookingAway,
        HeadTilt=HeadTilt,
        IsFocused=IsFocused,
        IsUnfocused=IsUnfocused,
        FaceLost=FaceLost,
    )

    if hp["valid"] and hp["rvec"] is not None:
        DrawHeadAxes(Annotated, hp["rvec"], hp["tvec"], hp["nose_pt"])

    cv2.imshow("Drowsiness Detection", Annotated)
    if cv2.waitKey(1) == ord("q"):
        break

# ── Cleanup ─────────────────────────────────────────────────
Camera.release()
FaceLandmarker.close()
cv2.destroyAllWindows()
