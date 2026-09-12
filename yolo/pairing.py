"""Short-lived local pairing credentials for desktop/mobile clients."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import threading
import time
from dataclasses import dataclass
from typing import Any


class PairingRateLimitedError(ValueError):
    """Raised when too many pairing codes have recently failed."""

    def __init__(self, retry_after: float):
        self.retry_after = max(0.0, float(retry_after))
        super().__init__(
            f"pairing temporarily locked; retry in {self.retry_after:.0f} seconds"
        )


@dataclass
class _TokenRecord:
    """One issued companion token. The secret itself is never stored here —
    the token string is the dict key; records carry only presentation data."""

    device_name: str
    issued_at: float
    expires_at: float


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
        self._tokens: dict[str, _TokenRecord] = {}
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

    def exchange(self, code: Any, now: float | None = None,
                 device_name: str = "") -> dict[str, Any]:
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
            self._tokens[access_token] = _TokenRecord(
                device_name=(device_name or "").strip(),
                issued_at=now,
                expires_at=expires_at,
            )
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

    def revoke_admin(self, token: Any, now: float | None = None) -> bool:
        """Admin-side revocation of any companion token (master token auth)."""
        if not isinstance(token, str) or not token:
            return False
        now = time.time() if now is None else now
        with self._lock:
            record = self._tokens.pop(token, None)
            return record is not None

    def revoke_by_preview(self, preview: Any, now: float | None = None) -> int:
        """Revoke every companion token whose prefix matches `preview`.

        Previews are the only handle the admin UI has (secrets are never
        stored in listings), so resolution must happen here behind the lock.
        Returns the number of tokens revoked.
        """
        if not isinstance(preview, str) or not preview:
            return 0
        now = time.time() if now is None else now
        with self._lock:
            matches = [t for t in self._tokens if t.startswith(preview)]
            for token in matches:
                del self._tokens[token]
            return len(matches)

    def register_token(self, token: str, expires_at: float,
                       device_name: str = "", now: float | None = None) -> None:
        """Register an externally-issued companion token (Supabase pairing path)."""
        if not isinstance(token, str) or not token:
            raise ValueError("token is required")
        now = time.time() if now is None else now
        with self._lock:
            self._tokens[token] = _TokenRecord(
                device_name=(device_name or "").strip(),
                issued_at=now,
                expires_at=float(expires_at),
            )

    def list_tokens(self, now: float | None = None) -> list[dict[str, Any]]:
        """Admin listing of live companion tokens, secrets excluded."""
        now = time.time() if now is None else now
        with self._lock:
            expired = [t for t, r in self._tokens.items() if now >= r.expires_at]
            for token in expired:
                del self._tokens[token]
            return [
                {
                    "token_preview": token[:8],
                    "device_name": record.device_name,
                    "issued_at": record.issued_at,
                    "expires_at": record.expires_at,
                }
                for token, record in sorted(
                    self._tokens.items(), key=lambda item: item[1].issued_at
                )
            ]

    def is_valid_token(self, token: str, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        if not isinstance(token, str) or not token:
            return False
        with self._lock:
            record = self._tokens.get(token)
            if record is None:
                return False
            if now >= record.expires_at:
                del self._tokens[token]
                return False
            return True
