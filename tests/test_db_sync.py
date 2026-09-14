"""Tests for JsonlTailReader — JSONL → Supabase background sync."""

import json
import time
from typing import Any

import pytest

from yolo.db_sync import JsonlTailReader


class _MockTable:
    """Fake Supabase table that records insert/update calls."""

    def __init__(self):
        self.inserts: list[list[dict]] = []
        self.updates: list[tuple[dict, str]] = []
        self._update_data: dict = {}
        self._eq_col: str = ""
        self._eq_val: Any = None

    def insert(self, rows):
        self.inserts.append(list(rows))
        return self

    def update(self, data):
        self._update_data = data
        return self

    def eq(self, col, val):
        self._eq_col = col
        self._eq_val = val
        self.updates.append((dict(self._update_data), f"{col}={val}"))
        return self

    def execute(self):
        return None


class _MockDB:
    """Fake Supabase client that returns _MockTable instances."""

    def __init__(self):
        self.tables: dict[str, _MockTable] = {}

    def table(self, name: str) -> _MockTable:
        if name not in self.tables:
            self.tables[name] = _MockTable()
        return self.tables[name]


class TestJsonlTailReader:
    """Unit tests for the JSONL tail reader."""

    def test_picks_up_new_frame_rows(self, tmp_path):
        """Reader processes new frame lines appended to the JSONL file."""
        log_path = tmp_path / "test.jsonl"
        # Create file with initial content
        with open(log_path, "w") as f:
            f.write(json.dumps({"type": "session_start", "session_id": "s1", "ts": 100.0}) + "\n")

        db = _MockDB()
        reader = JsonlTailReader(db, str(log_path), flush_interval=0.1)
        reader.start()
        reader.bind_session("s1")
        time.sleep(0.15)  # let reader seek to end before writing

        # Append frame events
        with open(log_path, "a") as f:
            for i in range(3):
                f.write(json.dumps({
                    "type": "frame", "session_id": "s1",
                    "ts": 100.0 + i, "attention": 80 + i,
                    "perclos": 0.1, "ema_drowsy": 0.2,
                    "pitch": 5.0, "yaw": -2.0, "roll": 1.0,
                    "pose_valid": True, "alert": None, "blinks_per_min": 15.0,
                }) + "\n")

        # Wait for flush
        time.sleep(0.5)
        reader.stop()

        # Verify telemetry rows were inserted
        telemetry = db.tables.get("telemetry")
        assert telemetry is not None
        assert len(telemetry.inserts) >= 1
        total_rows = sum(len(batch) for batch in telemetry.inserts)
        assert total_rows == 3

    def test_picks_up_alert_rows(self, tmp_path):
        """Reader processes alert events."""
        log_path = tmp_path / "test.jsonl"
        with open(log_path, "w") as f:
            f.write(json.dumps({"type": "session_start", "session_id": "s1", "ts": 100.0}) + "\n")

        db = _MockDB()
        reader = JsonlTailReader(db, str(log_path), flush_interval=0.1)
        reader.start()
        reader.bind_session("s1")
        time.sleep(0.15)

        with open(log_path, "a") as f:
            f.write(json.dumps({"type": "alert", "session_id": "s1", "ts": 101.0, "alert": "MICROSLEEP", "fired_for": 3.0}) + "\n")
            f.write(json.dumps({"type": "clear", "session_id": "s1", "ts": 104.0, "alert": "MICROSLEEP"}) + "\n")

        time.sleep(0.5)
        reader.stop()

        alerts = db.tables.get("alert_events")
        assert alerts is not None
        total_rows = sum(len(batch) for batch in alerts.inserts)
        assert total_rows == 2

    def test_session_start_inserts_session_row(self, tmp_path):
        """Reader creates a sessions row on session_start."""
        log_path = tmp_path / "test.jsonl"
        with open(log_path, "w") as f:
            pass  # empty

        db = _MockDB()
        reader = JsonlTailReader(db, str(log_path), flush_interval=0.1)
        reader.start()
        reader.bind_session("s1", device_id="d1", user_id="u1")
        time.sleep(0.15)

        with open(log_path, "a") as f:
            f.write(json.dumps({"type": "session_start", "session_id": "s1", "ts": 100.0}) + "\n")

        time.sleep(0.5)
        reader.stop()

        sessions = db.tables.get("sessions")
        assert sessions is not None
        assert len(sessions.inserts) >= 1
        row = sessions.inserts[0][0]
        assert row["id"] == "s1"
        assert row["device_id"] == "d1"
        assert row["user_id"] == "u1"

    def test_session_stop_updates_session_row(self, tmp_path):
        """Reader updates sessions row on session_stop."""
        log_path = tmp_path / "test.jsonl"
        with open(log_path, "w") as f:
            pass

        db = _MockDB()
        reader = JsonlTailReader(db, str(log_path), flush_interval=0.1)
        reader.start()
        reader.bind_session("s1")
        time.sleep(0.15)

        with open(log_path, "a") as f:
            f.write(json.dumps({"type": "session_stop", "session_id": "s1", "ts": 200.0}) + "\n")

        time.sleep(0.5)
        reader.stop()

        sessions = db.tables.get("sessions")
        assert sessions is not None
        assert len(sessions.updates) >= 1

    def test_does_not_read_old_lines(self, tmp_path):
        """Reader only processes lines written AFTER it started."""
        log_path = tmp_path / "test.jsonl"
        # Write old lines first
        with open(log_path, "w") as f:
            f.write(json.dumps({"type": "session_start", "session_id": "old", "ts": 100.0}) + "\n")
            f.write(json.dumps({"type": "frame", "session_id": "old", "ts": 101.0, "attention": 50.0,
                                "perclos": 0.1, "ema_drowsy": 0.2, "pitch": 0, "yaw": 0, "roll": 0,
                                "pose_valid": True, "alert": None, "blinks_per_min": 0}) + "\n")

        db = _MockDB()
        reader = JsonlTailReader(db, str(log_path), flush_interval=0.1)
        reader.start()
        reader.bind_session("new_session")

        time.sleep(0.3)  # reader should have seeked to end by now

        reader.stop()

        # No telemetry should be inserted — old lines were skipped
        telemetry = db.tables.get("telemetry")
        if telemetry is not None:
            total = sum(len(b) for b in telemetry.inserts)
            assert total == 0

    def test_stop_flushes_remaining(self, tmp_path):
        """Calling stop() flushes any remaining buffered rows."""
        log_path = tmp_path / "test.jsonl"
        with open(log_path, "w") as f:
            pass

        db = _MockDB()
        reader = JsonlTailReader(db, str(log_path), flush_interval=999)  # very long interval
        reader.start()
        reader.bind_session("s1")
        time.sleep(0.15)

        # Write frames — they won't flush until stop() because flush_interval=999s
        with open(log_path, "a") as f:
            for i in range(5):
                f.write(json.dumps({
                    "type": "frame", "session_id": "s1", "ts": 100.0 + i,
                    "attention": 80, "perclos": 0.1, "ema_drowsy": 0.2,
                    "pitch": 0, "yaw": 0, "roll": 0, "pose_valid": True,
                    "alert": None, "blinks_per_min": 15.0,
                }) + "\n")

        time.sleep(0.3)
        reader.stop()

        telemetry = db.tables.get("telemetry")
        assert telemetry is not None
        total = sum(len(b) for b in telemetry.inserts)
        assert total == 5

    def test_iso_ts_conversion(self):
        """_iso_ts converts unix timestamps to ISO strings."""
        result = JsonlTailReader._iso_ts(1000000.0)
        assert "T" in result  # ISO format contains T

        result2 = JsonlTailReader._iso_ts("2024-01-01T00:00:00Z")
        assert result2 == "2024-01-01T00:00:00Z"  # passthrough

        result3 = JsonlTailReader._iso_ts(None)
        assert "T" in result3  # current time
    def test_session_stats_computed_on_stop(self, tmp_path):
        log_path = tmp_path / 'test.jsonl'
        with open(log_path, 'w') as f:
            pass
        db = _MockDB()
        reader = JsonlTailReader(db, str(log_path), flush_interval=0.1)
        reader.start()
        reader.bind_session('s1')
        time.sleep(0.15)
        with open(log_path, 'a') as f:
            f.write(json.dumps({'type': 'session_start', 'session_id': 's1', 'ts': 100.0}) + chr(10))
            for i in range(5):
                f.write(json.dumps({'type': 'frame', 'session_id': 's1', 'ts': 100.0 + i, 'attention': 80.0 + i, 'perclos': 0.1 + i * 0.02, 'ema_drowsy': 0.2, 'pitch': 0, 'yaw': 0, 'roll': 0, 'pose_valid': True, 'alert': None, 'blinks_per_min': 15.0}) + chr(10))
            f.write(json.dumps({'type': 'alert', 'session_id': 's1', 'ts': 103.0, 'alert': 'MICROSLEEP', 'fired_for': 3.0}) + chr(10))
            f.write(json.dumps({'type': 'session_stop', 'session_id': 's1', 'ts': 105.0}) + chr(10))
        time.sleep(0.5)
        reader.stop()
        sessions = db.tables.get('sessions')
        assert sessions is not None
        assert len(sessions.updates) >= 1
        update_data = sessions.updates[0][0]
        assert 'duration_s' in update_data
        assert 'avg_attention' in update_data
        assert 'alert_count' in update_data
        assert 'safety_score' in update_data
        assert update_data['duration_s'] == 5.0
        assert update_data['alert_count'] == 1
        assert update_data['avg_attention'] == 82.0
