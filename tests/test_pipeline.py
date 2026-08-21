import numpy as np

from yolo.latest import LatestValue
from yolo.pipeline import InferenceThread, _normalized_landmarks


class FakeBox:
    def __init__(self, x1, y1, x2, y2, cls, conf):
        self.xyxy = [[x1, y1, x2, y2]]
        self.cls = [cls]
        self.conf = [conf]


class FakeModel:
    def __call__(self, frame):
        r = type("R", (), {})()
        r.boxes = [FakeBox(10, 10, 50, 50, 0, 0.9)]  # drowsy box
        return [r]


class FakeCamera:
    def __init__(self):
        self._lv = LatestValue()
        self._lv.publish(np.zeros((60, 80, 3), dtype=np.uint8))

    def latest_frame(self):
        return self._lv.latest()

    def stop(self):
        pass


class FakeModelMulti:
    def __init__(self, boxes):
        self._boxes = boxes

    def __call__(self, frame):
        r = type("R", (), {})()
        r.boxes = [FakeBox(*b) for b in self._boxes]
        return [r]


def test_driver_face_is_largest_box():
    cam = FakeCamera()
    model = FakeModelMulti([
        (10, 10, 50, 50, 0, 0.99),     # small drowsy box (passenger)
        (100, 100, 260, 260, 1, 0.6),  # large alert box (driver)
    ])
    inf = InferenceThread(cam, model, None, pose_every_n=10**9, yolo_every_n=2)
    inf._infer(cam.latest_frame())        # counter=1: YOLO skipped
    r2 = inf._infer(cam.latest_frame())   # counter=2: YOLO runs
    assert r2.max_alert == 0.6            # largest box wins
    assert r2.max_drowsy == 0.0
    assert len(r2.boxes) == 2             # both still drawn for the HUD


def test_yolo_throttle_persists_detection():
    cam = FakeCamera()
    inf = InferenceThread(cam, FakeModel(), None, pose_every_n=10**9, yolo_every_n=2)
    r1 = inf._infer(cam.latest_frame())   # counter=1: YOLO skipped
    r2 = inf._infer(cam.latest_frame())   # counter=2: YOLO runs
    r3 = inf._infer(cam.latest_frame())   # counter=3: YOLO skipped → persist
    assert r2.face_found is True
    assert r2.max_drowsy == 0.9
    assert r3.face_found is True          # carried forward, no face-lost flap
    assert r3.max_drowsy == 0.9
    assert r3.boxes == r2.boxes


def test_head_pose_throttle_persists_pose():
    cam = FakeCamera()
    inf = InferenceThread(cam, FakeModel(), None, pose_every_n=2, yolo_every_n=10**9)
    inf._landmarker = _fake_landmarker_result([_realistic_face_landmarks()])
    r1 = inf._infer(cam.latest_frame())   # counter=1: pose skipped (initial default)
    r2 = inf._infer(cam.latest_frame())   # counter=2: pose runs (valid=True)
    r3 = inf._infer(cam.latest_frame())   # counter=3: pose skipped → must persist valid=True
    assert r2.head_pose["valid"] is True
    assert r3.head_pose["valid"] is True
    assert r3.head_pose["pitch"] == r2.head_pose["pitch"]
    assert r3.ear == r2.ear


# ── MediaPipe landmark API compatibility ──────────────────────────
# MediaPipe < 1.0 returns NormalizedLandmarkList wrappers exposing
# ``.landmark``; 1.0+ returns plain lists of NormalizedLandmark.

def test_normalized_landmarks_old_api_wrapper():
    class FakeFace:
        landmark = ["lm0", "lm1"]
    r = type("R", (), {"face_landmarks": [FakeFace()]})()
    assert _normalized_landmarks(r) == ["lm0", "lm1"]


def test_normalized_landmarks_new_api_plain_list():
    r = type("R", (), {"face_landmarks": [["lm0", "lm1"]]})()
    assert _normalized_landmarks(r) == ["lm0", "lm1"]


def test_normalized_landmarks_no_face_returns_none():
    assert _normalized_landmarks(None) is None
    r = type("R", (), {"face_landmarks": []})()
    assert _normalized_landmarks(r) is None


def _fake_landmarker_result(faces):
    """A minimal landmarker double returning the given face shapes."""
    return type("LM", (), {
        "detect_for_video": lambda self, img, ts: type(
            "R", (), {"face_landmarks": faces})(),
    })()


def _realistic_face_landmarks():
    """468 normalized landmarks with distinct head-pose points so that
    ComputeHeadPose's solvePnP succeeds (valid=True) — exercising the
    exact code path that crashed on MediaPipe 1.0."""
    class FakeLM:
        def __init__(self, x, y):
            self.x, self.y = x, y

    lms = [FakeLM(0.0, 0.0) for _ in range(468)]
    # Indices used by ComputeHeadPose (nose, chin, eye/mouth corners).
    for i, (x, y) in ((1, (0.5, 0.4)), (152, (0.5, 0.6)), (33, (0.3, 0.5)),
                      (263, (0.7, 0.5)), (61, (0.35, 0.65)), (291, (0.65, 0.65))):
        lms[i] = FakeLM(x, y)
    return lms


def test_infer_accepts_plain_list_landmarks():
    # MediaPipe 1.0 shape end-to-end: pose valid + plain-list landmarks
    # must not raise AttributeError (the original crash) and must produce EAR.
    cam = FakeCamera()
    inf = InferenceThread(cam, FakeModel(), None, pose_every_n=1, yolo_every_n=10**9)
    inf._landmarker = _fake_landmarker_result([_realistic_face_landmarks()])
    r = inf._infer(cam.latest_frame())
    assert r.head_pose["valid"] is True
    assert r.ear is not None


def test_infer_accepts_wrapper_landmarks():
    # MediaPipe < 1.0 shape end-to-end: wrapper object exposing .landmark.
    cam = FakeCamera()
    inf = InferenceThread(cam, FakeModel(), None, pose_every_n=1, yolo_every_n=10**9)

    class FakeFace:
        # Old-API NormalizedLandmarkList: subscriptable AND exposes .landmark.
        landmark = _realistic_face_landmarks()

        def __getitem__(self, i):
            return self.landmark[i]

    inf._landmarker = _fake_landmarker_result([FakeFace()])
    r = inf._infer(cam.latest_frame())
    assert r.head_pose["valid"] is True
    assert r.ear is not None

