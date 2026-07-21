"""
Driver Drowsiness & Distraction Detection — Telegram Integration.

Sends a snapshot to a Telegram chat when an alert fires.
Cooldown prevents message spam.
"""

import os
import time
import cv2
import threading
import requests


_LastTelegramMsg = 0.0
_TelegramLock = threading.Lock()


def _SendTelegramPhoto(ImgPath):
    """POST a photo to the Telegram Bot API on a background thread.

    Args:
        ImgPath (str): Path to the image file to send.
    """
    token = os.getenv("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.getenv("TELEGRAM_CHAT_ID", "")
    url = f"https://api.telegram.org/bot{token}/sendPhoto"

    try:
        with open(ImgPath, "rb") as f:
            requests.post(
                url,
                data={"chat_id": chat_id},
                files={"photo": f},
                timeout=10,
            )
    except Exception as e:
        print(f"[WARN] Failed to send Telegram photo: {e}")


def TriggerTelegramPhoto(Frame, Cooldown=30.0):
    """Save frame and dispatch to Telegram if cooldown has elapsed.

    Args:
        Frame (np.ndarray): The camera frame to snapshot.
        Cooldown (float): Minimum seconds between sends.
    """
    global _LastTelegramMsg

    now = time.time()
    with _TelegramLock:
        if now - _LastTelegramMsg < Cooldown:
            return

        token = os.getenv("TELEGRAM_BOT_TOKEN", "")
        chat_id = os.getenv("TELEGRAM_CHAT_ID", "")

        if not token or not chat_id:
            print("[WARN] Telegram credentials not set. Skipping photo.")
            _LastTelegramMsg = now
            return

        _LastTelegramMsg = now
        cv2.imwrite("drowsy_alert.jpg", Frame)
        threading.Thread(
            target=_SendTelegramPhoto,
            args=("drowsy_alert.jpg",),
            daemon=True,
        ).start()
