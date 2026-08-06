"""Render the HUD onto a synthetic frame and save a PNG for visual QA."""
import os
import sys

import numpy as np
import cv2

# Make the project root importable when run directly from scripts/.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from yolo.hud import HudState, RenderHud


def main():
    frame = np.full((720, 1280, 3), 30, dtype=np.uint8)
    for y in range(0, 720, 40):
        cv2.rectangle(frame, (0, y), (1280, y + 2), (45, 45, 50), -1)
    state = HudState(attention=72.0, perclos=0.35, max_drowsy=0.4,
                     pitch=-18.0, alert="HEAD NODDING - DROWSY!")
    out = RenderHud(frame, state)
    cv2.imwrite("hud_preview.png", out)
    print("Wrote hud_preview.png")


if __name__ == "__main__":
    main()
