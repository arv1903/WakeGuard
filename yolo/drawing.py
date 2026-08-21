"""
Driver Drowsiness & Distraction Detection — Visual Overlays.

All drawing helpers: confidence bars, HUD panel, alert overlay,
pose minimap, 3D axes, and modern bounding boxes.
"""

import cv2
import numpy as np

from .config import (
    BarWidth,
    BarHeight,
    HudPanel,
    HeadYawFocused,
    HeadPitchFocusedMin,
    HeadPitchFocusedMax,
    HeadYawThreshold,
    HeadDownPitch,
    focal_length,
)


# ──────────────────────────────────────────────────────────────
#  Low-Level Bars
# ──────────────────────────────────────────────────────────────

def DrawConfidenceBar(Frame, X, Y, Label, Value):
    """Draw a horizontal confidence bar (0–1) with label.

    Args:
        Frame (np.ndarray): Target image.
        X, Y (int): Top-left corner of the bar.
        Label (str): Label text.
        Value (float): Confidence in [0, 1].
    """
    filled = int(np.clip(Value, 0, 1) * BarWidth)
    red = int(255 * Value)
    green = int(255 * (1 - Value))
    color = (0, green, red)

    cv2.rectangle(Frame, (X, Y), (X + BarWidth, Y + BarHeight), (40, 40, 40), -1)
    if filled:
        cv2.rectangle(Frame, (X, Y), (X + filled, Y + BarHeight), color, -1)
    cv2.rectangle(Frame, (X, Y), (X + BarWidth, Y + BarHeight), (90, 90, 90), 1)
    cv2.putText(
        Frame, f"{Label}: {Value:.2f}",
        (X + BarWidth + 5, Y + 10),
        cv2.FONT_HERSHEY_SIMPLEX, 0.37, (200, 200, 200), 1,
    )


def DrawHeadPoseBar(
    Frame, X, Y, Label, Value, Suffix, MaxAngle,
    ActiveColor, InactiveColor, IsActive,
):
    """Draw a head-pose angle bar with colour blending.

    Args:
        Frame (np.ndarray): Target image.
        X, Y (int): Top-left corner.
        Label (str): Label text.
        Value (float): Angle in degrees.
        Suffix (str): Suffix appended to the label (e.g. " DOWN").
        MaxAngle (float): Value at which the bar is full.
        ActiveColor (tuple): BGR when the indicator is active.
        InactiveColor (tuple): BGR when inactive.
        IsActive (bool): Whether this axis is in alert/warning state.
    """
    norm = np.clip(abs(Value) / MaxAngle, 0, 1)
    fill = int(norm * BarWidth)

    blended = tuple(
        int(ActiveColor[i] * norm + InactiveColor[i] * (1 - norm))
        for i in range(3)
    )
    label_color = ActiveColor if IsActive else InactiveColor

    cv2.rectangle(Frame, (X, Y), (X + BarWidth, Y + BarHeight), (40, 40, 40), -1)
    if fill:
        cv2.rectangle(Frame, (X, Y), (X + fill, Y + BarHeight), blended, -1)
    cv2.rectangle(Frame, (X, Y), (X + BarWidth, Y + BarHeight), (90, 90, 90), 1)
    cv2.putText(
        Frame, f"{Label}: {Value:+.0f}{Suffix}",
        (X + BarWidth + 5, Y + 10),
        cv2.FONT_HERSHEY_SIMPLEX, 0.37, label_color, 1,
    )


# ──────────────────────────────────────────────────────────────
#  Attention Gauge
# ──────────────────────────────────────────────────────────────

def DrawAttentionGauge(Frame, X, Y, Width, Score):
    """Draw the tri-colour attention gauge at the top of the HUD.

    Args:
        Frame (np.ndarray): Target image.
        X, Y (int): Top-left corner.
        Width (int): Width in pixels.
        Score (float): Attention score 0–100.
    """
    h = 22
    cv2.rectangle(Frame, (X, Y - 2), (X + Width + 2, Y + h + 2), (40, 40, 50), -1)
    cv2.rectangle(Frame, (X, Y - 2), (X + Width + 2, Y + h + 2), (70, 70, 90), 1)

    sections = [
        (0, 50, (50, 50, 200)),
        (50, 80, (40, 140, 220)),
        (80, 101, (30, 180, 60)),
    ]
    for lo, hi, color in sections:
        lx = X + int(lo * Width / 100)
        rx = X + int(hi * Width / 100)
        cv2.rectangle(Frame, (lx, Y), (rx, Y + h), color, -1)

    cx = X + int(np.clip(Score, 0, 100) * Width / 100)
    cv2.line(Frame, (cx, Y - 4), (cx, Y + h + 4), (255, 255, 255), 2)
    cv2.circle(Frame, (cx, Y + h // 2), 7, (255, 255, 255), -1)
    cv2.circle(Frame, (cx, Y + h // 2), 3, (20, 20, 30), -1)

    cv2.putText(
        Frame, f"ATTENTION: {Score:.0f}%",
        (X, Y - 7),
        cv2.FONT_HERSHEY_SIMPLEX, 0.42, (180, 200, 255), 1,
    )

    labels = [
        ("LOW", X),
        ("MID", X + int(50 * Width / 100) - 10),
        ("FOCUSED", X + int(80 * Width / 100) - 20),
    ]
    for text, lx in labels:
        cv2.putText(
            Frame, text, (lx, Y + h + 13),
            cv2.FONT_HERSHEY_SIMPLEX, 0.30, (140, 140, 160), 1,
        )


# ──────────────────────────────────────────────────────────────
#  Pose Minimap
# ──────────────────────────────────────────────────────────────

def DrawPoseMinimap(
    Frame, X, Y, Size, Pitch, Yaw,
    HeadDown, LookingAway, HeadTilt,
):
    """Draw the head-pose minimap with zone overlays and dot indicator.

    Args:
        Frame (np.ndarray): Target image.
        X, Y (int): Top-left corner of the square.
        Size (int): Side length in pixels.
        Pitch, Yaw (float): Current angles.
        HeadDown, LookingAway, HeadTilt (bool): State flags (unused visually
            but kept for future styling).
    """
    half = Size // 2
    cx, cy = X + half, Y + half

    cv2.rectangle(Frame, (X, Y), (X + Size, Y + Size), (30, 30, 42), -1)
    cv2.rectangle(Frame, (X, Y), (X + Size, Y + Size), (70, 70, 90), 1)

    def yaw_px(v):
        return cx + int(np.clip(v / 60.0, -1, 1) * half)

    def pitch_px(v):
        return cy - int(np.clip(v / 45.0, -1, 1) * half)

    # Focused zone (green)
    zone_focused = [
        (yaw_px(-HeadYawFocused), pitch_px(HeadPitchFocusedMax)),
        (yaw_px(HeadYawFocused), pitch_px(HeadPitchFocusedMin)),
    ]
    cv2.rectangle(Frame, zone_focused[0], zone_focused[1], (40, 140, 30), -1)

    # Side zones (blue)
    zone_l = [
        (X, pitch_px(HeadPitchFocusedMax)),
        (yaw_px(-HeadYawFocused), pitch_px(HeadPitchFocusedMin)),
    ]
    zone_r = [
        (yaw_px(HeadYawFocused), pitch_px(HeadPitchFocusedMax)),
        (X + Size, pitch_px(HeadPitchFocusedMin)),
    ]
    cv2.rectangle(Frame, zone_l[0], zone_l[1], (40, 100, 180), -1)
    cv2.rectangle(Frame, zone_r[0], zone_r[1], (40, 100, 180), -1)

    # Warning transition zones (light blue)
    yaw_half_width = yaw_px(HeadYawThreshold) - cx
    zone_warn_l = [
        (cx - half, pitch_px(HeadPitchFocusedMax)),
        (cx - yaw_half_width, pitch_px(HeadPitchFocusedMin)),
    ]
    zone_warn_r = [
        (cx + yaw_half_width, pitch_px(HeadPitchFocusedMax)),
        (cx + half, pitch_px(HeadPitchFocusedMin)),
    ]
    cv2.rectangle(Frame, zone_warn_l[0], zone_warn_l[1], (30, 140, 210), -1)
    cv2.rectangle(Frame, zone_warn_r[0], zone_warn_r[1], (30, 140, 210), -1)

    # Head-down danger zone (dark purple)
    hd_y = pitch_px(-HeadDownPitch)
    cv2.rectangle(Frame, (X, hd_y), (X + Size, Y + Size), (30, 20, 140), -1)

    # Crosshairs
    cv2.line(Frame, (cx, Y), (cx, Y + Size), (55, 55, 70), 1)
    cv2.line(Frame, (X, cy), (X + Size, cy), (55, 55, 70), 1)

    # Current pose dot
    dot_x = yaw_px(Yaw)
    dot_y = pitch_px(Pitch)
    cv2.circle(Frame, (dot_x, dot_y), 7, (60, 60, 80), -1)
    cv2.circle(Frame, (dot_x, dot_y), 5, (255, 255, 255), -1)
    cv2.circle(Frame, (dot_x, dot_y), 2, (20, 20, 30), -1)

    # Axis labels
    cv2.putText(
        Frame, "P/Y", (X + 2, Y + 10),
        cv2.FONT_HERSHEY_SIMPLEX, 0.30, (120, 120, 140), 1,
    )
    cv2.putText(
        Frame, "YAW", (X + Size - 32, Y + Size - 4),
        cv2.FONT_HERSHEY_SIMPLEX, 0.28, (120, 120, 140), 1,
    )
    cv2.putText(
        Frame, "PITCH", (cx - 16, Y + Size - 4),
        cv2.FONT_HERSHEY_SIMPLEX, 0.28, (120, 120, 140), 1,
    )


# ──────────────────────────────────────────────────────────────
#  3D Head Axes (on camera feed)
# ──────────────────────────────────────────────────────────────

def DrawHeadAxes(Frame, Rvec, Tvec, NosePt, AxisLength=60):
    """Project and draw RGB 3D orientation axes anchored at the nose.

    X = red, Y = green, Z = blue.

    Args:
        Frame (np.ndarray): Target image.
        Rvec, Tvec: solvePnP rotation & translation vectors.
        NosePt (np.ndarray): (2,) pixel coordinate of the nose tip.
        AxisLength (int): Length of each axis arrow in pixels.
    """
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
        axis_2d, _ = cv2.projectPoints(axis_3d, Rvec, Tvec, cam_matrix, dist_coeffs)
    except cv2.error:
        return

    origin = tuple(np.int32(NosePt))
    colors = [(255, 80, 80), (80, 255, 80), (80, 160, 255)]
    labels = ["X", "Y", "Z"]

    for i, (pt, color, label) in enumerate(zip(axis_2d, colors, labels)):
        end_pt = tuple(np.int32(pt.ravel()))
        cv2.arrowedLine(Frame, origin, end_pt, color, 2, tipLength=0.15, line_type=cv2.LINE_AA)
        cv2.putText(
            Frame, label,
            (end_pt[0] + 5, end_pt[1] - 5),
            cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2, cv2.LINE_AA,
        )

    cv2.circle(Frame, origin, 4, (255, 255, 255), -1, cv2.LINE_AA)


# ──────────────────────────────────────────────────────────────
#  Modern Corner Bounding Box
# ──────────────────────────────────────────────────────────────

def DrawModernBox(Frame, X1, Y1, X2, Y2, Label, Color):
    """Draw a sleek corner-only bounding box with a semi-transparent label.

    Args:
        Frame (np.ndarray): Target image.
        X1, Y1, X2, Y2 (int): Bounding-box coordinates.
        Label (str): Text label drawn above the box.
        Color (tuple): BGR colour for the lines and label background.
    """
    corner_len = 20
    thickness = 1

    # Top-left
    cv2.line(Frame, (X1, Y1), (X1 + corner_len, Y1), Color, thickness)
    cv2.line(Frame, (X1, Y1), (X1, Y1 + corner_len), Color, thickness)
    # Top-right
    cv2.line(Frame, (X2, Y1), (X2 - corner_len, Y1), Color, thickness)
    cv2.line(Frame, (X2, Y1), (X2, Y1 + corner_len), Color, thickness)
    # Bottom-left
    cv2.line(Frame, (X1, Y2), (X1 + corner_len, Y2), Color, thickness)
    cv2.line(Frame, (X1, Y2), (X1, Y2 - corner_len), Color, thickness)
    # Bottom-right
    cv2.line(Frame, (X2, Y2), (X2 - corner_len, Y2), Color, thickness)
    cv2.line(Frame, (X2, Y2), (X2, Y2 - corner_len), Color, thickness)

    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.6
    txt_thickness = 2
    (text_w, text_h), _ = cv2.getTextSize(Label, font, font_scale, txt_thickness)

    bg = Frame.copy()
    cv2.rectangle(bg, (X1, Y1 - text_h - 15), (X1 + text_w + 10, Y1), Color, -1)
    cv2.addWeighted(bg, 0.7, Frame, 0.3, 0, Frame)
    cv2.putText(
        Frame, Label, (X1 + 5, Y1 - 7),
        font, font_scale, (255, 255, 255), txt_thickness, cv2.LINE_AA,
    )


# ──────────────────────────────────────────────────────────────
#  Alert Overlay
# ──────────────────────────────────────────────────────────────

def DrawAlertOverlay(Frame, Tick, Message="DROWSINESS DETECTED!"):
    """Flash a full-frame alert overlay with a flashing band.

    Args:
        Frame (np.ndarray): Target image.
        Tick (int): Application tick counter, used for blinking.
        Message (str): Alert text displayed in the band.
    """
    h, w = Frame.shape[:2]
    overlay = Frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, h), (0, 0, 150), -1)
    cv2.addWeighted(overlay, 0.22, Frame, 0.78, 0, Frame)

    if (Tick // 10) % 2 == 0:
        band_h = 68
        band_y = h // 2 - band_h // 2
        cv2.rectangle(Frame, (0, band_y), (w, band_y + band_h), (0, 0, 200), -1)
        cv2.rectangle(Frame, (0, band_y), (w, band_y + band_h), (0, 0, 100), 3)

        text_size = cv2.getTextSize(Message, cv2.FONT_HERSHEY_DUPLEX, 1.05, 2)[0]
        tx = (w - text_size[0]) // 2
        ty = band_y + (band_h + text_size[1]) // 2
        cv2.putText(
            Frame, Message, (tx + 2, ty + 2),
            cv2.FONT_HERSHEY_DUPLEX, 1.05, (0, 0, 80), 2,
        )
        cv2.putText(
            Frame, Message, (tx, ty),
            cv2.FONT_HERSHEY_DUPLEX, 1.05, (255, 255, 255), 2,
        )


# ──────────────────────────────────────────────────────────────
#  Drowsy Crop Extraction
# ──────────────────────────────────────────────────────────────

def ExtractDrowsyCrop(Frame, X1, Y1, X2, Y2):
    """Extract an expanded region around a detected face for Telegram.

    Args:
        Frame (np.ndarray): Full camera frame.
        X1, Y1, X2, Y2 (int): Detected face bounding box.

    Returns:
        np.ndarray or None: Cropped region, or None if invalid.
    """
    bw, bh = X2 - X1, Y2 - Y1
    fh, fw = Frame.shape[:2]

    cy1 = max(0, Y1 - int(bh * 2.5))
    cy2 = min(fh, Y2 + int(bh * 4.0))
    cx1 = max(0, X1 - int(bw * 1.5))
    cx2 = min(fw, X2 + int(bw * 1.5))

    if cy2 > cy1 and cx2 > cx1:
        return Frame[cy1:cy2, cx1:cx2]
    return None


# ──────────────────────────────────────────────────────────────
#  Full HUD Panel
# ──────────────────────────────────────────────────────────────

def DrawHud(
    Frame, NoFace, IsAlert, MaxDrowsy, MaxAlert,
    AttentionScore=100.0, HeadPose=None,
    HeadDown=False, LookingAway=False, HeadTilt=False,
    IsFocused=False, IsUnfocused=False, FaceLost=False,
):
    """Render the complete HUD sidebar with all indicators.

    Args:
        Frame (np.ndarray): Target frame (mutated in-place).
        NoFace (bool): True when no face is visible.
        IsAlert (bool): True when any alert is active.
        MaxDrowsy (float): Highest YOLO drowsy confidence [0–1].
        MaxAlert (float): Highest YOLO alert confidence [0–1].
        AttentionScore (float): 0–100 attention score.
        HeadPose (dict | None): Head-pose result (pitch/yaw/roll/valid).
        HeadDown, LookingAway, HeadTilt (bool): State flags.
        IsFocused, IsUnfocused (bool): Attention-zone flags.
        FaceLost (bool): True when YOLO lost the face (head dropped out of view).
    """
    h = Frame.shape[0]
    panel_rect = Frame.copy()
    cv2.rectangle(panel_rect, (0, 0), (HudPanel, h), (16, 16, 26), -1)
    cv2.addWeighted(panel_rect, 0.56, Frame, 0.44, 0, Frame)

    # Title
    cv2.putText(
        Frame, "DROWSINESS DETECTION", (7, 20),
        cv2.FONT_HERSHEY_SIMPLEX, 0.54, (90, 215, 255), 1,
    )
    cv2.line(Frame, (7, 26), (HudPanel - 7, 26), (60, 60, 90), 1)

    # Attention gauge
    gauge_w = HudPanel - 14
    DrawAttentionGauge(Frame, 7, 32, gauge_w, AttentionScore)

    # Eye confidence section
    eye_y = 78
    cv2.line(Frame, (7, eye_y - 6), (HudPanel - 7, eye_y - 6), (60, 60, 90), 1)
    cv2.putText(
        Frame, "EYE CONFIDENCE", (7, eye_y + 8),
        cv2.FONT_HERSHEY_SIMPLEX, 0.42, (200, 200, 200), 1,
    )
    DrawConfidenceBar(Frame, 7, eye_y + 14, "DROWSY", MaxDrowsy)

    # Alert bar
    alert_filled = int(np.clip(MaxAlert, 0, 1) * BarWidth)
    ar = int(255 * (1 - MaxAlert))
    ag = int(255 * MaxAlert)
    alert_color = (0, ag, ar)
    cv2.rectangle(Frame, (7, eye_y + 30), (7 + BarWidth, eye_y + 30 + BarHeight), (40, 40, 40), -1)
    if alert_filled:
        cv2.rectangle(Frame, (7, eye_y + 30), (7 + alert_filled, eye_y + 30 + BarHeight), alert_color, -1)
    cv2.rectangle(Frame, (7, eye_y + 30), (7 + BarWidth, eye_y + 30 + BarHeight), (90, 90, 90), 1)
    cv2.putText(
        Frame, f"ALERT : {MaxAlert:.2f}",
        (7 + BarWidth + 5, eye_y + 30 + 10),
        cv2.FONT_HERSHEY_SIMPLEX, 0.37, (200, 200, 200), 1,
    )

    # Head pose section
    hp_y = eye_y + 55
    cv2.line(Frame, (7, hp_y - 3), (HudPanel - 7, hp_y - 3), (60, 60, 90), 1)
    cv2.putText(
        Frame, "HEAD POSE", (7, hp_y + 11),
        cv2.FONT_HERSHEY_SIMPLEX, 0.42, (180, 200, 255), 1,
    )

    hp = HeadPose or {}
    if hp.get("valid"):
        pitch, yaw, roll = hp["pitch"], hp["yaw"], hp["roll"]
        DrawHeadPoseBar(
            Frame, 7, hp_y + 17, "PITCH", pitch,
            " DOWN" if HeadDown else "", 45.0,
            (0, 60, 255), (200, 200, 200), HeadDown,
        )
        DrawHeadPoseBar(
            Frame, 7, hp_y + 32, "YAW  ", yaw,
            " AWAY" if LookingAway else "", 60.0,
            (0, 160, 255), (200, 200, 200), LookingAway,
        )
        DrawHeadPoseBar(
            Frame, 7, hp_y + 47, "ROLL ", roll,
            "", 30.0,
            (200, 180, 220), (200, 200, 200), HeadTilt,
        )
    else:
        cv2.putText(
            Frame, "no face", (7, hp_y + 26),
            cv2.FONT_HERSHEY_SIMPLEX, 0.40, (120, 120, 140), 1,
        )

    # Pose minimap
    minimap_size = 130
    minimap_x = (HudPanel - minimap_size) // 2
    minimap_y = hp_y + 68
    if hp.get("valid"):
        DrawPoseMinimap(
            Frame, minimap_x, minimap_y, minimap_size,
            hp["pitch"], hp["yaw"], HeadDown, LookingAway, HeadTilt,
        )
    else:
        cv2.rectangle(
            Frame, (minimap_x, minimap_y),
            (minimap_x + minimap_size, minimap_y + minimap_size),
            (30, 30, 42), -1,
        )
        cv2.rectangle(
            Frame, (minimap_x, minimap_y),
            (minimap_x + minimap_size, minimap_y + minimap_size),
            (70, 70, 90), 1,
        )
        cv2.putText(
            Frame, "POSEMAP",
            (minimap_x + 15, minimap_y + minimap_size // 2 + 4),
            cv2.FONT_HERSHEY_SIMPLEX, 0.40, (100, 100, 120), 1,
        )

    # Status footer
    cv2.line(Frame, (7, h - 52), (HudPanel - 7, h - 52), (60, 60, 90), 1)
    status_y = h - 33

    if NoFace and not hp.get("valid") and FaceLost:
        Status, StatusColor = "FACE LOST", (20, 120, 255)
    elif NoFace and not hp.get("valid"):
        Status, StatusColor = "NO FACE", (0, 140, 255)
    elif IsAlert:
        Status, StatusColor = "DROWSY", (40, 40, 255)
    elif HeadDown:
        Status, StatusColor = "HEAD DOWN", (0, 160, 255)
    elif LookingAway:
        Status, StatusColor = "DISTRACTED", (0, 180, 255)
    elif IsUnfocused:
        Status, StatusColor = "UNFOCUSED", (220, 180, 50)
    elif IsFocused:
        Status, StatusColor = "FOCUSED", (30, 220, 40)
    else:
        Status, StatusColor = "ALERT", (30, 200, 30)

    cv2.putText(
        Frame, f"STATUS: {Status}", (7, status_y),
        cv2.FONT_HERSHEY_SIMPLEX, 0.52, StatusColor, 2 if IsAlert else 1,
    )
    cv2.putText(
        Frame, "Q=Quit", (7, h - 13),
        cv2.FONT_HERSHEY_SIMPLEX, 0.33, (110, 110, 110), 1,
    )
