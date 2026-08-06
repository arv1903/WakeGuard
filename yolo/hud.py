"""Anti-aliased HUD rendering with Pillow."""

import math
import time
from collections import deque
from dataclasses import dataclass, field

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from .config import HudPanel, NightMode


@dataclass
class HudState:
    attention: float = 100.0
    perclos: float = 0.0
    max_drowsy: float = 0.0
    max_alert: float = 0.0
    pitch: float = 0.0
    yaw: float = 0.0
    roll: float = 0.0
    pose_valid: bool = False
    head_down: bool = False
    looking_away: bool = False
    face_lost: bool = False
    alert: str | None = None
    fps: float = 0.0
    attention_history: deque = field(default_factory=lambda: deque(maxlen=60))
    last_seen: np.ndarray | None = None
    face_lost_progress: float = 0.0


def _font(size):
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf", size)
    except OSError:
        return ImageFont.load_default()


# Static panel (rounded translucent sidebar + title), cached per size.
_panel_cache = {}


def _static_panel(w, h, panel_w):
    key = (w, h)
    if key not in _panel_cache:
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        d.rounded_rectangle((w - panel_w, 0, w - 8, h - 8), 16,
                            fill=(18, 18, 24, 220))
        d.text((w - panel_w + 16, 16), "ATTENTION", font=_font(18),
               fill=(200, 200, 210, 255))
        _panel_cache[key] = layer
    return _panel_cache[key]


def _vignette(size, alpha):
    """Radial-gradient darkening layer with the given max alpha."""
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = w / 2, h / 2
    max_r = math.hypot(cx, cy)
    steps = 24
    for i in range(steps):
        r0 = max_r * (1 - (i + 1) / steps)
        r1 = max_r * (1 - i / steps)
        a = int(alpha * (1 - i / steps) ** 2)
        d.ellipse((cx - r1, cy - r1, cx + r1, cy + r1), fill=(0, 0, 0, a))
        d.ellipse((cx - r0, cy - r0, cx + r0, cy + r0), fill=(0, 0, 0, 0))
    return layer


ALERT_SEVERITY = {
    "MICROSLEEP": 4,
    "HEAD NODDING": 3,
    "FATIGUE": 3,
    "FACE LOST": 3,
    "DISTRACTED": 2,
    "DROWSINESS": 1,
}


def _severity(alert):
    if not alert:
        return 0
    for key, sev in ALERT_SEVERITY.items():
        if key in alert.upper():
            return sev
    return 1


def RenderHud(frame: np.ndarray, state: HudState) -> np.ndarray:
    """Composite the HUD over a BGR frame and return the annotated frame."""
    img = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).convert("RGBA")
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    W, H = img.size
    panel_w = HudPanel

    # Static panel + attention gauge
    overlay.alpha_composite(_static_panel(W, H, panel_w))
    cx, cy, r = W - panel_w + 118, 120, 80
    frac = max(0.0, min(1.0, state.attention / 100.0))
    color = ((76, 175, 80, 255) if frac >= 0.8 else
             (255, 193, 7, 255) if frac >= 0.5 else (244, 67, 54, 255))
    d.arc((cx - r, cy - r, cx + r, cy + r), start=180, end=0,
          fill=(60, 60, 70, 255), width=10)
    d.arc((cx - r, cy - r, cx + r, cy + r), start=180,
          end=180 - 180 * frac, fill=color, width=10)
    d.text((cx - 20, cy - 16), f"{state.attention:.0f}", font=_font(28),
           fill=(255, 255, 255, 255))

    # Sparkline of attention history
    if len(state.attention_history) > 1:
        pts = []
        hist = list(state.attention_history)
        n = len(hist)
        base_x = W - panel_w + 20
        for i, val in enumerate(hist):
            x = base_x + i * ((panel_w - 40) / max(n - 1, 1))
            y = 240 - (val / 100.0) * 90
            pts.append((x, y))
        d.line(pts, fill=(100, 200, 255, 255), width=2)

    # Value bars
    y = 280
    for label, value in (("DROWSY", state.max_drowsy),
                         ("PERCLOS", state.perclos),
                         ("FPS", min(state.fps / 60.0, 1.0))):
        d.text((W - panel_w + 20, y), label, font=_font(14),
               fill=(150, 150, 160, 255))
        filled = int(value * (panel_w - 40))
        d.rounded_rectangle((W - panel_w + 20, y + 18, W - 28, y + 30),
                            radius=6, fill=(60, 60, 70, 255))
        d.rounded_rectangle((W - panel_w + 20, y + 18,
                             W - panel_w + 20 + filled, y + 30),
                            radius=6, fill=(100, 180, 255, 255))
        y += 44

    # Alert banner + severity pulse
    sev = _severity(state.alert)
    if state.alert and sev:
        pulse = 0.5 + 0.5 * math.sin(2 * math.pi * 2.0 * (time.monotonic() % 1.0))
        color = (244, 67, 54, 255) if sev >= 3 else (255, 152, 0, 255)
        d.rounded_rectangle((20, 20, W - panel_w - 20, 72), radius=12,
                            fill=color)
        d.text((40, 34), state.alert, font=_font(20), fill=(255, 255, 255, 255))
        overlay.alpha_composite(_vignette(img.size, int(40 + 50 * sev * pulse)))
        d.rectangle((0, 0, W - 1, H - 1), outline=(244, 67, 54, 255),
                    width=int(4 + 4 * sev * pulse))

    # Face-lost indicator + countdown ring on last-seen thumbnail
    if state.face_lost:
        d.text((W - panel_w + 20, H - 60), "FACE LOST", font=_font(16),
               fill=(244, 67, 54, 255))
        if state.last_seen is not None:
            thumb_w, thumb_h = 120, 90
            thumb = cv2.resize(state.last_seen, (thumb_w, thumb_h))
            thumb_img = Image.fromarray(cv2.cvtColor(thumb, cv2.COLOR_BGR2RGB))
            tx, ty = W - panel_w + 20, H - 170
            overlay.alpha_composite(thumb_img.convert("RGBA"), (tx, ty))
            prog = max(0.0, min(1.0, state.face_lost_progress))
            d.arc((tx - 6, ty - 6, tx + thumb_w + 6, ty + thumb_h + 6),
                  start=90, end=90 - 360 * prog, fill=(244, 67, 54, 255),
                  width=5)

    if NightMode:
        overlay = Image.eval(overlay, lambda v: v // 2)

    img = Image.alpha_composite(img, overlay)
    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
