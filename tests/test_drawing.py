import numpy as np

from yolo.drawing import DrawYoloBoxes


def _canvas(width=320, height=240):
    return np.zeros((height, width, 3), dtype=np.uint8)


def test_draw_drowsy_box_red_at_native_coords():
    frame = _canvas()
    DrawYoloBoxes(frame, [(10, 10, 30, 30, 0, 0.87)])
    # Vertical corner bracket spans x=10 from y=10..30.
    assert tuple(frame[20, 10]) == (0, 0, 255)


def test_draw_alert_box_green():
    frame = _canvas()
    DrawYoloBoxes(frame, [(10, 10, 30, 30, 1, 0.92)])
    assert tuple(frame[20, 10]) == (0, 200, 0)


def test_draw_boxes_scales_coords_onto_smaller_canvas():
    # Box was produced on a 2x-wider source; Scale=0.5 maps it back down.
    frame = _canvas(width=160, height=120)
    DrawYoloBoxes(frame, [(20, 20, 60, 60, 0, 0.77)], Scale=0.5)
    # Mapped vertical bracket: x=10, y=10..30.
    assert tuple(frame[20, 10]) == (0, 0, 255)
    # Nothing drawn outside the mapped box.
    assert tuple(frame[70, 10]) == (0, 0, 0)


def test_draw_boxes_scales_coords_up():
    frame = _canvas()
    DrawYoloBoxes(frame, [(10, 10, 30, 30, 0, 0.87)], Scale=2.0)
    # Mapped vertical bracket: x=20, y=20..40.
    assert tuple(frame[40, 20]) == (0, 0, 255)


def test_draw_no_boxes_leaves_canvas_unchanged():
    frame = _canvas()
    DrawYoloBoxes(frame, [])
    assert np.count_nonzero(frame) == 0
