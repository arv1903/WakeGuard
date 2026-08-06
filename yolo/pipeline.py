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
from .eyes import ComputeEAR

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
        # Last YOLO detection, carried forward while throttled so the
        # consumer never sees a false "face lost" on skipped frames.
        self._last_boxes = []
        self._last_max_drowsy = 0.0
        self._last_max_alert = 0.0
        self._last_face_found = False
        self._last_crop = None
        self._last_ear = None

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
            if result.head_pose["valid"]:
                mp_landmarks = (mp_result.face_landmarks[0].landmark
                                if mp_result.face_landmarks else None)
                self._last_ear = ComputeEAR(mp_landmarks, frame.shape[1], frame.shape[0])
            else:
                # No face: forget the stale EAR so blink/microsleep logic
                # never trusts a closure that is no longer observable.
                self._last_ear = None
        # Persist EAR across throttled pose frames (stable for blink tracking).
        result.ear = self._last_ear
        self._stats.tock("pose")

        # ── YOLO (every N frames) ───────────────────────
        self._stats.tick()
        if n % self._yolo_every_n == 0:
            results = self._model(frame)
            # Track the largest box as the driver's face; a passenger's
            # eyes must never drive the alert state.
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
            crop = None
            if driver_box is not None:
                x1, y1, x2, y2, cls_id, conf = driver_box
                if cls_id == 0:
                    result.max_drowsy = conf
                    crop = frame[y1:y2, x1:x2].copy()
                else:
                    result.max_alert = conf
            if crop is not None:
                self._last_crop = crop
            self._last_boxes = result.boxes
            self._last_max_drowsy = result.max_drowsy
            self._last_max_alert = result.max_alert
            self._last_face_found = result.face_found
        else:
            # Throttled frame: report the last known detection so face-lost
            # logic does not flap on every skipped frame.
            result.boxes = list(self._last_boxes)
            result.max_drowsy = self._last_max_drowsy
            result.max_alert = self._last_max_alert
            result.face_found = self._last_face_found
        self._stats.tock("yolo")

        # Own copy so downstream drawing/Telegram can mutate it safely.
        result.drowsy_crop = self._last_crop
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
