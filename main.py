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
from yolo.attention import AlertLatch, ComputeAttentionScore, UpdateTimer
from yolo.config import (
    HeadDownPitch, HeadYawThreshold, HeadRollThreshold,
    HeadDownTime, HeadAwayTime, CombinedDrowsyTime,
    FaceLostDrowsyTime, FaceLostCleanTime,
    HeadPoseEveryN, YoloEveryN,
    YoloDrowsyThreshold, YoloDrowsyWeak, YoloDrowsyDuration,
    CaptureWidth, CaptureHeight,
    DisplayFps, FrameWidth, FrameHeight,
    PoseSmoothAlpha, AttentionSmoothAlpha,
    AttentionFocusedMin, AttentionUnfocusedMin,
    TelegramCooldown, AlertMessages,
    PerclosAlertThreshold, PerclosAlertTime, PerclosWindowSeconds,
    DrowsyEmaAlpha, EyesClosedYoloConf,
    EarClosedThreshold, EarMinBlinkSeconds, MicrosleepSeconds,
    ClearGraceSeconds,
    CalibrationDuration, ProfilePath,
)
from yolo.calibration import CalibrationProfile, RunCalibration
from yolo.eyes import BlinkMonitor
from yolo.perclos import DrowsyEMA, PerclosTracker
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
    ap.add_argument("--calibrate", action="store_true",
                    help="Force re-running the neutral-pose calibration.")
    ap.add_argument("--skip-calibration", action="store_true",
                    help="Do not auto-calibrate when no profile exists.")
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

    # ── Calibration ───────────────────────────────────────────────
    profile = CalibrationProfile.load(ProfilePath)
    if profile is None or args.calibrate:
        if args.headless or args.skip_calibration:
            if profile is None:
                print("[warn] No calibration profile and headless/skip-calibration: "
                      "using neutral defaults.")
            profile = profile or CalibrationProfile()
        else:
            def current_pose():
                r = inference.latest_result()
                if r is None or not r.head_pose.get("valid"):
                    return {"valid": False}
                return {"pitch": r.head_pose["pitch"],
                        "yaw": r.head_pose["yaw"],
                        "roll": r.head_pose["roll"], "valid": True}
            print("LOOK STRAIGHT AHEAD — calibrating neutral head pose...")
            try:
                profile = RunCalibration(current_pose, duration=CalibrationDuration)
                profile.save(ProfilePath)
                print(f"Calibration saved to {ProfilePath} "
                      f"(pitch={profile.neutral_pitch:.1f}, "
                      f"yaw={profile.neutral_yaw:.1f}, roll={profile.neutral_roll:.1f})")
            except RuntimeError as exc:
                print(f"[warn] {exc} Using neutral defaults.")
                profile = CalibrationProfile()

    # ── State (unchanged logic from the original loop) ────────────
    LastTime = time.monotonic()
    Tick = 0
    YoloDrowsyAcc = HeadDownAcc = HeadAwayAcc = CombinedAcc = 0.0
    PerclosAcc = 0.0
    ema_drowsy = DrowsyEMA(alpha=DrowsyEmaAlpha)
    perclos = PerclosTracker(window_seconds=PerclosWindowSeconds)
    blinks = BlinkMonitor(closed_threshold=EarClosedThreshold,
                          min_blink_seconds=EarMinBlinkSeconds,
                          microsleep_seconds=MicrosleepSeconds)
    latches = {name: AlertLatch(clear_seconds=ClearGraceSeconds)
               for name in ("perclos", "microsleep")}
    FaceLost = False
    FaceLostAccumulated = 0.0
    WasHeadDownBeforeLoss = WasDrowsyBeforeLoss = False
    PrevFaceFound = False
    SmoothedPitch = SmoothedYaw = SmoothedRoll = 0.0
    SmoothedAttention = 100.0
    DisplayStats = PerfStats()

    FramePeriod = 1.0 / DisplayFps

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
                WasHeadDownBeforeLoss = hp["valid"] and (SmoothedPitch - profile.neutral_pitch) < -HeadDownPitch
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
            HeadDown = hp["valid"] and (SmoothedPitch - profile.neutral_pitch) < -HeadDownPitch
            LookingAway = hp["valid"] and abs(SmoothedYaw - profile.neutral_yaw) > HeadYawThreshold
            HeadTilt = hp["valid"] and abs(SmoothedRoll - profile.neutral_roll) > HeadRollThreshold
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

            # ── PERCLOS + EMA (fuses YOLO confidence and EAR) ──────
            eyes_closed = (ema_drowsy.update(result.max_drowsy) > EyesClosedYoloConf
                           or (result.ear is not None and result.ear < EarClosedThreshold))
            perclos_now = perclos.update(eyes_closed)
            PerclosAcc, PerclosFired = UpdateTimer(
                perclos_now > PerclosAlertThreshold, PerclosAcc, DeltaTime,
                PerclosAlertTime, Freeze=TimerFrozen)
            # Latches hold while timers are frozen (face lost) — dt=0 stops decay.
            PerclosAlert = latches["perclos"].update(
                PerclosFired, 0.0 if TimerFrozen else DeltaTime)

            # ── Microsleep (EAR-based) — most dangerous ────────────
            blink_state = blinks.update(result.ear if result.ear is not None else 1.0, Now)
            MicrosleepAlert = latches["microsleep"].update(
                blink_state["microsleep"], 0.0 if TimerFrozen else DeltaTime)

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
                elapsed = time.monotonic() - Now
                if elapsed < FramePeriod:
                    time.sleep(FramePeriod - elapsed)
            DisplayStats.tock("draw")

    finally:
        inference.stop()
        camera.stop()
        telegram.StopTelegramWorker()
        if not args.headless:
            cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
