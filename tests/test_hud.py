import numpy as np

from yolo.hud import HudState, RenderHud


def test_render_returns_same_size():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out = RenderHud(frame, HudState(attention=75.0))
    assert out.shape == frame.shape


def test_render_with_alert():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out = RenderHud(frame, HudState(alert="MICROSLEEP - EYES CLOSED! WAKE UP!"))
    assert out.shape == frame.shape and out.dtype == np.uint8


def test_render_face_lost_with_thumbnail():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    state = HudState(face_lost=True, face_lost_progress=0.6,
                     last_seen=np.full((100, 100, 3), 120, dtype=np.uint8))
    out = RenderHud(frame, state)
    assert out.shape == frame.shape
