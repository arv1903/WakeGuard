"""Tests for yolo.db — WriteQueue, verify_jwt, and auth helpers.

All tests use mocked Supabase clients so no real connection is needed.
"""

import json
import time
from unittest.mock import MagicMock, patch, PropertyMock

import pytest

from yolo.db import WriteQueue, verify_jwt


# ---------------------------------------------------------------------------
# WriteQueue tests
# ---------------------------------------------------------------------------


class TestWriteQueue:
    def test_enqueue_single_row(self):
        db = MagicMock()
        q = WriteQueue(db, flush_interval=100)  # long interval so no auto-flush
        q.start()
        try:
            q.enqueue("sessions", {"id": "1", "name": "test"})
            q._flush_pending()
            db.table.assert_called_with("sessions")
        finally:
            q.stop()

    def test_enqueue_batch(self):
        db = MagicMock()
        q = WriteQueue(db, flush_interval=100)
        q.start()
        try:
            rows = [{"id": str(i)} for i in range(5)]
            q.enqueue_batch("telemetry", rows)
            q._flush_pending()
            db.table.assert_called_with("telemetry")
        finally:
            q.stop()

    def test_flush_empty_queue_noop(self):
        db = MagicMock()
        q = WriteQueue(db, flush_interval=100)
        q.start()
        try:
            q._flush_pending()
            db.table.assert_not_called()
        finally:
            q.stop()

    def test_retry_on_failure(self):
        db = MagicMock()
        table_mock = MagicMock()
        db.table.return_value = table_mock
        table_mock.insert.return_value.execute.side_effect = [
            Exception("network error"),  # first attempt fails
            MagicMock(data=[{"id": "1"}]),  # second attempt succeeds
        ]

        q = WriteQueue(db, flush_interval=100, max_retries=3)
        q.start()
        try:
            q.enqueue("sessions", {"id": "1"})
            q._flush_pending()
            # Should have retried
            assert table_mock.insert.call_count == 2
        finally:
            q.stop()

    def test_stop_flushes_remaining(self):
        db = MagicMock()
        q = WriteQueue(db, flush_interval=100)
        q.start()
        q.enqueue("sessions", {"id": "1"})
        q.stop()
        db.table.assert_called_with("sessions")

    def test_batch_by_table(self):
        db = MagicMock()
        q = WriteQueue(db, flush_interval=100)
        q.start()
        try:
            q.enqueue("sessions", {"id": "1"})
            q.enqueue("telemetry", {"id": "2"})
            q.enqueue("sessions", {"id": "3"})
            q._flush_pending()
            # Two different tables should be called
            table_names = [call[0][0] for call in db.table.call_args_list]
            assert "sessions" in table_names
            assert "telemetry" in table_names
        finally:
            q.stop()


# ---------------------------------------------------------------------------
# verify_jwt tests
# ---------------------------------------------------------------------------


class TestVerifyJwt:
    def test_returns_none_without_secret(self):
        with patch.dict("os.environ", {}, clear=True):
            result = verify_jwt("some.token.here")
            assert result is None

    def test_returns_none_for_invalid_token(self):
        with patch.dict("os.environ", {"SUPABASE_JWT_SECRET": "test-secret"}):
            result = verify_jwt("invalid.token.value")
            assert result is None

    def test_verifies_valid_token(self):
        import jwt as pyjwt

        secret = "test-secret"
        payload = {"sub": "user-123", "aud": "authenticated"}
        token = pyjwt.encode(payload, secret, algorithm="HS256")

        with patch.dict("os.environ", {"SUPABASE_JWT_SECRET": secret}):
            result = verify_jwt(token)
            assert result is not None
            assert result["sub"] == "user-123"

    def test_rejects_expired_token(self):
        import jwt as pyjwt

        secret = "test-secret"
        payload = {"sub": "user-123", "aud": "authenticated", "exp": 0}
        token = pyjwt.encode(payload, secret, algorithm="HS256")

        with patch.dict("os.environ", {"SUPABASE_JWT_SECRET": secret}):
            result = verify_jwt(token)
            assert result is None

    def test_returns_none_for_empty_token(self):
        with patch.dict("os.environ", {"SUPABASE_JWT_SECRET": "test-secret"}):
            assert verify_jwt("") is None
            assert verify_jwt(None) is None  # type: ignore[arg-type]
