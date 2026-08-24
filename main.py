"""
Driver Drowsiness & Distraction Detection — Main Application.

Runs the threaded pipeline (capture → inference → display) and the
alert/attention state machine on the display thread.
"""

import argparse
import os
import platform
import queue
import math
import threading
import time
import uuid
from collections import deque

import cv2
import numpy as np

import yolo.telegram as telegram
from yolo.alarm import SetAlarmMuted, UpdateAlarm
from yolo.attention import AlertLatch, ComputeAttentionScore, UpdateTimer
from yolo.config import (
    HeadDownPitch, HeadYawThreshold, HeadRollThreshold,
    HeadDownTime, HeadAwayTime, CombinedDrowsyTime,
    FaceLostDrowsyTime, FaceLostCleanTime,
    HeadPoseEveryN, YoloEveryN,
    YoloDrowsyThreshold, YoloDrowsyWeak, YoloDrowsyDuration,
    CaptureWidth, CaptureHeight,
    DisplayFps, FrameWidth, FrameHeight, HudPanel,
    PoseSmoothAlpha, AttentionSmoothAlpha,
    AttentionFocusedMin, AttentionUnfocusedMin,
    TelegramCooldown, AlertMessages,
    PerclosAlertThreshold, PerclosAlertTime, PerclosWindowSeconds,
    DrowsyEmaAlpha, EyesClosedYoloConf,
    EarClosedThreshold, EarMinBlinkSeconds, MicrosleepSeconds,
    BlinkRateAlertPerMin, BlinkRateAlertTime,
    ClearGraceSeconds,
    CalibrationDuration, CalibrationCountdown, ProfilePath,
    SessionLogPath,
)
from yolo.calibration import CalibrationProfile, CalibrationSession, RunCalibration
from yolo.envfile import LoadEnvFile
from yolo.diagnostics import RunDiagnostics
from yolo.session_log import SessionLogger
from yolo.eyes import BlinkMonitor
from yolo.hud import HudState, RenderHud
from yolo.perclos import DrowsyEMA, PerclosTracker
from yolo.detector import CreateDetectionModel, CreateFaceLandmarker
from yolo.drawing import DrawAlertOverlay, DrawModernBox, DrawHeadAxes
from yolo.pipeline import CameraThread, InferenceThread
from yolo.stats import PerfStats
from yolo.monitoring import (GetAlertSeverity, MonitoringSnapshot,
                             MonitoringStore, SNAPSHOT_SCHEMA_VERSION,
                             SelectAlert)
from yolo.api import CommandConflictError, MonitoringApi
from yolo.config import LoadSettings
import yolo.config as _config

# Names bound by value from yolo.config above; refreshed after LoadSettings
# so --config overrides actually reach the app logic.
_CONFIG_NAMES = (
    "HeadDownPitch HeadYawThreshold HeadRollThreshold HeadDownTime "
    "HeadAwayTime CombinedDrowsyTime FaceLostDrowsyTime FaceLostCleanTime "
    "HeadPoseEveryN YoloEveryN YoloDrowsyThreshold YoloDrowsyWeak "
    "YoloDrowsyDuration CaptureWidth CaptureHeight DisplayFps FrameWidth "
    "FrameHeight HudPanel PoseSmoothAlpha AttentionSmoothAlpha AttentionFocusedMin "
    "AttentionUnfocusedMin TelegramCooldown PerclosAlertThreshold "
    "PerclosAlertTime PerclosWindowSeconds DrowsyEmaAlpha EyesClosedYoloConf "
    "EarClosedThreshold EarMinBlinkSeconds MicrosleepSeconds ClearGraceSeconds "
    "CalibrationDuration CalibrationCountdown ProfilePath SessionLogPath "
    "BlinkRateAlertPerMin BlinkRateAlertTime "
    "SessionLoggingEnabled NightMode"
).split()


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
    ap.add_argument("--log", default=SessionLogPath,
                    help="Path for the JSONL session log.")
    ap.add_argument("--summary", metavar="LOG_PATH",
                    help="Print a trip summary from a session log and exit.")
    ap.add_argument("--config", default=None,
                    help="Path to a JSON settings file overriding config.py defaults.")
    ap.add_argument("--record", metavar="PATH", default=None,
                    help="Record the annotated video to PATH.")
    ap.add_argument("--api", action="store_true",
                    help="Expose monitoring status/events for Flutter clients.")
    ap.add_argument("--api-host", default="127.0.0.1",
                    help="API bind host (LAN binding requires --api-token).")
    ap.add_argument("--api-port", type=int, default=8765,
                    help="API bind port (default 8765; 0 selects a free port).")
    ap.add_argument("--api-token", default=os.environ.get("DRIVER_API_TOKEN"),
                    help="Bearer token required for API access, especially on LAN.")
    return ap.parse_args()


def main():
    LoadEnvFile()                     # .env → os.environ (before diagnostics)
    args = parse_args()
    LoadSettings(args.config)
    for _name in _CONFIG_NAMES:
        globals()[_name] = getattr(_config, _name)
    if args.summary:
        from yolo.summary import BuildSummary, PrintSummary
        PrintSummary(BuildSummary(args.summary))
        return

    if args.api and not args.headless:
        print("[info] --api implies --headless; forcing headless mode (use --api without display window)")

        args.headless = True

    source = int(args.source) if args.source.isdigit() else args.source

    # ── Diagnostics ────────────────────────────────────────────────
    problems = RunDiagnostics(source, args.no_alarm, args.no_telegram)
    for p in problems:
        print(f"[!] {p}")
    if problems and not args.headless:
        try:
            input("Press Enter to ignore and continue, or Ctrl+C to quit.")
        except EOFError:
            pass

    # Load detection models once at startup (cheap), but defer camera/
    # inference threads until a session is started via the API.
    detection_model = CreateDetectionModel("best.pt")
    face_landmarker = CreateFaceLandmarker("face_landmarker.task")

    camera = None
    inference = None

    def _start_pipeline():
        nonlocal camera, inference
        if camera is not None and camera.is_alive():
            return  # already running
        camera = CameraThread(source, CaptureWidth, CaptureHeight)
        inference = InferenceThread(camera, detection_model, face_landmarker,
                                    pose_every_n=HeadPoseEveryN, yolo_every_n=YoloEveryN)
        camera.start()
        inference.start()
        print("[session] camera + inference pipeline started")

    def _stop_pipeline():
        nonlocal camera, inference
        if inference is not None:
            inference.stop()
            inference = None
        if camera is not None:
            camera.stop()
            camera = None
        print("[session] camera + inference pipeline stopped")

    if not args.no_telegram:
        telegram.StartTelegramWorker()

    # ── Calibration ───────────────────────────────────────────────
    def current_pose():
        if inference is None:
            return {"valid": False}
        r = inference.latest_result()
        if r is None or not r.head_pose.get("valid"):
            return {"valid": False}
        return {"pitch": r.head_pose["pitch"],
                "yaw": r.head_pose["yaw"],
                "roll": r.head_pose["roll"], "valid": True}

    # Load existing profile but do NOT run calibration at startup —
    # calibration is deferred to when a session starts and the pipeline
    # is running (so there are actual frames to calibrate from).
    _needs_calibration = False
    profile = CalibrationProfile.load(ProfilePath)
    if profile is None:
        profile = CalibrationProfile()
        _needs_calibration = True
        print("[warn] No calibration profile; using neutral defaults. "
              "Calibration will run when a session starts.")
    elif args.calibrate:
        _needs_calibration = True

    # ── State (unchanged logic from the original loop) ────────────
    LastTime = time.monotonic()
    Tick = 0
    YoloDrowsyAcc = HeadDownAcc = HeadAwayAcc = CombinedAcc = 0.0
    PerclosAcc = LowBlinkAcc = 0.0
    ema_drowsy = DrowsyEMA(alpha=DrowsyEmaAlpha)
    perclos = PerclosTracker(window_seconds=PerclosWindowSeconds)
    blinks = BlinkMonitor(closed_threshold=EarClosedThreshold,
                          min_blink_seconds=EarMinBlinkSeconds,
                          microsleep_seconds=MicrosleepSeconds)
    latches = {name: AlertLatch(clear_seconds=ClearGraceSeconds)
               for name in ("perclos", "microsleep", "low_blink")}
    FaceLost = False
    FaceLostAccumulated = 0.0
    WasHeadDownBeforeLoss = WasDrowsyBeforeLoss = False
    PrevFaceFound = False
    SmoothedPitch = SmoothedYaw = SmoothedRoll = 0.0
    SmoothedAttention = 100.0
    DisplayStats = PerfStats()
    attention_history = deque(maxlen=60)
    last_seen = None
    draw_fps = 0.0
    face_lost_progress = 0.0

    FramePeriod = 1.0 / DisplayFps
    logger = SessionLogger(args.log)
    prev_alert = None
    last_log_time = time.monotonic()
    recorder = None
    recording_enabled = args.record is not None
    recorder_path = args.record
    alarm_muted = False
    paused = False
    trip_active = False
    _idle_logged = False
    session_id = uuid.uuid4().hex
    trip_started_at = time.time()
    api_started_at = time.time()
    snapshot_sequence = 0
    cal_session: CalibrationSession | None = None
    calibration_status = {
        "state": "idle",
        "progress": 0.0,
        "error": None,
        "valid_samples": 0,
    }
    calibration_command_pending = False
    calibration_lock = threading.Lock()
    api_commands = queue.Queue()
    monitoring_store = MonitoringStore()

    def handle_api_command(command, payload):
        nonlocal calibration_command_pending
        if command == "update_settings":
            # Validate before acknowledging the HTTP request. The display
            # thread still owns mutation and side effects.
            payload = _config.ValidateRuntimeSettings(payload or {})
        elif command == "start_calibration":
            payload = payload or {}
            duration = payload.get("duration", CalibrationDuration)
            if isinstance(duration, bool) or not isinstance(duration, (int, float)):
                raise ValueError("calibration duration must be numeric")
            duration = float(duration)
            if not math.isfinite(duration) or not 1.0 <= duration <= 30.0:
                raise ValueError("calibration duration must be between 1 and 30 seconds")
            with calibration_lock:
                if inference is None or camera is None:
                    raise CommandConflictError("start a monitoring session before calibration")
                if calibration_command_pending or calibration_status["state"] == "running":
                    raise CommandConflictError("calibration is already running")
                calibration_command_pending = True
            payload = {"duration": duration}
        api_commands.put((command, payload))
        return {"accepted": True, "command": command}

    def current_summary():
        from yolo.summary import BuildSummary
        return BuildSummary(args.log, session_id=session_id)

    def current_history():
        from yolo.summary import BuildSessionHistory
        return BuildSessionHistory(args.log, limit=10)

    def current_telemetry(session_id: str):
        from yolo.summary import BuildSessionTelemetry
        return BuildSessionTelemetry(args.log, session_id)

    def current_session():
        return {
            "id": session_id,
            "active": trip_active,
            "started_at": trip_started_at,
            "summary_url": "/api/v1/sessions/current/summary",
        }

    def api_metadata():
        return {
            "service": "driver-monitor",
            "schema_version": SNAPSHOT_SCHEMA_VERSION,
            "api_version": "v1",
            "device_name": os.environ.get("DRIVER_DEVICE_NAME") or platform.node(),
            "platform": platform.system().lower(),
            "started_at": api_started_at,
            "capabilities": ["events", "jpeg", "mjpeg", "commands", "summary", "history", "pairing"],
        }

    monitoring_api = None
    if args.api:
        monitoring_api = MonitoringApi(
            host=args.api_host,
            port=args.api_port,
            store=monitoring_store,
            command_handler=handle_api_command,
            summary_provider=current_summary,
            history_provider=current_history,
            telemetry_provider=current_telemetry,
            metadata_provider=api_metadata,
            session_provider=current_session,
            auth_token=args.api_token,
        )
        monitoring_api.start()
        print(f"Monitoring API listening on {args.api_host}:{monitoring_api.port}")
        # Publish an initial idle snapshot so SSE clients get an immediate
        # response instead of blocking for 25 s on the first connect.
        snapshot_sequence += 1
        monitoring_store.publish(MonitoringSnapshot(
            sequence=snapshot_sequence, timestamp=time.time(),
            session_id=session_id, trip_started_at=trip_started_at,
            trip_active=False, attention=0, perclos=0, ema_drowsy=0,
            ear=None, eyes_closed=False, microsleep=False, blinks_per_min=0,
            pitch=0, yaw=0, roll=0, pose_valid=False, face_found=False,
            face_lost=False, face_lost_progress=0, head_down=False,
            looking_away=False, head_tilt=False, focused=False,
            unfocused=False, alert=None, alert_severity=0,
            alarm_muted=False, fps=0,
            calibration_state=calibration_status["state"],
            calibration_progress=calibration_status["progress"],
            calibration_error=calibration_status["error"],
            calibration_valid_samples=calibration_status["valid_samples"],
        ))

    if not args.headless:
        cv2.namedWindow("Drowsiness Detection", cv2.WINDOW_NORMAL)
        # Canvas is video + side panel, so make room for both.
        cv2.resizeWindow("Drowsiness Detection", FrameWidth + HudPanel, FrameHeight)

    try:
        while True:
            # API threads only enqueue commands; state changes happen here on
            # the display thread so the detector's state remains race-free.
            while True:
                try:
                    command, payload = api_commands.get_nowait()
                except queue.Empty:
                    break
                if command == "mute_alarm":
                    alarm_muted = True
                    SetAlarmMuted(True)
                elif command == "unmute_alarm":
                    alarm_muted = False
                    SetAlarmMuted(False)
                elif command == "start_trip":
                    if not trip_active:
                        session_id = uuid.uuid4().hex
                        trip_started_at = time.time()
                        logger.session_start(session_id)
                        _start_pipeline()
                        blinks.reset()
                        # Run calibration on first session if needed (non-blocking)
                        if _needs_calibration:
                            cal_session = CalibrationSession(duration=CalibrationDuration)
                            cal_session.start()
                            calibration_status.update(
                                state="running", progress=0.0, error=None,
                                valid_samples=0)
                            print("[session] started non-blocking neutral head pose calibration...")
                    trip_active = True
                    last_log_time = time.monotonic()
                elif command == "stop_trip":
                    if trip_active:
                        logger.session_stop(session_id)
                    trip_active = False
                    _stop_pipeline()
                    blinks.reset()
                elif command == "start_calibration":
                    if inference is None or camera is None or not trip_active:
                        calibration_status.update(
                            state="failed", progress=0.0,
                            error="monitoring session ended before calibration started",
                            valid_samples=0)
                        with calibration_lock:
                            calibration_command_pending = False
                        continue
                    duration = payload["duration"]
                    cal_session = CalibrationSession(duration=duration)
                    cal_session.start()
                    calibration_status.update(
                        state="running", progress=0.0, error=None,
                        valid_samples=0)
                    with calibration_lock:
                        calibration_command_pending = False
                    print(f"[api] started non-blocking calibration ({duration:.1f}s)")
                elif command == "update_settings":
                    # Validated settings update — any bad value raises ValueError
                    # which api.py translates to 400 so the Flutter toggle gets
                    # feedback instead of silently pretending to work.
                    try:
                        payload = payload or {}
                        config_updates = {
                            key: value for key, value in payload.items()
                            if key not in {"telegram_enabled", "alarm_enabled"}
                        }
                        _config.UpdateThresholds(config_updates)
                        for name in _CONFIG_NAMES:
                            if name in config_updates:
                                globals()[name] = config_updates[name]
                        # Blink-related thresholds via the monitor's validator
                        if "EarClosedThreshold" in payload:
                            blinks.configure(closed_threshold=payload["EarClosedThreshold"])
                            globals()["EarClosedThreshold"] = payload["EarClosedThreshold"]
                        if "MicrosleepSeconds" in payload:
                            blinks.configure(microsleep_seconds=payload["MicrosleepSeconds"])
                            globals()["MicrosleepSeconds"] = payload["MicrosleepSeconds"]
                        if "telegram_enabled" in payload:
                            telegram.SetTelegramEnabled(bool(payload["telegram_enabled"]))
                        if "alarm_enabled" in payload:
                            alarm_muted = not payload["alarm_enabled"]
                            SetAlarmMuted(alarm_muted)
                        if "SessionLoggingEnabled" in payload:
                            print(f"[api] logging {'enabled' if payload['SessionLoggingEnabled'] else 'disabled'}")
                    except ValueError:
                        raise
                    except Exception as exc:
                        raise ValueError(str(exc))
                    print(f"[api] updated settings: {payload}")

            # When no session is active the pipeline is stopped — just
            # idle and keep draining API commands.
            if inference is None or camera is None:
                if not _idle_logged:
                    print("[idle] Waiting for a session to start...")
                    _idle_logged = True
                time.sleep(0.1)
                continue
            elif _idle_logged:
                print("[session] pipeline active")
                _idle_logged = False

            # Use Condition-based wait instead of spin-poll sleep(0.005)
            # which woke 200×/s for nothing (~8% CPU waste).
            if not hasattr(main, "_infer_version"):
                main._infer_version = -1  # type: ignore[attr-defined]
            result, main._infer_version = inference.wait_for_result(main._infer_version, timeout=0.5)  # type: ignore[attr-defined]
            if result is None:
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

            # ── Paused: freeze evaluation, show the frame only ─────
            if paused:
                if not args.headless:
                    cv2.putText(annotated, "PAUSED", (40, 100),
                                cv2.FONT_HERSHEY_SIMPLEX, 2.0,
                                (255, 255, 0), 3)
                    # Keep the same canvas width so the window doesn't jump.
                    panel = np.zeros((annotated.shape[0], HudPanel, 3),
                                     dtype=np.uint8)
                    annotated = np.hstack([annotated, panel])
                    cv2.imshow("Drowsiness Detection", annotated)
                    key = cv2.waitKey(1) & 0xFF
                    if key == ord("q"):
                        break
                    elif key == ord("p"):
                        paused = False
                continue

            hp = result.head_pose
            if cal_session is not None and cal_session.is_active:
                cal_session.update(hp, Now)
                calibration_status.update(
                    progress=cal_session.progress,
                    valid_samples=cal_session.valid_samples)
                if cal_session.is_finished:
                    try:
                        profile = cal_session.finish()
                        profile.save(ProfilePath)
                        calibration_status.update(
                            state="succeeded", progress=1.0, error=None,
                            valid_samples=cal_session.valid_samples)
                        _needs_calibration = False
                        print(f"[calibration] saved profile (pitch={profile.neutral_pitch:.1f}, "
                              f"yaw={profile.neutral_yaw:.1f}, roll={profile.neutral_roll:.1f})")
                    except (RuntimeError, OSError) as exc:
                        calibration_status.update(
                            state="failed", progress=cal_session.progress,
                            error=str(exc),
                            valid_samples=cal_session.valid_samples)
                        _needs_calibration = True
                        print(f"[calibration] failed: {exc}")
                    cal_session = None

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
                    face_lost_progress = FaceLostAccumulated / FaceLostDrowsyTime
                else:
                    FaceLostAlert = FaceLostAccumulated >= FaceLostCleanTime
                    face_lost_progress = FaceLostAccumulated / FaceLostCleanTime
            else:
                face_lost_progress = 0.0
            if FaceFound and not FaceLost:
                last_seen = frame.copy()

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
            ema_now = ema_drowsy.update(result.max_drowsy)
            # EAR is only trusted when a face pose is valid — prevents
            # spurious eye-closed when half-occluded (ComputeEAR now returns
            # None, but guard with pose_valid for defense in depth).
            eyes_closed = (ema_now > EyesClosedYoloConf
                           or (hp["valid"] and result.ear is not None and result.ear < EarClosedThreshold))
            perclos_now = perclos.update(eyes_closed)
            PerclosAcc, PerclosFired = UpdateTimer(
                perclos_now > PerclosAlertThreshold, PerclosAcc, DeltaTime,
                PerclosAlertTime, Freeze=TimerFrozen)
            # Latches hold while timers are frozen (face lost) — dt=0 stops decay.
            PerclosAlert = latches["perclos"].update(
                PerclosFired, 0.0 if TimerFrozen else DeltaTime)

            # ── Microsleep (EAR-based) — most dangerous ────────────
            # Pass ear directly; BlinkMonitor treats None as eyes-open.
            blink_state = blinks.update(result.ear, Now)
            MicrosleepAlert = latches["microsleep"].update(
                blink_state["microsleep"], 0.0 if TimerFrozen else DeltaTime)
            low_blink_condition = (
                blink_state["rate_ready"] and hp["valid"] and result.ear is not None
                and not blink_state["closed"]
                and blink_state["blinks_per_min"] < BlinkRateAlertPerMin)
            LowBlinkAcc, LowBlinkFired = UpdateTimer(
                low_blink_condition, LowBlinkAcc, DeltaTime,
                BlinkRateAlertTime, Freeze=TimerFrozen)
            LowBlinkAlert = latches["low_blink"].update(
                LowBlinkFired, 0.0 if TimerFrozen else DeltaTime)

            AlertMsg = SelectAlert(
                AlertMessages,
                microsleep=MicrosleepAlert,
                combined=CombinedAlert or HeadDownAlert,
                perclos=PerclosAlert,
                face_lost=FaceLostAlert,
                head_away=HeadAwayAlert,
                low_blink=LowBlinkAlert,
                yolo=YoloAlert,
            )

            if AlertMsg:
                DrawAlertOverlay(annotated, Tick, AlertMsg)
                # Full camera frame (not a crop) + alert type for the caption.
                telegram.TriggerTelegramPhoto(
                    frame, Message=AlertMsg, Cooldown=TelegramCooldown)

            if not args.no_alarm:
                UpdateAlarm(AlertMsg is not None)

            # ── Attention (same as original) ──────────────────────
            rel_pitch = SmoothedPitch - profile.neutral_pitch
            rel_yaw = SmoothedYaw - profile.neutral_yaw
            raw = ComputeAttentionScore(result.max_drowsy, rel_pitch, rel_yaw)
            SmoothedAttention = AttentionSmoothAlpha * SmoothedAttention + (1 - AttentionSmoothAlpha) * raw
            IsFocused = (SmoothedAttention >= AttentionFocusedMin and not HeadDown
                         and not LookingAway and result.max_drowsy < YoloDrowsyWeak
                         and hp["valid"])
            IsUnfocused = (SmoothedAttention >= AttentionUnfocusedMin
                           and SmoothedAttention < AttentionFocusedMin and not HeadDown
                           and not LookingAway and hp["valid"])

            # Publish a JSON-safe state snapshot independently of the OpenCV
            # renderer. Flutter clients consume this same state over the API.
            snapshot_sequence += 1
            monitoring_store.publish(MonitoringSnapshot(
                sequence=snapshot_sequence,
                timestamp=time.time(),
                session_id=session_id,
                trip_started_at=trip_started_at,
                trip_active=trip_active,
                attention=SmoothedAttention,
                perclos=perclos_now,
                ema_drowsy=ema_now,
                ear=result.ear,
                eyes_closed=eyes_closed,
                microsleep=blink_state["microsleep"],
                blinks_per_min=blink_state["blinks_per_min"],
                pitch=SmoothedPitch,
                yaw=SmoothedYaw,
                roll=SmoothedRoll,
                pose_valid=hp["valid"],
                face_found=FaceFound,
                face_lost=FaceLost,
                face_lost_progress=face_lost_progress,
                head_down=HeadDown,
                looking_away=LookingAway,
                head_tilt=HeadTilt,
                focused=IsFocused,
                unfocused=IsUnfocused,
                alert=AlertMsg,
                alert_severity=GetAlertSeverity(AlertMsg),
                alarm_muted=alarm_muted,
                fps=draw_fps,
                calibration_state=calibration_status["state"],
                calibration_progress=calibration_status["progress"],
                calibration_error=calibration_status["error"],
                calibration_valid_samples=calibration_status["valid_samples"],
            ))
            if monitoring_api is not None:
                monitoring_api.publish_frame(frame)

            # ── Session logging (alert transitions + 1 Hz samples) ──
            # Respect SessionLoggingEnabled — the Flutter toggle now actually works.
            do_log = trip_active and globals().get("SessionLoggingEnabled", True)
            if do_log and AlertMsg != prev_alert:
                if AlertMsg:
                    logger.alert_event(AlertMsg, 0.0)
                else:
                    logger.clear_event(prev_alert or "")
                prev_alert = AlertMsg
            if do_log and Now - last_log_time >= 1.0:
                logger.frame_sample(SmoothedAttention, perclos_now, ema_now,
                                    SmoothedPitch, SmoothedYaw, SmoothedRoll,
                                    hp["valid"], AlertMsg,
                                    blinks_per_min=blink_state["blinks_per_min"])
                attention_history.append(SmoothedAttention)
                last_log_time = Now

            DisplayStats.tick()
            if not args.headless:
                if hp["valid"] and hp["rvec"] is not None:
                    DrawHeadAxes(annotated, hp["rvec"], hp["tvec"], hp["nose_pt"])
                draw_ms = DisplayStats.mean("draw")
                draw_fps = 1000.0 / draw_ms if draw_ms > 0 else 0.0
                annotated = RenderHud(annotated, HudState(
                        attention=SmoothedAttention,
                        perclos=perclos_now,
                        max_drowsy=result.max_drowsy,
                        max_alert=result.max_alert,
                        pitch=SmoothedPitch, yaw=SmoothedYaw, roll=SmoothedRoll,
                        pose_valid=hp["valid"],
                        head_down=HeadDown, looking_away=LookingAway,
                        face_lost=FaceLost,
                        alert=AlertMsg,
                        fps=draw_fps,
                        attention_history=attention_history,
                        last_seen=last_seen,
                        face_lost_progress=face_lost_progress,
                ))
                cv2.imshow("Drowsiness Detection", annotated)
                key = cv2.waitKey(1) & 0xFF
                if key == ord("q"):
                    break
                elif key == ord("s"):
                    os.makedirs("captures", exist_ok=True)
                    cv2.imwrite(f"captures/snap_{int(time.time())}.jpg", annotated)
                    print("Snapshot saved to captures/")
                elif key == ord("m"):
                    alarm_muted = not alarm_muted
                    SetAlarmMuted(alarm_muted)
                    print("Alarm muted" if alarm_muted else "Alarm unmuted")
                elif key == ord("p"):
                    paused = True
                    print("PAUSED — press P to resume")
                elif key == ord("r") and args.record is None:
                    recording_enabled = not recording_enabled
                    if recording_enabled:
                        os.makedirs("captures", exist_ok=True)
                        recorder_path = f"captures/rec_{int(time.time())}.mp4"
                        recorder = None
                        print(f"Recording to {recorder_path}")
                    else:
                        print("Recording stopped")
                if recording_enabled and recorder is None:
                    hh, ww = annotated.shape[:2]
                    recorder = cv2.VideoWriter(
                        recorder_path, cv2.VideoWriter_fourcc(*"mp4v"),
                        DisplayFps, (ww, hh))
                if recorder is not None:
                    recorder.write(annotated)
                    if not recording_enabled:
                        recorder.release()
                        recorder = None
            # Frame-rate limiting — applies in both display and headless/api mode
            elapsed = time.monotonic() - Now
            if elapsed < FramePeriod:
                time.sleep(FramePeriod - elapsed)
            DisplayStats.tock("draw")

    finally:
        _stop_pipeline()
        if monitoring_api is not None:
            monitoring_api.stop()
        logger.close()
        if recorder is not None:
            recorder.release()
        telegram.StopTelegramWorker()
        if not args.headless:
            cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
