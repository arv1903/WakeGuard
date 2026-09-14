"""Tests for SessionLogger."""

import json

import pytest

from yolo.session_log import SessionLogger


class TestSessionLogger:
    """SessionLogger basic functionality."""

    def test_session_start_writes_event(self, tmp_path):
        path = tmp_path / "test.jsonl"
        logger = SessionLogger(str(path))
        logger.session_start("session-1")
        logger.close()

        lines = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
        assert len(lines) == 1
        assert lines[0]["type"] == "session_start"
        assert lines[0]["session_id"] == "session-1"

    def test_frame_sample_writes_event(self, tmp_path):
        path = tmp_path / "test.jsonl"
        logger = SessionLogger(str(path))
        logger.session_start("session-1")
        logger.frame_sample(
            attention=85.0, perclos=0.1, ema_drowsy=0.2,
            pitch=5.0, yaw=-2.0, roll=1.0, pose_valid=True,
            alert=None, blinks_per_min=15.0,
        )
        logger.close()

        lines = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
        frame_events = [l for l in lines if l["type"] == "frame"]
        assert len(frame_events) == 1
        assert frame_events[0]["attention"] == 85.0

    def test_alert_event_writes_event(self, tmp_path):
        path = tmp_path / "test.jsonl"
        logger = SessionLogger(str(path))
        logger.session_start("session-1")
        logger.alert_event("MICROSLEEP", 3.0)
        logger.close()

        lines = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
        alerts = [l for l in lines if l["type"] == "alert"]
        assert len(alerts) == 1
        assert alerts[0]["alert"] == "MICROSLEEP"

    def test_clear_event_writes_event(self, tmp_path):
        path = tmp_path / "test.jsonl"
        logger = SessionLogger(str(path))
        logger.session_start("session-1")
        logger.clear_event("MICROSLEEP")
        logger.close()

        lines = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
        clears = [l for l in lines if l["type"] == "clear"]
        assert len(clears) == 1

    def test_session_stop_writes_event(self, tmp_path):
        path = tmp_path / "test.jsonl"
        logger = SessionLogger(str(path))
        logger.session_start("session-1")
        logger.session_stop("session-1")
        logger.close()

        lines = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
        stops = [l for l in lines if l["type"] == "session_stop"]
        assert len(stops) == 1

    def test_kwargs_ignored(self, tmp_path):
        """Extra kwargs (like write_queue) are silently ignored."""
        logger = SessionLogger(str(tmp_path / "test.jsonl"), write_queue="ignored")
        logger.session_start("session-1")
        logger.close()

        lines = [json.loads(l) for l in open(tmp_path / "test.jsonl", encoding="utf-8") if l.strip()]
        assert len(lines) == 1
