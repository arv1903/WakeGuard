"""
Driver Drowsiness & Distraction Detection — Telegram Photo Dispatch.

Sends snapshots on a background worker thread so alerting never blocks
the video pipeline. `TriggerTelegramPhoto` enqueues; the worker drains
the queue respecting a cooldown.
"""

import os
import queue
import threading
import time

import requests

from .config import TelegramCooldown

_Queue = queue.Queue(maxsize=4)
_LastSent = 0.0
_CooldownLock = threading.Lock()
_Enabled = True
_Stop = threading.Event()
_Worker = None


def SetTelegramEnabled(enabled: bool) -> None:
    """Global on/off switch (e.g. --no-telegram)."""
    global _Enabled
    _Enabled = enabled


def StartTelegramWorker() -> None:
    global _Worker
    if _Worker is None or not _Worker.is_alive():
        _Stop.clear()
        _Worker = threading.Thread(target=_Run, daemon=True, name="telegram")
        _Worker.start()


def StopTelegramWorker() -> None:
    _Stop.set()
    if _Worker is not None:
        _Worker.join(timeout=2.0)


def _SendPhoto(image) -> None:
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    if not token or not chat_id:
        return
    ok, buf = cv2_encode(image)
    if not ok:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{token}/sendPhoto",
            data={"chat_id": chat_id},
            files={"photo": ("drowsy.jpg", buf, "image/jpeg")},
            timeout=10,
        )
    except requests.RequestException:
        pass  # alerting must never crash the pipeline


def cv2_encode(image):
    import cv2
    ok, buf = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return ok, buf.tobytes() if ok else None


def _Run() -> None:
    global _LastSent
    while not _Stop.is_set():
        try:
            item = _Queue.get(timeout=0.5)
        except queue.Empty:
            continue
        with _CooldownLock:
            now = time.time()
            if now - _LastSent < TelegramCooldown:
                continue                       # still in cooldown; drop item
            _LastSent = now
        _SendPhoto(item)


def TriggerTelegramPhoto(image, Cooldown=TelegramCooldown) -> None:
    """Enqueue a snapshot. Returns immediately; the worker sends it."""
    global TelegramCooldown
    TelegramCooldown = Cooldown
    if not _Enabled:
        return
    try:
        _Queue.put_nowait(image)
    except queue.Full:
        pass  # drop oldest alerts rather than block
