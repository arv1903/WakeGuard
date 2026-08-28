"""Supabase client singleton and offline write queue for WakeGuard.

All Supabase access goes through this module.  When the ``SUPABASE_URL`` and
``SUPABASE_SERVICE_KEY`` environment variables are not set every helper
returns ``None`` so the rest of the codebase can gracefully fall back to
file-based storage.
"""

from __future__ import annotations

import json
import os
import queue
import threading
import time
from typing import Any

try:
    from supabase import create_client, Client  # type: ignore[import-untyped]
except ImportError:
    Client = None  # type: ignore[assignment,misc]

# ---------------------------------------------------------------------------
# Supabase client singleton
# ---------------------------------------------------------------------------

_client: Client | None = None
_init_lock = threading.Lock()


def get_db() -> Client | None:
    """Return a lazily-initialised Supabase client, or ``None`` if unconfigured."""
    global _client
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        return None
    if _client is None:
        with _init_lock:
            if _client is None:
                if Client is None:
                    raise ImportError(
                        "supabase package is not installed — "
                        "run: pip install supabase"
                    )
                _client = create_client(url, key)
    return _client


def is_configured() -> bool:
    """Return ``True`` when Supabase env vars are present."""
    return bool(os.environ.get("SUPABASE_URL") and os.environ.get("SUPABASE_SERVICE_KEY"))


# ---------------------------------------------------------------------------
# JWT helpers
# ---------------------------------------------------------------------------

def _fetch_jwks() -> dict[str, Any] | None:
    """Fetch Supabase JWKS (JSON Web Key Set) for ES256 JWT verification."""
    url = os.environ.get("SUPABASE_URL")
    if not url:
        return None
    try:
        import urllib.request
        jwks_url = f"{url}/auth/v1/.well-known/jwks.json"
        req = urllib.request.Request(jwks_url, headers={"Accept": "application/json"})
        resp = urllib.request.urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception:
        return None


# Cache for JWKS keys: {kid: PEM_public_key}
_jwks_cache: dict[str, str] | None = None
_jwks_cache_time: float = 0.0
_JWKS_CACHE_TTL = 3600.0  # refresh every hour


def _get_jwks_keys() -> dict[str, str]:
    """Return a mapping of kid -> PEM public key from Supabase JWKS, cached."""
    global _jwks_cache, _jwks_cache_time
    now = time.monotonic()
    if _jwks_cache is not None and (now - _jwks_cache_time) < _JWKS_CACHE_TTL:
        return _jwks_cache

    jwks = _fetch_jwks()
    keys: dict[str, str] = {}
    if jwks and "keys" in jwks:
        for jwk in jwks["keys"]:
            kid = jwk.get("kid")
            if not kid:
                continue
            try:
                from jwt.algorithms import RSAAlgorithm, ECAlgorithm
                # ES256 keys use EC algorithm
                if jwk.get("kty") == "EC":
                    key = ECAlgorithm.from_jwk(json.dumps(jwk))
                    keys[kid] = key
                elif jwk.get("kty") == "RSA":
                    key = RSAAlgorithm.from_jwk(json.dumps(jwk))
                    keys[kid] = key
            except Exception:
                continue
    _jwks_cache = keys
    _jwks_cache_time = now
    if keys:
        print(f"[db] JWKS loaded: {len(keys)} key(s)")
    else:
        print("[db] JWKS empty or unreachable — falling back to SUPABASE_JWT_SECRET")
    return keys


def verify_jwt(token: str) -> dict[str, Any] | None:
    """Verify a Supabase JWT and return its claims, or ``None`` on failure.

    First tries JWKS-based verification (ES256/RSA) fetched from
    Supabase's ``.well-known/jwks.json`` endpoint.  Falls back to
    ``SUPABASE_JWT_SECRET`` with HS256 for legacy projects.
    """
    if not token:
        return None
    try:
        import jwt  # PyJWT
    except ImportError:
        return None

    # Decode header to find kid and algorithm
    try:
        header = jwt.get_unverified_header(token)
    except Exception:
        return None
    kid = header.get("kid", "")
    alg = header.get("alg", "")

    # Try JWKS verification first (works for ES256, RS256, etc.)
    jwks_keys = _get_jwks_keys()
    if kid in jwks_keys:
        try:
            return jwt.decode(token, jwks_keys[kid],
                              algorithms=[alg], audience="authenticated")
        except Exception:
            pass

    # If JWKS had keys but this kid wasn't found, the token is from an
    # old key — try all cached keys as a fallback.
    if jwks_keys:
        for key in jwks_keys.values():
            try:
                return jwt.decode(token, key,
                                  algorithms=[alg], audience="authenticated")
            except Exception:
                continue

    # Fallback: HS256 with SUPABASE_JWT_SECRET (legacy projects)
    secret = os.environ.get("SUPABASE_JWT_SECRET")
    if secret and alg == "HS256":
        try:
            return jwt.decode(token, secret,
                              algorithms=["HS256"], audience="authenticated")
        except Exception:
            pass

    return None


# ---------------------------------------------------------------------------
# Auth helpers (Supabase REST — server-side only)
# ---------------------------------------------------------------------------

def auth_register(email: str, password: str, display_name: str = "") -> dict[str, Any] | None:
    """Register a new Supabase Auth user via the admin REST API.

    Returns ``{"id": ..., "email": ...}`` on success or ``None`` on failure.
    """
    db = get_db()
    if db is None:
        return None
    try:
        # supabase-py v2 — admin user creation
        result = db.auth.admin.create_user({
            "email": email,
            "password": password,
            "email_confirm": True,
            "user_metadata": {"display_name": display_name},
        })
        return {"id": result.user.id, "email": result.user.email}
    except Exception as exc:
        import traceback
        print(f"[db] registration failed: {exc}")
        print(f"[db] exception type: {type(exc).__name__}")
        if hasattr(exc, 'args'):
            for i, arg in enumerate(exc.args):
                print(f"[db]   args[{i}]: {arg!r}")
        traceback.print_exc()
        return None


def auth_login(email: str, password: str) -> dict[str, Any] | None:
    """Sign in with email/password.  Returns ``{"access_token": ..., "user_id": ...}``."""
    db = get_db()
    if db is None:
        return None
    try:
        result = db.auth.sign_in_with_password({"email": email, "password": password})
        return {
            "access_token": result.session.access_token,
            "refresh_token": result.session.refresh_token,
            "user_id": result.user.id,
            "expires_at": result.session.expires_at,
        }
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Offline write queue
# ---------------------------------------------------------------------------

class WriteQueue:
    """Buffer DB writes locally and flush them in the background.

    Designed for network outages: rows are kept in a thread-safe queue and
    retried with exponential back-off.  The queue is flushed periodically
    (default every 5 s) and on :meth:`stop`.
    """

    def __init__(
        self,
        db: Client,
        flush_interval: float = 5.0,
        max_retries: int = 3,
        batch_size: int = 50,
    ):
        self._db = db
        self._flush_interval = flush_interval
        self._max_retries = max_retries
        self._batch_size = batch_size

        self._queue: queue.Queue[tuple[str, list[dict]]] = queue.Queue()
        self._running = threading.Event()
        self._thread: threading.Thread | None = None

    # ── Lifecycle ──────────────────────────────────────────────────────

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._running.set()
        self._thread = threading.Thread(
            target=self._flush_loop, name="db-write-queue", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._running.clear()
        if self._thread is not None:
            self._thread.join(timeout=5.0)
            self._thread = None
        # Final best-effort flush
        self._flush_pending()

    # ── Enqueue ────────────────────────────────────────────────────────

    def enqueue(self, table: str, row: dict) -> None:
        """Queue a single row for insertion."""
        self._queue.put((table, [row]))

    def enqueue_batch(self, table: str, rows: list[dict]) -> None:
        """Queue multiple rows for insertion."""
        if rows:
            self._queue.put((table, list(rows)))

    # ── Internal ───────────────────────────────────────────────────────

    def _flush_loop(self) -> None:
        while self._running.is_set():
            time.sleep(self._flush_interval)
            self._flush_pending()

    def _flush_pending(self) -> None:
        """Drain the queue and attempt batch inserts."""
        batches: dict[str, list[dict]] = {}
        count = 0
        while not self._queue.empty() and count < self._batch_size * 10:
            try:
                table, rows = self._queue.get_nowait()
            except queue.Empty:
                break
            batches.setdefault(table, []).extend(rows)
            count += len(rows)

        for table, rows in batches.items():
            self._insert_with_retry(table, rows)

    def _insert_with_retry(self, table: str, rows: list[dict]) -> None:
        """Insert rows with exponential back-off on failure."""
        attempt = 0
        delay = 1.0
        while attempt < self._max_retries:
            try:
                self._db.table(table).insert(rows).execute()
                return
            except Exception:
                attempt += 1
                time.sleep(delay)
                delay = min(delay * 2, 30.0)
        # Exhausted retries — re-queue for the next flush cycle
        self._queue.put((table, rows))
