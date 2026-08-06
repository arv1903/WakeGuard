"""Startup diagnostics: check models, camera, and optional integrations."""

import os

import cv2


def RunDiagnostics(source, no_alarm=False, no_telegram=False) -> list:
    """Return a list of problem strings. Empty list = all good."""
    problems = []
    for f in ("best.pt", "face_landmarker.task"):
        if not os.path.exists(f):
            problems.append(f"Missing model file: {f}")
    if not no_alarm and not os.path.exists("alert.mp3"):
        problems.append("Missing alarm file: alert.mp3")
    cap = cv2.VideoCapture(source)
    ok, _ = cap.read()
    cap.release()
    if not ok:
        problems.append(f"Cannot read from source: {source}")
    if not no_telegram and not (os.environ.get("TELEGRAM_BOT_TOKEN")
                                and os.environ.get("TELEGRAM_CHAT_ID")):
        problems.append("Telegram enabled but TELEGRAM_BOT_TOKEN / "
                        "TELEGRAM_CHAT_ID are not set")
    return problems
