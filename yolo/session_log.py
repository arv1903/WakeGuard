"""Thread-safe JSONL session logging for post-trip review and training data."""

import json
import os
import threading
import time


class SessionLogger:
    def __init__(self, path: str, session_id: str | None = None):
        d = os.path.dirname(path)
        if d:
            try:
                os.makedirs(d, exist_ok=True)
            except OSError:
                pass
        self._lock = threading.Lock()
        self._closed = False
        try:
            self._f = open(path, "a", encoding="utf-8")
        except OSError as exc:
            # Fall back to in-memory no-op if disk is full / permission denied.
            print(f"[session_log] failed to open {path}: {exc}")
            import io
            self._f = io.StringIO()
            self._closed = False
        self.session_id = session_id

    def set_session_id(self, session_id: str | None) -> None:
        self.session_id = session_id

    def session_start(self, session_id: str) -> None:
        """Record session start and bind future events to *session_id*."""
        self.session_id = session_id
        self._write({"type": "session_start"})

    def session_stop(self, session_id: str) -> None:
        """Record session end for *session_id*."""
        self._write({"type": "session_stop"})
        self.session_id = None

    def _write(self, event: dict) -> None:
        event["ts"] = time.time()
        if self.session_id:
            event["session_id"] = self.session_id
        with self._lock:
            if self._closed:
                return
            try:
                self._f.write(json.dumps(event) + "\n")
                self._f.flush()
                if hasattr(self._f, "fileno"):
                    try:
                        os.fsync(self._f.fileno())
                    except OSError:
                        pass
            except OSError as exc:
                print(f"[session_log] write failed: {exc}")

    def frame_sample(self, attention: float, perclos: float, ema_drowsy: float,
                     pitch: float, yaw: float, roll: float, pose_valid: bool,
                     alert, blinks_per_min: float = 0.0) -> None:
        self._write({"type": "frame",
                     "attention": round(attention, 1),
                     "perclos": round(perclos, 3),
                     "ema_drowsy": round(ema_drowsy, 3),
                     "pitch": round(pitch, 1), "yaw": round(yaw, 1),
                     "roll": round(roll, 1), "pose_valid": pose_valid,
                     "alert": alert,
                     "blinks_per_min": round(blinks_per_min, 1)})

    def alert_event(self, alert: str, fired_for: float) -> None:
        self._write({"type": "alert", "alert": alert,
                     "fired_for": round(fired_for, 2)})

    def clear_event(self, alert: str) -> None:
        """Record that an alert ended. Distinct from alert starts so summary
        and replay evaluation never count clears as alerts."""
        self._write({"type": "clear", "alert": alert})

    def close(self) -> None:
        with self._lock:
            if self._closed:
                return
            try:
                self._f.close()
            except Exception:
                pass
            self._closed = True
