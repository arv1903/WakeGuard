"""Short-lived local pairing credentials for desktop/mobile clients."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
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
    """One issued companion token. Tokens are stored keyed by SHA-256
    digest, so the secret itself is never persisted or listed; records
    carry only presentation data."""

    device_name: str
    issued_at: float
    expires_at: float
    preview: str = ""


class PairingManager:
    """Manage one short-lived human pairing code and issued access tokens.

    The code is intended to be displayed by a trusted local desktop UI and
    entered on a companion device. It is single-use; successful exchange
    rotates it immediately. Issued bearer tokens are independent of the
    backend's optional long-lived deployment token.

    When ``store_path`` is set, issued tokens survive a desktop restart:
    the mobile app pairs once and keeps working across reboots instead of
    silently losing access the moment the backend process exits. The store
    file only ever contains SHA-256 digests of the tokens (plus a short
    preview for the admin UI), never the secrets themselves.
    """

    def __init__(self, code_ttl: float = 120.0,
                 token_ttl: float = 24 * 60 * 60,
                 max_failed_attempts: int = 5,
                 failure_window: float = 60.0,
                 lockout_seconds: float = 30.0,
                 store_path: str | None = None):
        if code_ttl <= 0 or token_ttl <= 0:
            raise ValueError("pairing TTLs must be positive")
        if max_failed_attempts <= 0:
            raise ValueError("max_failed_attempts must be positive")
        if failure_window <= 0:
            raise ValueError("failure_window must be positive")
        if lockout_seconds <= 0:
            raise ValueError("lockout_seconds must be positive")
        self.code_ttl = float(code_ttl)
        self.token_ttl = float(token_ttl)
        self.max_failed_attempts = int(max_failed_attempts)
        self.failure_window = float(failure_window)
        self.lockout_seconds = float(lockout_seconds)
        self._store_path = store_path
        self._lock = threading.Lock()
        self._code = ""
        self._code_digest = b""
        self._code_expires_at = 0.0
        self._tokens: dict[str, _TokenRecord] = {}
        self._failed_attempts: list[float] = []
        self._locked_until = 0.0
        self._load_tokens_locked()
        self._rotate_code_locked(time.time())

    @staticmethod
    def _new_code() -> str:
        # Eight uppercase hex characters are easy to read aloud or type while
        # retaining enough entropy for a two-minute local pairing window.
        return secrets.token_hex(4).upper()

    @staticmethod
    def _digest(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

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

    # ── Persistence (best-effort, behind the lock) ───────────────────

    def _load_tokens_locked(self) -> None:
        if not self._store_path:
            return
        try:
            with open(self._store_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except FileNotFoundError:
            return
        except (OSError, ValueError):
            # A corrupt or unreadable store must never keep the API from
            # starting; begin with an empty set (users simply re-pair).
            return
        records = data.get("tokens") if isinstance(data, dict) else None
        if not isinstance(records, list):
            return
        now = time.time()
        for entry in records:
            if not isinstance(entry, dict):
                continue
            digest = entry.get("token_digest")
            expires_at = entry.get("expires_at")
            if not isinstance(digest, str) or not digest:
                continue
            if not isinstance(expires_at, (int, float)) or now >= expires_at:
                continue
            self._tokens[digest] = _TokenRecord(
                device_name=str(entry.get("device_name") or ""),
                issued_at=float(entry.get("issued_at") or 0.0),
                expires_at=float(expires_at),
                preview=str(entry.get("preview") or ""),
            )

    def _save_tokens_locked(self) -> None:
        if not self._store_path:
            return
        payload = {
            "version": 1,
            "tokens": [
                {
                    "token_digest": digest,
                    "device_name": record.device_name,
                    "issued_at": record.issued_at,
                    "expires_at": record.expires_at,
                    "preview": record.preview,
                }
                for digest, record in self._tokens.items()
            ],
        }
        tmp_path = f"{self._store_path}.tmp"
        try:
            with open(tmp_path, "w", encoding="utf-8") as fh:
                json.dump(payload, fh)
            os.replace(tmp_path, self._store_path)
        except OSError:
            # Persistence is best-effort; in-memory state keeps working.
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    def _register_locked(self, token: str, device_name: str,
                         issued_at: float, expires_at: float) -> None:
        self._tokens[self._digest(token)] = _TokenRecord(
            device_name=(device_name or "").strip(),
            issued_at=issued_at,
            expires_at=expires_at,
            preview=token[:8],
        )
        self._save_tokens_locked()

    # ── Public API ────────────────────────────────────────────────────

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
            self._register_locked(access_token, device_name, now, expires_at)
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
            removed = self._tokens.pop(self._digest(token), None) is not None
            if removed:
                self._save_tokens_locked()
            return removed

    def revoke_admin(self, token: Any, now: float | None = None) -> bool:
        """Admin-side revocation of any companion token (master token auth)."""
        if not isinstance(token, str) or not token:
            return False
        now = time.time() if now is None else now
        with self._lock:
            removed = self._tokens.pop(self._digest(token), None) is not None
            if removed:
                self._save_tokens_locked()
            return removed

    def revoke_by_preview(self, preview: Any, now: float | None = None) -> int:
        """Revoke every companion token whose stored preview matches `preview`.

        Previews are the only handle the admin UI has (secrets are never
        stored in listings), so resolution must happen here behind the lock.
        Returns the number of tokens revoked.
        """
        if not isinstance(preview, str) or not preview:
            return 0
        now = time.time() if now is None else now
        with self._lock:
            matches = [digest for digest, record in self._tokens.items()
                       if record.preview and record.preview.startswith(preview)]
            for digest in matches:
                del self._tokens[digest]
            if matches:
                self._save_tokens_locked()
            return len(matches)

    def register_token(self, token: str, expires_at: float,
                       device_name: str = "", now: float | None = None) -> None:
        """Register an externally-issued companion token (Supabase pairing path)."""
        if not isinstance(token, str) or not token:
            raise ValueError("token is required")
        now = time.time() if now is None else now
        with self._lock:
            self._register_locked(token, device_name, now, float(expires_at))

    def list_tokens(self, now: float | None = None) -> list[dict[str, Any]]:
        """Admin listing of live companion tokens, secrets excluded."""
        now = time.time() if now is None else now
        with self._lock:
            expired = [t for t, r in self._tokens.items() if now >= r.expires_at]
            for token in expired:
                del self._tokens[token]
            if expired:
                self._save_tokens_locked()
            return [
                {
                    "token_preview": record.preview or digest[:8],
                    "device_name": record.device_name,
                    "issued_at": record.issued_at,
                    "expires_at": record.expires_at,
                }
                for digest, record in sorted(
                    self._tokens.items(), key=lambda item: item[1].issued_at
                )
            ]

    def is_valid_token(self, token: str, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        if not isinstance(token, str) or not token:
            return False
        with self._lock:
            record = self._tokens.get(self._digest(token))
            if record is None:
                return False
            if now >= record.expires_at:
                del self._tokens[self._digest(token)]
                self._save_tokens_locked()
                return False
            return True
