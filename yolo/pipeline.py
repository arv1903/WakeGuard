"""Threaded capture → inference → display pipeline."""
import threading
import time
import traceback
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


def _normalized_landmarks(mp_result):
    """Return the first face's landmarks as a plain list, across MediaPipe versions.

    MediaPipe < 1.0 wraps landmarks in a ``NormalizedLandmarkList`` exposing a
    ``.landmark`` attribute; 1.0+ returns a plain ``list[NormalizedLandmark]``
    directly. This helper normalizes both shapes to a plain list so callers
    (``ComputeEAR``) never see an ``AttributeError`` on the wrapper.

    Args:
        mp_result: A MediaPipe FaceLandmarkerResult (or None).

    Returns:
        list[NormalizedLandmark] | None: the first face's landmarks, or None
        when no face was detected.
    """
    if mp_result is None or not getattr(mp_result, "face_landmarks", None):
        return None
    face = mp_result.face_landmarks[0]
    return face.landmark if hasattr(face, "landmark") else face


@dataclass
class FrameResult:
    frame: np.ndarray
    timestamp: float
    boxes: list = field(default_factory=list)
    max_drowsy: float = 0.0
    max_alert: float = 0.0
    face_found: bool = False
    head_pose: dict = field(
        default_factory=lambda: {"pitch": 0.0, "yaw": 0.0, "roll": 0.0,
                                 "valid": False, "rvec": None, "tvec": None,
                                 "nose_pt": None})
    ear: float | None = None


class CameraThread(threading.Thread):
    """Reads frames from a camera index or video file with auto-recovery."""

    def __init__(self, source, width=640, height=480, flip=True):
        super().__init__(daemon=True, name="camera")
        self._source = source
        self._width = width
        self._height = height
        self._latest = LatestValue()
        self._stop = threading.Event()
        self._is_video = isinstance(source, str) and not source.isdigit()
        self._eof = False
        self._flip = flip if not self._is_video else False
        self._cap = cv2.VideoCapture(source)
        ok_w = self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        ok_h = self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        if not ok_w or not ok_h:
            print(f"[camera] warning: could not set capture size to {width}x{height} "
                  f"(backend returned {ok_w}/{ok_h}); using driver default")

    def run(self) -> None:
        failures = 0
        backoff = 0.05
        while not self._stop.is_set():
            ok, frame = self._cap.read()
            if not ok:
                if self._is_video:
                    self._eof = True
                    break
                failures += 1
                if failures >= 30:
                    if failures == 30:
                        print(f"[camera] read stalled ({failures} failures); attempting re-acquisition...")
                    self._cap.release()
                    self._stop.wait(backoff)
                    self._cap = cv2.VideoCapture(self._source)
                    self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, self._width)
                    self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self._height)
                    backoff = min(backoff * 1.5, 2.0)
                    failures = 0
                else:
                    self._stop.wait(0.01)
                continue
            failures = 0
            backoff = 0.05
            if self._flip:
                frame = cv2.flip(frame, 1)
            self._latest.publish(frame)

    def stop(self) -> None:
        self._stop.set()
        if self.is_alive():
            self.join(timeout=2.0)
        self._cap.release()

    def latest_frame(self):
        return self._latest.latest()

    def wait_for_frame(self, last_version: int, timeout: float | None = 0.5):
        return self._latest.wait_for_new(last_version, timeout=timeout)
    @property
    def is_eof(self) -> bool:
        return self._eof


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
        self._rgb_buffer: np.ndarray | None = None
        # Last YOLO detection and head pose, carried forward while throttled so
        # the consumer never sees false "face lost" or resets timers on skipped frames.
        self._last_boxes = []
        self._last_max_drowsy = 0.0
        self._last_max_alert = 0.0
        self._last_face_found = False
        self._last_ear = None
        self._last_head_pose = {
            "pitch": 0.0, "yaw": 0.0, "roll": 0.0,
            "valid": False, "rvec": None, "tvec": None, "nose_pt": None,
        }

    def run(self) -> None:
        failures = 0
        last_version = -1
        while not self._stop.is_set():
            frame, last_version = self._camera.wait_for_frame(last_version, timeout=0.5)
            if frame is None:
                continue
            try:
                self._publish(self._infer(frame))
                failures = 0
            except Exception:
                # A single bad frame (e.g. a MediaPipe API mismatch) must never
                # kill the feed silently — log it and keep consuming. Back off
                # exponentially on persistent errors to bound CPU burn.
                failures += 1
                if failures <= 3:
                    traceback.print_exc()
                self._stop.wait(min(0.05 * (2 ** min(failures - 1, 5)), 1.0))

    def _infer(self, frame: np.ndarray) -> FrameResult:
        self._frame_counter += 1
        n = self._frame_counter
        result = FrameResult(frame=frame, timestamp=time.monotonic())

        # ── Head pose (every N frames) ──────────────────
        self._stats.tick()
        if n % self._pose_every_n == 0:
            if (self._rgb_buffer is None
                    or self._rgb_buffer.shape != frame.shape
                    or self._rgb_buffer.dtype != frame.dtype):
                self._rgb_buffer = np.empty(frame.shape, dtype=frame.dtype, order="C")
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB, dst=self._rgb_buffer)
            if rgb is not self._rgb_buffer:
                self._rgb_buffer = np.ascontiguousarray(rgb)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=self._rgb_buffer)
            mp_result = self._landmarker.detect_for_video(mp_image, _mp_timestamp_ms())
            result.head_pose = ComputeHeadPose(mp_result, frame.shape)
            if result.head_pose["valid"]:
                mp_landmarks = _normalized_landmarks(mp_result)
                self._last_ear = ComputeEAR(mp_landmarks, frame.shape[1], frame.shape[0])
            else:
                # No face: forget the stale EAR so blink/microsleep logic
                # never trusts a closure that is no longer observable.
                self._last_ear = None
            self._last_head_pose = dict(result.head_pose)
        else:
            result.head_pose = dict(self._last_head_pose)
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
            if driver_box is not None:
                x1, y1, x2, y2, cls_id, conf = driver_box
                if cls_id == 0:
                    result.max_drowsy = conf
                else:
                    result.max_alert = conf
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
        return result

    def _publish(self, result: FrameResult) -> None:
        self._latest.publish(result)

    def stop(self) -> None:
        self._stop.set()
        self.join(timeout=2.0)

    def latest_result(self) -> FrameResult | None:
        return self._latest.latest()

    def wait_for_result(self, last_version: int, timeout: float | None = 0.5):
        return self._latest.wait_for_new(last_version, timeout=timeout)

    def stats(self) -> dict:
        return self._stats.snapshot()
