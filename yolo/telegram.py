"""
Driver Drowsiness & Distraction Detection — Telegram Photo Dispatch.

Sends snapshots on a background worker thread so alerting never blocks
the video pipeline. `TriggerTelegramPhoto` enqueues; the worker drains
the queue respecting a cooldown. Each alert sends the full camera frame
with a caption carrying the alert type, the current time, and an
approximate location (IP-geolocated, or from DRIVER_LOCATION_* env vars),
followed by a Telegram location pin when coordinates are known.
"""

import os
import queue
import threading
import time
from datetime import datetime

import requests

from .config import TelegramCooldown

_Queue = queue.Queue(maxsize=4)
_LastSent = 0.0
_CooldownLock = threading.Lock()
_Enabled = True
_Stop = threading.Event()
_Worker = None

# Approximate location cache (IP geolocation result reused across alerts).
_LocationCache = {"ts": 0.0, "data": None}
_LocationCacheSeconds = 600.0


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


def GetApproxLocation(timeout=4.0) -> dict | None:
    """Approximate driver location as ``{lat, lon, name}`` or None.

    Priority: ``DRIVER_LOCATION_LAT`` / ``DRIVER_LOCATION_LON`` env vars
    (optionally ``DRIVER_LOCATION_NAME``), then free IP geolocation via
    ip-api.com. Results are cached for 10 minutes; a failed lookup returns
    None and is retried on the next alert.
    """
    now = time.time()
    if now - _LocationCache["ts"] < _LocationCacheSeconds \
            and _LocationCache["data"] is not None:
        return _LocationCache["data"]

    lat = os.environ.get("DRIVER_LOCATION_LAT")
    lon = os.environ.get("DRIVER_LOCATION_LON")
    if lat and lon:
        try:
            data = {"lat": float(lat), "lon": float(lon),
                    "name": os.environ.get("DRIVER_LOCATION_NAME",
                                           "configured location")}
            _LocationCache.update(ts=now, data=data)
            return data
        except ValueError:
            pass

    try:
        resp = requests.get(
            "https://ip-api.com/json/?fields=status,lat,lon,city,regionName,country"
            "&lang=en", timeout=timeout)
        info = resp.json()
        if info.get("status") == "success":
            data = {
                "lat": info["lat"], "lon": info["lon"],
                "name": ", ".join(x for x in (info.get("city"),
                                              info.get("regionName"),
                                              info.get("country")) if x),
            }
            _LocationCache.update(ts=now, data=data)
            return data
    except (requests.RequestException, ValueError):
        pass
    return None


def _BuildCaption(message, location) -> str:
    """Caption for the alert photo: alert type, time, and location."""
    lines = [f"🚨 {message}" if message else "🚨 Drowsiness Alert",
             f"🕒 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"]
    if location:
        lines.append(f"📍 {location['name']} "
                     f"({location['lat']:.4f}, {location['lon']:.4f})")
    return "\n".join(lines)


def _SendPhoto(image, caption) -> None:
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
            data={"chat_id": chat_id, "caption": caption},
            files={"photo": ("drowsy.jpg", buf, "image/jpeg")},
            timeout=10,
        )
    except requests.RequestException:
        pass  # alerting must never crash the pipeline


def _SendLocation(token, chat_id, location) -> None:
    try:
        requests.post(
            f"https://api.telegram.org/bot{token}/sendLocation",
            data={"chat_id": chat_id,
                  "latitude": location["lat"], "longitude": location["lon"]},
            timeout=10,
        )
    except requests.RequestException:
        pass


def cv2_encode(image):
    import cv2
    ok, buf = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return ok, buf.tobytes() if ok else None


def _Run() -> None:
    global _LastSent
    while not _Stop.is_set():
        try:
            image, message = _Queue.get(timeout=0.5)
        except queue.Empty:
            continue
        with _CooldownLock:
            now = time.time()
            if now - _LastSent < TelegramCooldown:
                continue                       # still in cooldown; drop item
            _LastSent = now
        # Keep the alert photo prompt: bounded lookup (cached results are
        # instant; a cold lookup is capped at 2s).
        location = GetApproxLocation(timeout=2.0)
        _SendPhoto(image, _BuildCaption(message, location))
        if location:
            token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
            chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
            if token and chat_id:
                _SendLocation(token, chat_id, location)


def TriggerTelegramPhoto(image, Message=None, Cooldown=TelegramCooldown) -> None:
    """Enqueue a full-frame snapshot. Returns immediately; the worker sends it."""
    global TelegramCooldown
    TelegramCooldown = Cooldown
    if not _Enabled:
        return
    try:
        _Queue.put_nowait((image, Message))
    except queue.Full:
        pass  # drop oldest alerts rather than block
