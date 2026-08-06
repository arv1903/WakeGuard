import numpy as np

from yolo import config
from yolo.hud import HudState, RenderHud


def test_render_returns_video_plus_panel():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out = RenderHud(frame, HudState(attention=75.0))
    assert out.shape == (480, 640 + config.HudPanel, 3)
    # The video region must be pixel-identical: the panel sits beside it.
    assert np.array_equal(out[:, :640], frame)


def test_render_with_alert():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out = RenderHud(frame, HudState(alert="MICROSLEEP - EYES CLOSED! WAKE UP!"))
    assert out.shape == (480, 640 + config.HudPanel, 3)
    assert out.dtype == np.uint8
    # Panel region is non-black (content present), video region may show the
    # alert banner — but the panel never covers the camera column.
    assert not np.array_equal(out[:, 640:], np.zeros((480, config.HudPanel, 3),
                                                     dtype=np.uint8))


def test_render_face_lost_with_thumbnail():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    state = HudState(face_lost=True, face_lost_progress=0.6,
                     last_seen=np.full((100, 100, 3), 120, dtype=np.uint8))
    out = RenderHud(frame, state)
    assert out.shape == (480, 640 + config.HudPanel, 3)
    assert np.array_equal(out[:, :640], frame)
