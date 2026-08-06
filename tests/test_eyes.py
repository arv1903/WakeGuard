from yolo.eyes import BlinkMonitor, ComputeEAR


class FakeLM:
    def __init__(self, x, y):
        self.x, self.y = x, y


def _face(eye_half_height):
    """468 landmarks; both eyes are horizontal slits of given half-height.

    Geometry (frame 100x100): left eye spans x=0.30..0.50 with vertical
    pairs (160,144) at x=0.40 and (158,153) at x=0.44; right eye spans
    x=0.50..0.70 with vertical pairs (385,380) at x=0.60 and (387,373) at
    x=0.64. This yields EAR = 10 * eye_half_height.
    """
    lms = [FakeLM(0.5, 0.5) for _ in range(468)]
    # Left eye corners
    lms[33] = FakeLM(0.30, 0.5)
    lms[133] = FakeLM(0.50, 0.5)
    # Left eye vertical pairs
    lms[160] = FakeLM(0.40, 0.5 - eye_half_height)
    lms[144] = FakeLM(0.40, 0.5 + eye_half_height)
    lms[158] = FakeLM(0.44, 0.5 - eye_half_height)
    lms[153] = FakeLM(0.44, 0.5 + eye_half_height)
    # Right eye corners
    lms[362] = FakeLM(0.50, 0.5)
    lms[263] = FakeLM(0.70, 0.5)
    # Right eye vertical pairs
    lms[385] = FakeLM(0.60, 0.5 - eye_half_height)
    lms[380] = FakeLM(0.60, 0.5 + eye_half_height)
    lms[387] = FakeLM(0.64, 0.5 - eye_half_height)
    lms[373] = FakeLM(0.64, 0.5 + eye_half_height)
    return lms


def test_ear_open_eye_is_high():
    ear = ComputeEAR(_face(0.03), 100, 100)   # wide open
    assert ear > 0.25


def test_ear_closed_eye_is_low():
    ear = ComputeEAR(_face(0.002), 100, 100)  # nearly shut
    assert ear < 0.12


def test_blink_detection_and_rate():
    bm = BlinkMonitor(closed_threshold=0.15, min_blink_seconds=0.1)
    bm.update(0.0, now=1.0)   # close
    bm.update(0.0, now=1.2)   # still closed
    state = bm.update(0.5, now=1.4)  # opened after 0.4s → blink
    assert state["blinks_per_min"] == 1
    assert not state["closed"]


def test_microsleep_after_threshold():
    bm = BlinkMonitor(closed_threshold=0.15, microsleep_seconds=1.5)
    bm.update(0.0, now=0.0)
    state = bm.update(0.0, now=2.0)
    assert state["closed"] and state["microsleep"]
