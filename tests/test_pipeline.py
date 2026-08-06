import numpy as np

from yolo.latest import LatestValue
from yolo.pipeline import InferenceThread


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
