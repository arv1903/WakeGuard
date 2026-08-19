"""Short-lived local pairing credentials for desktop/mobile clients."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import threading
import time
from typing import Any


class PairingRateLimitedError(ValueError):
    """Raised when too many pairing codes have recently failed."""

    def __init__(self, retry_after: float):
        self.retry_after = max(0.0, float(retry_after))
        super().__init__(
            f"pairing temporarily locked; retry in {self.retry_after:.0f} seconds"
        )


class PairingManager:
    """Manage one short-lived human pairing code and issued access tokens.

    The code is intended to be displayed by a trusted local desktop UI and
    entered on a companion device. It is single-use; successful exchange
    rotates it immediately. Issued bearer tokens are independent of the
    backend's optional long-lived deployment token.
    """

    def __init__(self, code_ttl: float = 120.0,
                 token_ttl: float = 24 * 60 * 60,
                 max_failed_attempts: int = 5,
                 failure_window: float = 60.0,
                 lockout_seconds: float = 30.0):
        if code_ttl <= 0 or token_ttl <= 0:
            raise ValueError("pairing TTLs must be positive")
        if max_failed_attempts <= 0:
            raise ValueError("max_failed_attempts must be positive")
        if failure_window <= 0 or lockout_seconds <= 0:
            raise ValueError("pairing throttle durations must be positive")
        self.code_ttl = float(code_ttl)
        self.token_ttl = float(token_ttl)
        self.max_failed_attempts = int(max_failed_attempts)
        self.failure_window = float(failure_window)
        self.lockout_seconds = float(lockout_seconds)
        self._lock = threading.Lock()
        self._code = ""
        self._code_digest = b""
        self._code_expires_at = 0.0
        self._tokens: dict[str, float] = {}
        self._failed_attempts: list[float] = []
        self._locked_until = 0.0
        self._rotate_code_locked(time.time())

    @staticmethod
    def _new_code() -> str:
        # Eight uppercase hex characters are easy to read aloud or type while
        # retaining enough entropy for a two-minute local pairing window.
        return secrets.token_hex(4).upper()

    def _rotate_code_locked(self, now: float) -> None:
        self._code = self._new_code()
        self._code_digest = hashlib.sha256(self._code.encode("ascii")).digest()
        self._code_expires_at = now + self.code_ttl

    def _prune_failed_attempts_locked(self, now: float) -> None:
        cutoff = now - self.failure_window
        self._failed_attempts = [
            timestamp for timestamp in self._failed_attempts
            if timestamp >= cutoff
        ]

    def details(self, now: float | None = None) -> dict[str, Any]:
        now = time.time() if now is None else now
        with self._lock:
            if now >= self._code_expires_at:
                self._rotate_code_locked(now)
            return {
                "code": self._code,
                "expires_at": self._code_expires_at,
                "pairing_uri": f"driver-monitor://pair?code={self._code}",
            }

    def exchange(self, code: Any, now: float | None = None) -> dict[str, Any]:
        now = time.time() if now is None else now
        if not isinstance(code, str):
            raise ValueError("pairing code is required")
        candidate = code.strip().upper()
        candidate_digest = hashlib.sha256(candidate.encode("ascii", "ignore")).digest()
        with self._lock:
            self._prune_failed_attempts_locked(now)
            if now < self._locked_until:
                raise PairingRateLimitedError(self._locked_until - now)
            if now >= self._code_expires_at:
                self._rotate_code_locked(now)
                raise ValueError("pairing code expired")
            if not hmac.compare_digest(candidate_digest, self._code_digest):
                self._failed_attempts.append(now)
                if len(self._failed_attempts) >= self.max_failed_attempts:
                    self._locked_until = now + self.lockout_seconds
                    raise PairingRateLimitedError(self.lockout_seconds)
                raise ValueError("invalid pairing code")

            access_token = secrets.token_urlsafe(32)
            expires_at = now + self.token_ttl
            self._tokens[access_token] = expires_at
            self._failed_attempts.clear()
            self._locked_until = 0.0
            self._rotate_code_locked(now)
            return {
                "access_token": access_token,
                "token_type": "Bearer",
                "expires_at": expires_at,
            }

    def revoke_token(self, token: Any) -> bool:
        """Revoke one issued companion token without affecting the master token."""
        if not isinstance(token, str) or not token:
            return False
        with self._lock:
            return self._tokens.pop(token, None) is not None

    def is_valid_token(self, token: str, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        if not isinstance(token, str) or not token:
            return False
        with self._lock:
            expires_at = self._tokens.get(token)
            if expires_at is None:
                return False
            if now >= expires_at:
                del self._tokens[token]
                return False
            return True
