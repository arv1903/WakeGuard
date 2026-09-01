"""Local API boundary for Flutter desktop and mobile clients.

The first transport is dependency-free HTTP plus a one-update Server-Sent Event
response. Clients reconnect with ``after=<sequence>``. This gives the Flutter
clients a stable live-state contract without adding a web framework to the
computer-vision runtime; a persistent WebSocket/video transport can be layered
on the same store later.
"""

from __future__ import annotations

from functools import partial
from datetime import datetime, timezone
import json
import ipaddress
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading

import cv2
import numpy as np
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse

from .monitoring import MonitoringSnapshot, MonitoringStore, SNAPSHOT_SCHEMA_VERSION
from .pairing import PairingManager, PairingRateLimitedError
from .db import verify_jwt, auth_register, auth_login, get_db, is_configured as supabase_configured


API_PREFIX = "/api/v1"
_MAX_BODY_BYTES = 64 * 1024

CommandHandler = Callable[[str, dict[str, Any]], dict[str, Any] | None]
SummaryProvider = Callable[[], dict[str, Any]]
MetadataProvider = Callable[[], dict[str, Any]]
TelemetryProvider = Callable[[str], list[dict[str, Any]]]


class _ApiServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


class CommandConflictError(RuntimeError):
    """A command cannot run because the current runtime state conflicts."""


class _RequestHandler(BaseHTTPRequestHandler):
    """Small JSON/SSE handler kept private behind ``MonitoringApi``."""

    server: _ApiServer

    def log_message(self, format, *args):  # noqa: A002 - stdlib handler signature
        # The application already has diagnostics/logging; avoid noisy access
        # logs in the camera process.
        return

    @property
    def api(self) -> "MonitoringApi":
        return self.server.api  # type: ignore[attr-defined]

    def _bearer_token(self) -> str | None:
        header = self.headers.get("Authorization", "")
        prefix = "Bearer "
        if not header.startswith(prefix):
            return None
        token = header[len(prefix):].strip()
        return token or None

    def _authorized(self) -> bool:
        token = self._bearer_token()
        # 1. No auth configured — allow everything
        expected = self.api.auth_token
        if not expected:
            return True
        # 2. Legacy deployment token
        if token == expected:
            return True
        # 3. Pairing companion token
        if token is not None and self.api.pairing.is_valid_token(token):
            return True
        # 4. Supabase JWT
        if token is not None and supabase_configured():
            claims = verify_jwt(token)
            if claims is not None:
                return True
        return False

    def _jwt_user_id(self) -> str | None:
        """Extract user_id from the Bearer JWT, or ``None``."""
        token = self._bearer_token()
        if not token:
            return None
        claims = verify_jwt(token)
        if claims is None:
            return None
        return claims.get("sub")

    def _send_headers(self, status: int, content_type: str,
                      length: int | None = None, close: bool = True,
                      extra_headers: dict[str, str] | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        if length is not None:
            self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        if extra_headers:
            for name, value in extra_headers.items():
                self.send_header(name, value)
        if close:
            self.send_header("Connection", "close")
        self.end_headers()

    def _send_bytes(self, status: int, body: bytes, content_type: str,
                    extra_headers: dict[str, str] | None = None) -> None:
        self._send_headers(status, content_type, len(body),
                           extra_headers=extra_headers)
        try:
            self.wfile.write(body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def _send_json(self, status: int, payload: dict[str, Any],
                   extra_headers: dict[str, str] | None = None) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self._send_bytes(status, body, "application/json; charset=utf-8",
                         extra_headers=extra_headers)

    def _error(self, status: int, message: str) -> None:
        self._send_json(status, {"error": message})

    def do_OPTIONS(self):  # noqa: N802 - stdlib handler signature
        self._send_headers(204, "text/plain; charset=utf-8", 0)

    def _send_mjpeg(self) -> None:
        self._send_headers(
            200,
            "multipart/x-mixed-replace; boundary=frame",
            close=False,
        )
        version = -1
        try:
            while self.api.running:
                payload, version = self.api.wait_for_jpeg(version, timeout=1.0)
                if payload is None:
                    continue
                self.wfile.write(
                    b"--frame\r\n"
                    b"Content-Type: image/jpeg\r\n"
                    + f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii")
                    + payload
                    + b"\r\n"
                )
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            # A mobile client disconnecting is normal and must not terminate
            # the API or the detector thread.
            return

    def _read_json(self) -> dict[str, Any] | None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._error(400, "invalid Content-Length")
            return None
        if length < 0 or length > _MAX_BODY_BYTES:
            self._error(413, "request body too large")
            return None
        try:
            raw = self.rfile.read(length)
            data = json.loads(raw.decode("utf-8")) if raw else {}
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._error(400, "request body must be valid JSON")
            return None
        if not isinstance(data, dict):
            self._error(400, "request body must be a JSON object")
            return None
        return data

    def do_GET(self):  # noqa: N802 - stdlib handler signature
        parsed = urlparse(self.path)
        path = parsed.path
        if path == f"{API_PREFIX}/pairing":
            self._send_pairing()
            return
        if path == f"{API_PREFIX}/device/discover":
            self._handle_device_discover()
            return
        if not self._authorized():
            self._error(401, "authorization required")
            return
        if path == f"{API_PREFIX}/health":
            self._send_json(200, {
                "status": "ok",
                "service": "driver-monitor",
                "schema_version": SNAPSHOT_SCHEMA_VERSION,
            })
        elif path == f"{API_PREFIX}/status":
            self._send_json(200, self.api.snapshot_payload())
        elif path == f"{API_PREFIX}/events":
            self._send_event(parsed.query)
        elif path == f"{API_PREFIX}/frame.jpg":
            self._send_frame()
        elif path == f"{API_PREFIX}/video.mjpg":
            self._send_mjpeg()
        elif path == f"{API_PREFIX}/device":
            self._send_json(200, self.api.metadata())
        elif path == f"{API_PREFIX}/sessions/current":
            self._send_json(200, self.api.session_metadata())
        elif path == f"{API_PREFIX}/sessions/current/summary":
            self._send_summary()
        elif path == f"{API_PREFIX}/sessions/history":
            self._send_history()
        else:
            self._send_session_telemetry(path)


    def _is_local_address(self, addr: str) -> bool:
        if addr in ("127.0.0.1", "::1", "::ffff:127.0.0.1", "localhost"):
            return True
        try:
            clean_addr = addr.removeprefix("::ffff:")
            ip = ipaddress.ip_address(clean_addr)
            return ip.is_loopback
        except ValueError:
            return False

    def _send_pairing(self) -> None:
        # The code is only retrievable from the same machine. A mobile client
        # receives it out-of-band from the desktop UI or an explicitly shown
        # QR payload, rather than through an unauthenticated LAN request.
        client_ip = self.client_address[0]
        # Also check X-Forwarded-For / Forwarded if behind proxy — deny if present
        if self.headers.get("X-Forwarded-For") or self.headers.get("Forwarded"):
            self._error(403, "pairing code is local-only (proxy detected)")
            return
        if not self._is_local_address(client_ip):
            self._error(403, "pairing code is local-only")
            return
        self._send_json(200, self.api.pairing.details())

    # ── Auth handlers ────────────────────────────────────────────────

    def _handle_auth_register(self) -> None:
        if not supabase_configured():
            self._error(501, "Supabase is not configured")
            return
        payload = self._read_json()
        if payload is None:
            return
        email = (payload.get("email") or "").strip()
        password = (payload.get("password") or "").strip()
        display_name = (payload.get("display_name") or "").strip()
        if not email or not password:
            self._error(400, "email and password are required")
            return
        result = auth_register(email, password, display_name)
        if result is None:
            self._error(400, "registration failed (email may already be in use)")
            return
        # Auto-login after registration
        login_result = auth_login(email, password)
        if login_result is not None:
            self._send_json(200, login_result)
        else:
            self._send_json(200, {"user_id": result["id"], "email": result["email"]})

    def _handle_auth_login(self) -> None:
        if not supabase_configured():
            self._error(501, "Supabase is not configured")
            return
        payload = self._read_json()
        if payload is None:
            return
        email = (payload.get("email") or "").strip()
        password = (payload.get("password") or "").strip()
        if not email or not password:
            self._error(400, "email and password are required")
            return
        result = auth_login(email, password)
        if result is None:
            self._error(401, "invalid email or password")
            return
        self._send_json(200, result)

    def _handle_device_register(self) -> None:
        user_id = self._jwt_user_id()
        if user_id is None:
            self._error(401, "valid JWT required")
            return
        db = get_db()
        if db is None:
            self._error(501, "Supabase is not configured")
            return
        payload = self._read_json()
        if payload is None:
            return
        device_name = (payload.get("device_name") or "unknown").strip()
        platform_name = (payload.get("platform") or "").strip()
        api_host = (payload.get("api_host") or "127.0.0.1").strip()
        api_port = int(payload.get("api_port") or 8765)
        try:
            resp = (
                db.table("devices")
                .insert({
                    "user_id": user_id,
                    "device_name": device_name,
                    "platform": platform_name,
                    "api_host": api_host,
                    "api_port": api_port,
                    "last_seen_at": datetime.now(timezone.utc),
                })
                .execute()
            )
            device_id = resp.data[0]["id"] if resp.data else None
            self._send_json(200, {"device_id": device_id})
        except Exception as exc:
            self._error(500, f"device registration failed: {exc}")

    def _handle_device_heartbeat(self) -> None:
        user_id = self._jwt_user_id()
        if user_id is None:
            self._error(401, "valid JWT required")
            return
        db = get_db()
        if db is None:
            self._error(501, "Supabase is not configured")
            return
        payload = self._read_json()
        if payload is None:
            return
        device_id = payload.get("device_id")
        if not device_id:
            self._error(400, "device_id is required")
            return
        api_host = payload.get("api_host")
        api_port = payload.get("api_port")
        update: dict[str, Any] = {"last_seen_at": datetime.now(timezone.utc)}
        if api_host:
            update["api_host"] = api_host
        if api_port:
            update["api_port"] = int(api_port)
        try:
            db.table("devices").update(update).eq("id", device_id).eq("user_id", user_id).execute()
            self._send_json(200, {"ok": True})
        except Exception as exc:
            self._error(500, f"heartbeat failed: {exc}")

    def _handle_device_discover(self) -> None:
        user_id = self._jwt_user_id()
        if user_id is None:
            self._error(401, "valid JWT required")
            return
        db = get_db()
        if db is None:
            self._error(501, "Supabase is not configured")
            return
        try:
            resp = (
                db.table("devices")
                .select("id,device_name,platform,api_host,api_port,last_seen_at")
                .eq("user_id", user_id)
                .order("last_seen_at", desc=True)
                .execute()
            )
            devices = resp.data or []
            self._send_json(200, {"devices": devices})
        except Exception as exc:
            self._error(500, f"discover failed: {exc}")

    def _handle_auth_pair(self) -> None:
        """Generate a scoped access token for a mobile client to talk to a device."""
        user_id = self._jwt_user_id()
        if user_id is None:
            self._error(401, "valid JWT required")
            return
        payload = self._read_json()
        if payload is None:
            return
        device_id = payload.get("device_id")
        if not device_id:
            self._error(400, "device_id is required")
            return
        # Verify the device belongs to this user
        db = get_db()
        if db is None:
            self._error(501, "Supabase is not configured")
            return
        try:
            resp = (
                db.table("devices")
                .select("id,api_host,api_port")
                .eq("id", device_id)
                .eq("user_id", user_id)
                .execute()
            )
            if not resp.data:
                self._error(404, "device not found")
                return
            device = resp.data[0]
            # Issue a companion token via the existing PairingManager
            import secrets
            import time
            token = secrets.token_urlsafe(32)
            expires_at = time.time() + 24 * 60 * 60  # 24 hours
            self.api.pairing._tokens[token] = expires_at
            self._send_json(200, {
                "access_token": token,
                "token_type": "Bearer",
                "expires_at": expires_at,
                "device": {
                    "id": device["id"],
                    "api_host": device["api_host"],
                    "api_port": device["api_port"],
                },
            })
        except Exception as exc:
            self._error(500, f"pair failed: {exc}")

    def _send_summary(self) -> None:
        if self.api.summary_provider is None:
            self._error(503, "summary service unavailable")
            return
        try:
            summary = self.api.summary_provider()
        except FileNotFoundError:
            self._error(404, "no session log available")
            return
        except Exception:
            self._error(500, "summary unavailable")
            return
        self._send_json(200, summary)

    def _send_history(self) -> None:
        if self.api.history_provider is None:
            self._send_json(200, {"history": []})
            return
        user_id = self._jwt_user_id()
        try:
            history = self.api.history_provider(user_id=user_id)
        except Exception:
            self._send_json(200, {"history": []})
            return
        self._send_json(200, {"history": history})

    def _send_session_telemetry(self, path: str) -> None:
        prefix = f"{API_PREFIX}/sessions/"
        if not path.startswith(prefix) or not path.endswith("/telemetry"):
            self._error(404, "endpoint not found")
            return
        session_id = path[len(prefix):-len("/telemetry")]
        if not session_id:
            self._error(400, "session_id is required")
            return
        if self.api.telemetry_provider is None:
            self._send_json(200, {"telemetry": []})
            return
        try:
            telemetry = self.api.telemetry_provider(session_id)
        except Exception:
            self._send_json(200, {"telemetry": []})
            return
        self._send_json(200, {"telemetry": telemetry})

    def _send_frame(self) -> None:
        frame = self.api.latest_frame()
        if frame is None:
            self._error(503, "frame unavailable")
            return
        ok, encoded = cv2.imencode(
            ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80]
        )
        if not ok:
            self._error(500, "frame encoding failed")
            return
        self._send_bytes(200, encoded.tobytes(), "image/jpeg")

    def _send_event(self, query: str) -> None:
        values = parse_qs(query)
        try:
            after = int(values.get("after", ["0"])[0])
        except ValueError:
            self._error(400, "after must be an integer sequence")
            return
        if after < 0:
            self._error(400, "after must not be negative")
            return

        try:
            snapshot = self.api.store.wait_for_update(after_sequence=after, timeout=25.0)
        except Exception:
            return
        event = {
            "type": "monitoring_state",
            "data": self.api.snapshot_payload(snapshot),
        }
        body = (
            f"id: {snapshot.sequence}\n"
            "event: monitoring_state\n"
            f"data: {json.dumps(event, separators=(',', ':'))}\n\n"
        ).encode("utf-8")
        try:
            self._send_bytes(200, body, "text/event-stream; charset=utf-8")
        except (BrokenPipeError, ConnectionResetError, OSError):
            # Client disconnected before we could write the response.
            return

    def do_POST(self):  # noqa: N802 - stdlib handler signature
        parsed = urlparse(self.path)
        # ── Auth endpoints (no auth required) ───────────────────────
        if parsed.path == f"{API_PREFIX}/auth/register":
            self._handle_auth_register()
            return
        if parsed.path == f"{API_PREFIX}/auth/login":
            self._handle_auth_login()
            return
        # ── Device endpoints (JWT required) ─────────────────────────
        if parsed.path == f"{API_PREFIX}/device/register":
            self._handle_device_register()
            return
        if parsed.path == f"{API_PREFIX}/device/heartbeat":
            self._handle_device_heartbeat()
            return
        if parsed.path == f"{API_PREFIX}/auth/pair":
            self._handle_auth_pair()
            return
        if parsed.path == f"{API_PREFIX}/pairing/exchange":
            payload = self._read_json()
            if payload is None:
                return
            try:
                result = self.api.pairing.exchange(payload.get("code"))
            except PairingRateLimitedError as exc:
                self._send_json(
                    429,
                    {"error": str(exc)},
                    extra_headers={"Retry-After": str(max(1, int(exc.retry_after + 0.999)))},
                )
                return
            except ValueError as exc:
                self._error(400, str(exc))
                return
            self._send_json(200, result)
            return
        if parsed.path == f"{API_PREFIX}/pairing/revoke":
            if not self._authorized():
                self._error(401, "authorization required")
                return
            token = self._bearer_token()
            if token is None:
                self._error(401, "companion token required")
                return
            if token == self.api.auth_token:
                self._error(400, "the deployment token cannot be revoked")
                return
            if not self.api.pairing.is_valid_token(token):
                self._error(401, "invalid or expired companion token")
                return
            self.api.pairing.revoke_token(token)
            self._send_json(200, {"revoked": True})
            return
        if not self._authorized():
            self._error(401, "authorization required")
            return

        command_paths = {
            f"{API_PREFIX}/trips/start": "start_trip",
            f"{API_PREFIX}/trips/stop": "stop_trip",
            f"{API_PREFIX}/session/start": "start_trip",
            f"{API_PREFIX}/session/stop": "stop_trip",
            f"{API_PREFIX}/calibration/start": "start_calibration",
            f"{API_PREFIX}/alarm/mute": "mute_alarm",
            f"{API_PREFIX}/alarm/unmute": "unmute_alarm",
            f"{API_PREFIX}/settings": "update_settings",
        }
        parsed = urlparse(self.path)
        command = command_paths.get(parsed.path)
        if command is None:
            self._error(404, "endpoint not found")
            return

        payload = self._read_json()
        if payload is None:
            return
        if self.api.command_handler is None:
            self._error(503, "command service unavailable")
            return
        try:
            result = self.api.command_handler(command, payload) or {"accepted": True}
        except ValueError as exc:
            self._error(400, str(exc))
            return
        except CommandConflictError as exc:
            self._error(409, str(exc))
            return
        except Exception:
            self._error(500, "command failed")
            return
        self._send_json(200, result)


class MonitoringApi:
    """Manage the local API server in a daemon thread.

    ``host`` should remain ``127.0.0.1`` for desktop-only mode. Binding to a
    LAN interface should be an explicit deployment choice and should use
    ``auth_token``.
    """

    def __init__(self, host: str = "127.0.0.1", port: int = 8765,
                 store: MonitoringStore | None = None,
                 command_handler: CommandHandler | None = None,
                 summary_provider: SummaryProvider | None = None,
                 history_provider: Callable[[], list[dict]] | None = None,
                 telemetry_provider: TelemetryProvider | None = None,
                 metadata_provider: MetadataProvider | None = None,
                 session_provider: MetadataProvider | None = None,
                 auth_token: str | None = None,
                 pairing: PairingManager | None = None):
        if port < 0 or port > 65535:
            raise ValueError("port must be between 0 and 65535")
        if host == "0.0.0.0" and not auth_token:
            raise ValueError("LAN binding requires an auth_token")
        self.host = host
        self.store = store or MonitoringStore()
        self.command_handler = command_handler
        self.summary_provider = summary_provider
        self.history_provider = history_provider
        self.telemetry_provider = telemetry_provider
        self.metadata_provider = metadata_provider
        self.session_provider = session_provider
        self.auth_token = auth_token
        self.pairing = pairing or PairingManager()
        self.instance_id = uuid.uuid4().hex
        self._running = threading.Event()
        handler = partial(_RequestHandler)
        self._server = _ApiServer((host, port), handler)
        self._server.api = self  # type: ignore[attr-defined]
        self._thread: threading.Thread | None = None
        self._frame_lock = threading.Lock()
        self._frame_condition = threading.Condition(self._frame_lock)
        self._frame: np.ndarray | None = None
        self._jpeg_bytes: bytes | None = None
        self._frame_version = 0

    @property
    def port(self) -> int:
        return self._server.server_address[1]

    @property
    def address(self) -> tuple[str, int]:
        return self.host, self.port

    @property
    def running(self) -> bool:
        return self._running.is_set()

    def snapshot_payload(self, snapshot: MonitoringSnapshot | None = None) -> dict[str, Any]:
        payload = (snapshot or self.store.latest()).to_dict()
        payload["server_id"] = self.instance_id
        return payload

    def metadata(self) -> dict[str, Any]:
        if self.metadata_provider is not None:
            payload = dict(self.metadata_provider())
        else:
            payload = {
                "service": "driver-monitor",
                "schema_version": SNAPSHOT_SCHEMA_VERSION,
                "api_version": "v1",
                "capabilities": ["events", "jpeg", "mjpeg", "commands", "pairing"],
            }
        payload["server_id"] = self.instance_id
        return payload

    def session_metadata(self) -> dict[str, Any]:
        if self.session_provider is not None:
            return self.session_provider()
        snapshot = self.store.latest()
        return {
            "id": snapshot.session_id,
            "active": snapshot.trip_active,
            "started_at": snapshot.trip_started_at,
        }

    def wait_for_frame(self, after_version: int,
                       timeout: float | None = None) -> tuple[np.ndarray | None, int]:
        with self._frame_condition:
            self._frame_condition.wait_for(
                lambda: self._frame_version > after_version or not self.running,
                timeout=timeout,
            )
            if self._frame is None:
                return None, self._frame_version
            return self._frame, self._frame_version

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._running.set()
        self._thread = threading.Thread(
            target=self._server.serve_forever,
            name="monitoring-api",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        if self._thread is None:
            return
        self._running.clear()
        with self._frame_condition:
            self._frame_condition.notify_all()
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=2.0)
        self._thread = None

    def publish(self, snapshot: MonitoringSnapshot) -> None:
        self.store.publish(snapshot)

    def publish_frame(self, frame: np.ndarray) -> None:
        """Publish the newest raw frame without blocking the detector."""
        ok, encoded = cv2.imencode(
            ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80]
        )
        jpeg_bytes = encoded.tobytes() if ok else None
        with self._frame_condition:
            self._frame = frame
            self._jpeg_bytes = jpeg_bytes
            self._frame_version += 1
            self._frame_condition.notify_all()

    def latest_frame(self) -> np.ndarray | None:
        with self._frame_lock:
            return self._frame

    def latest_jpeg(self) -> bytes | None:
        with self._frame_lock:
            return self._jpeg_bytes

    def wait_for_jpeg(self, after_version: int,
                      timeout: float | None = None) -> tuple[bytes | None, int]:
        with self._frame_condition:
            self._frame_condition.wait_for(
                lambda: self._frame_version > after_version or not self.running,
                timeout=timeout,
            )
            return self._jpeg_bytes, self._frame_version
