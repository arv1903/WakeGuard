"""OpenCV overlays used on the camera frame."""

import cv2
import numpy as np

from .config import focal_length


def DrawHeadAxes(Frame, Rvec, Tvec, NosePt, AxisLength=60):
    """Project and draw orientation axes anchored at the nose."""
    h, w = Frame.shape[:2]
    focal = focal_length(w)
    cam_matrix = np.array(
        [[focal, 0, w / 2.0], [0, focal, h / 2.0], [0, 0, 1]],
        dtype=np.float64,
    )
    dist_coeffs = np.zeros((4, 1), dtype=np.float64)
    axis_3d = np.float32([
        [AxisLength, 0, 0],
        [0, AxisLength, 0],
        [0, 0, AxisLength],
    ])
    try:
        axis_2d, _ = cv2.projectPoints(
            axis_3d, Rvec, Tvec, cam_matrix, dist_coeffs)
    except cv2.error:
        return
    origin = tuple(np.int32(NosePt))
    colors = [(255, 80, 80), (80, 255, 80), (80, 160, 255)]
    for pt, color, label in zip(axis_2d, colors, ("X", "Y", "Z")):
        end_pt = tuple(np.int32(pt.ravel()))
        cv2.arrowedLine(Frame, origin, end_pt, color, 2,
                        tipLength=0.15, line_type=cv2.LINE_AA)
        cv2.putText(Frame, label, (end_pt[0] + 5, end_pt[1] - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2, cv2.LINE_AA)
    cv2.circle(Frame, origin, 4, (255, 255, 255), -1, cv2.LINE_AA)


def DrawModernBox(Frame, X1, Y1, X2, Y2, Label, Color):
    """Draw a corner-only bounding box and label."""
    corner_len = 20
    for start, end in (
        ((X1, Y1), (X1 + corner_len, Y1)),
        ((X1, Y1), (X1, Y1 + corner_len)),
        ((X2, Y1), (X2 - corner_len, Y1)),
        ((X2, Y1), (X2, Y1 + corner_len)),
        ((X1, Y2), (X1 + corner_len, Y2)),
        ((X1, Y2), (X1, Y2 - corner_len)),
        ((X2, Y2), (X2 - corner_len, Y2)),
        ((X2, Y2), (X2, Y2 - corner_len)),
    ):
        cv2.line(Frame, start, end, Color, 1)
    font = cv2.FONT_HERSHEY_SIMPLEX
    scale, thickness = 0.6, 2
    (text_w, text_h), _ = cv2.getTextSize(Label, font, scale, thickness)
    bg = Frame.copy()
    cv2.rectangle(bg, (X1, Y1 - text_h - 15),
                  (X1 + text_w + 10, Y1), Color, -1)
    cv2.addWeighted(bg, 0.7, Frame, 0.3, 0, Frame)
    cv2.putText(Frame, Label, (X1 + 5, Y1 - 7), font, scale,
                (255, 255, 255), thickness, cv2.LINE_AA)


def DrawAlertOverlay(Frame, Tick, Message="DROWSINESS DETECTED!"):
    """Flash a full-frame alert overlay and message band."""
    h, w = Frame.shape[:2]
    overlay = Frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, h), (0, 0, 150), -1)
    cv2.addWeighted(overlay, 0.22, Frame, 0.78, 0, Frame)
    if (Tick // 10) % 2 == 0:
        band_h = 68
        band_y = h // 2 - band_h // 2
        cv2.rectangle(Frame, (0, band_y), (w, band_y + band_h),
                      (0, 0, 200), -1)
        cv2.rectangle(Frame, (0, band_y), (w, band_y + band_h),
                      (0, 0, 100), 3)
        text_size = cv2.getTextSize(
            Message, cv2.FONT_HERSHEY_DUPLEX, 1.05, 2)[0]
        tx = (w - text_size[0]) // 2
        ty = band_y + (band_h + text_size[1]) // 2
        cv2.putText(Frame, Message, (tx + 2, ty + 2),
                    cv2.FONT_HERSHEY_DUPLEX, 1.05, (0, 0, 80), 2)
        cv2.putText(Frame, Message, (tx, ty), cv2.FONT_HERSHEY_DUPLEX,
                    1.05, (255, 255, 255), 2)
