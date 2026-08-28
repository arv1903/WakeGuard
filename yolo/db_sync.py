"""Background JSONL → Supabase sync.

Reads new lines appended to the session JSONL log and batches them into
the Supabase ``telemetry``, ``alert_events``, and ``sessions`` tables.
The display thread is never touched — all I/O happens here.

Usage::

    reader = JsonlTailReader(db_client, log_path)
    reader.start()
    # … later, when a session starts …
    reader.bind_session(session_id, device_id, user_id)
    # … when a session stops …
    reader.unbind_session()
    # … on shutdown …
    reader.stop()
"""

from __future__ import annotations

import json
import os
import threading
import time
from datetime import datetime, timezone
from typing import Any


class JsonlTailReader:
    """Daemon thread that tails a JSONL file and upserts rows to Supabase."""

    def __init__(
        self,
        db: Any,
        log_path: str,
        flush_interval: float = 5.0,
        batch_size: int = 100,
    ):
        self._db = db
        self._log_path = log_path
        self._flush_interval = flush_interval
        self._batch_size = batch_size

        # Current session context (set by bind_session / unbind_session)
        self._session_id: str | None = None
        self._device_id: str | None = None
        self._user_id: str | None = None

        # Running session stats (accumulated across flushes)
        self._stats_started_at: float | None = None
        self._stats_ended_at: float | None = None
        self._stats_attentions: list[float] = []
        self._stats_perclos: list[float] = []
        self._stats_alert_names: list[str] = []

        # Pending rows per table
        self._pending: dict[str, list[dict]] = {}
        self._lock = threading.Lock()

        # Thread control
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    # ── Lifecycle ──────────────────────────────────────────────────────

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._run, name="jsonl-db-sync", daemon=True
        )
        self._thread.start()
        print("[db-sync] started")

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=5.0)
            self._thread = None
        # Final best-effort flush
        self._flush_pending()
        print("[db-sync] stopped")

    # ── Session binding ────────────────────────────────────────────────

    def bind_session(
        self, session_id: str, device_id: str | None = None,
        user_id: str | None = None,
    ) -> None:
        """Tell the reader which session_id to tag rows with."""
        self._session_id = session_id
        self._device_id = device_id
        self._user_id = user_id

    def unbind_session(self) -> None:
        """Called when a session ends — flush remaining rows."""
        self._session_id = None
        self._flush_pending()

    # ── Main loop ──────────────────────────────────────────────────────

    def _run(self) -> None:
        # Wait for the file to exist
        while not self._stop_event.is_set() and not os.path.exists(self._log_path):
            self._stop_event.wait(1.0)

        if self._stop_event.is_set():
            return

        # Seek to end — only sync NEW lines written after this point
        try:
            with open(self._log_path, "r", encoding="utf-8") as f:
                f.seek(0, 2)  # seek to end
                file_end = f.tell()
        except OSError:
            return

        last_flush = time.monotonic()

        while not self._stop_event.is_set():
            # Read new lines
            try:
                new_lines = self._read_new_lines(file_end)
                if new_lines:
                    file_end += sum(len(line.encode("utf-8")) + 1 for line in new_lines)
                    self._process_lines(new_lines)
            except Exception as exc:
                print(f"[db-sync] read error: {exc}")
                self._stop_event.wait(2.0)
                continue

            # Periodic flush
            now = time.monotonic()
            if now - last_flush >= self._flush_interval:
                self._flush_pending()
                last_flush = now

            # Sleep briefly to avoid busy-waiting
            self._stop_event.wait(0.5)

        # Final read: pick up any lines written during the last sleep
        try:
            new_lines = self._read_new_lines(file_end)
            if new_lines:
                self._process_lines(new_lines)
        except Exception:
            pass

    def _read_new_lines(self, from_offset: int) -> list[str]:
        """Read lines appended since *from_offset*."""
        lines: list[str] = []
        try:
            with open(self._log_path, "r", encoding="utf-8") as f:
                f.seek(from_offset)
                while True:
                    line = f.readline()
                    if not line:
                        break
                    line = line.strip()
                    if line:
                        lines.append(line)
        except OSError:
            pass
        return lines

    def _process_lines(self, lines: list[str]) -> None:
        """Parse JSONL lines and queue rows for DB insertion."""
        session_start_events = []
        session_stop_events = []
        frame_rows = []
        alert_rows = []

        for raw in lines:
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue

            ev_type = ev.get("type")
            sid = ev.get("session_id") or self._session_id
            ts = self._iso_ts(ev.get("ts"))

            if ev_type == "session_start":
                session_start_events.append(ev)
            elif ev_type == "session_stop":
                session_stop_events.append(ev)
            elif ev_type == "frame" and sid:
                frame_rows.append({
                    "session_id": sid,
                    "ts": ts,
                    "attention": ev.get("attention"),
                    "perclos": ev.get("perclos"),
                    "ema_drowsy": ev.get("ema_drowsy"),
                    "pitch": ev.get("pitch"),
                    "yaw": ev.get("yaw"),
                    "roll": ev.get("roll"),
                    "pose_valid": ev.get("pose_valid"),
                    "alert": ev.get("alert"),
                    "blinks_per_min": ev.get("blinks_per_min"),
                })
                # Accumulate stats for session summary
                att = ev.get("attention")
                if att is not None:
                    self._stats_attentions.append(float(att))
                pc = ev.get("perclos")
                if pc is not None:
                    self._stats_perclos.append(float(pc))
            elif ev_type == "alert" and sid:
                alert_rows.append({
                    "session_id": sid,
                    "ts": ts,
                    "alert": ev.get("alert", ""),
                    "event_type": "alert",
                    "fired_for": ev.get("fired_for"),
                })
                alert_name = ev.get("alert", "")
                if alert_name:
                    self._stats_alert_names.append(alert_name)
            elif ev_type == "clear" and sid:
                alert_rows.append({
                    "session_id": sid,
                    "ts": ts,
                    "alert": ev.get("alert", ""),
                    "event_type": "clear",
                    "fired_for": None,
                })

        with self._lock:
            # Session start → insert into sessions table
            for ev in session_start_events:
                sid = ev.get("session_id") or self._session_id
                ts_val = ev.get("ts")
                if ts_val is not None:
                    self._stats_started_at = float(ts_val)
                if sid:
                    self._pending.setdefault("sessions", []).append({
                        "id": sid,
                        "device_id": self._device_id,
                        "user_id": self._user_id,
                        "started_at": self._iso_ts(ev.get("ts")),
                    })

            # Session stop → update sessions table with summary stats
            for ev in session_stop_events:
                sid = ev.get("session_id") or self._session_id
                ts_val = ev.get("ts")
                if ts_val is not None:
                    self._stats_ended_at = float(ts_val)
                if sid:
                    self._pending.setdefault("sessions_stop", []).append({
                        "id": sid,
                        "ended_at": self._iso_ts(ev.get("ts")),
                    })

            # Batch frame samples (chunk into batch_size)
            for i in range(0, len(frame_rows), self._batch_size):
                chunk = frame_rows[i : i + self._batch_size]
                self._pending.setdefault("telemetry", []).extend(chunk)

            # Alert/clear events
            self._pending.setdefault("alert_events", []).extend(alert_rows)

    def _flush_pending(self) -> None:
        """Drain pending rows and insert into Supabase."""
        with self._lock:
            if not self._pending:
                return
            batches = dict(self._pending)
            self._pending.clear()

        total = 0
        for table, rows in batches.items():
            if not rows:
                continue

            if table == "sessions_stop":
                stats = self._compute_session_stats()
                for row in rows:
                    try:
                        update_data = {"ended_at": row["ended_at"], **stats}
                        self._db.table("sessions").update(update_data).eq("id", row["id"]).execute()
                        total += 1
                    except Exception as exc:
                        print(f"[db-sync] session stop update failed: {exc}")
                continue

            try:
                self._db.table(table).insert(rows).execute()
                total += len(rows)
            except Exception as exc:
                print(f"[db-sync] insert into {table} failed: {exc}")
                # Re-queue failed rows for next flush
                with self._lock:
                    self._pending.setdefault(table, []).extend(rows)

        if total > 0:
            print(f"[db-sync] flushed {total} row(s)")

    def _compute_session_stats(self) -> dict:
        """Compute aggregate session statistics from accumulated data."""
        from collections import Counter
        from .score import compute_safety_score

        attentions = self._stats_attentions
        perclos_vals = self._stats_perclos

        att_avg = (sum(attentions) / len(attentions)) if attentions else 0.0
        att_min = min(attentions) if attentions else 0.0
        p_max = max(perclos_vals) if perclos_vals else 0.0

        duration = 0.0
        if self._stats_started_at is not None and self._stats_ended_at is not None:
            duration = max(0.0, self._stats_ended_at - self._stats_started_at)
        elif attentions:
            duration = float(len(attentions))

        alert_count = len(self._stats_alert_names)
        alerts_by_type = dict(Counter(self._stats_alert_names))
        safety_score = compute_safety_score(att_avg, alert_count)

        return {
            "duration_s": round(duration, 2),
            "avg_attention": round(att_avg, 2),
            "avg_perclos": round(p_max, 4),
            "alert_count": alert_count,
            "safety_score": round(safety_score, 2),
            "alerts_by_type": json.dumps(alerts_by_type),
        }

    @staticmethod
    def _iso_ts(ts: Any) -> str:
        """Convert a unix timestamp to ISO 8601 string."""
        if ts is None:
            return datetime.now(timezone.utc).isoformat()
        if isinstance(ts, (int, float)):
            return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
        if isinstance(ts, str):
            return ts  # already ISO
        return datetime.now(timezone.utc).isoformat()
