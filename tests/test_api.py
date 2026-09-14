import json
import time
from threading import Thread
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import numpy as np
import pytest

from yolo import api as api_module
from yolo.api import MonitoringApi, _primary_lan_address
from yolo.monitoring import MonitoringSnapshot, MonitoringStore
from yolo.pairing import PairingManager


def _get(base, path, headers=None):
    request = Request(base + path, headers=headers or {})
    with urlopen(request, timeout=2) as response:
        return response.status, response.headers, response.read()


def _post(base, path, payload=None, headers=None):
    body = json.dumps(payload or {}).encode("utf-8")
    request = Request(
        base + path,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with urlopen(request, timeout=2) as response:
        return response.status, json.loads(response.read())


@pytest.fixture
def api():
    store = MonitoringStore(MonitoringSnapshot(sequence=1, attention=91.0))
    service = MonitoringApi(port=0, store=store)
    service.start()
    try:
        yield service, store
    finally:
        service.stop()


def test_health_and_status(api):
    service, _ = api
    base = f"http://127.0.0.1:{service.port}"

    status, _, raw_health = _get(base, "/api/v1/health")
    _, _, raw_status = _get(base, "/api/v1/status")

    assert status == 200
    assert json.loads(raw_health)["status"] == "ok"
    assert json.loads(raw_status)["attention"] == 91.0
    assert json.loads(raw_status)["schema_version"] == 3
    assert json.loads(raw_status)["server_id"]


def test_pairing_exchange_issues_a_token_and_rotates_code():
    service = MonitoringApi(port=0, auth_token="master")
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        _, _, raw = _get(base, "/api/v1/pairing")
        pairing = json.loads(raw)
        assert len(pairing["code"]) == 8
        assert pairing["pairing_uri"].endswith(pairing["code"])

        status, result = _post(base, "/api/v1/pairing/exchange", {
            "code": pairing["code"],
        })
        assert status == 200
        assert result["token_type"] == "Bearer"
        assert result["access_token"]

        status, _, _ = _get(
            base,
            "/api/v1/status",
            headers={"Authorization": f"Bearer {result['access_token']}"},
        )
        assert status == 200

        with pytest.raises(HTTPError) as exc:
            _post(base, "/api/v1/pairing/exchange", {"code": pairing["code"]})
        assert exc.value.code == 400
    finally:
        service.stop()


def test_pairing_token_can_revoke_itself_and_then_loses_access():
    service = MonitoringApi(port=0, auth_token="master")
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        _, _, raw = _get(base, "/api/v1/pairing")
        issued = _post(base, "/api/v1/pairing/exchange", {
            "code": json.loads(raw)["code"],
        })[1]
        headers = {"Authorization": f"Bearer {issued['access_token']}"}

        status, result = _post(base, "/api/v1/pairing/revoke", headers=headers)
        assert status == 200
        assert result["revoked"] is True

        with pytest.raises(HTTPError) as exc:
            _get(base, "/api/v1/status", headers=headers)
        assert exc.value.code == 401
    finally:
        service.stop()


def test_pairing_revoke_requires_a_companion_token():
    service = MonitoringApi(port=0, auth_token="master")
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        with pytest.raises(HTTPError) as exc:
            _post(base, "/api/v1/pairing/revoke", headers={
                "Authorization": "Bearer master",
            })
        assert exc.value.code == 400

        with pytest.raises(HTTPError) as invalid:
            _post(base, "/api/v1/pairing/revoke", headers={
                "Authorization": "Bearer not-issued",
            })
        assert invalid.value.code == 401
    finally:
        service.stop()


def test_error_responses_drain_request_body_before_closing():
    """Rejecting a POST before reading its body must not abort the TCP
    stream: on Windows the unread body triggers an RST that hides the
    response from the client (WinError 10053)."""
    service = MonitoringApi(port=0, auth_token="master")
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        for _ in range(10):
            with pytest.raises(HTTPError) as exc:
                _post(base, "/api/v1/pairing/revoke", {"x": "y"}, headers={
                    "Authorization": "Bearer master",
                })
            assert exc.value.code == 400
    finally:
        service.stop()


def test_pairing_response_carries_routable_lan_address(monkeypatch):
    """The QR scanner needs the desktop's LAN address — a loopback host in
    the pairing QR makes the phone dial itself (errno 11)."""
    monkeypatch.setattr(api_module, "_primary_lan_address",
                        lambda: "192.168.1.10")
    service = MonitoringApi(port=0)
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        _, _, raw = _get(base, "/api/v1/pairing")
        payload = json.loads(raw)
        assert payload["lan_host"] == "192.168.1.10"
        assert payload["lan_port"] == service.port
    finally:
        service.stop()


def test_pairing_response_omits_lan_address_when_unresolvable(monkeypatch):
    monkeypatch.setattr(api_module, "_primary_lan_address", lambda: None)
    service = MonitoringApi(port=0)
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        _, _, raw = _get(base, "/api/v1/pairing")
        payload = json.loads(raw)
        assert "lan_host" not in payload
        assert "lan_port" not in payload
    finally:
        service.stop()


def test_primary_lan_address_is_never_loopback():
    addr = _primary_lan_address()
    if addr is None:
        pytest.skip("no non-loopback route available on this machine")
    assert addr not in ("127.0.0.1", "0.0.0.0")


def test_auth_refresh_returns_501_without_supabase(monkeypatch):
    """The refresh route exists and degrades cleanly when Supabase is off."""
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    service = MonitoringApi(port=0)
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        with pytest.raises(HTTPError) as exc:
            _post(base, "/api/v1/auth/refresh", {"refresh_token": "abc"})
        assert exc.value.code == 501
    finally:
        service.stop()


def test_auth_refresh_requires_a_refresh_token(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    service = MonitoringApi(port=0)
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        with pytest.raises(HTTPError) as exc:
            _post(base, "/api/v1/auth/refresh", {})
        assert exc.value.code == 400
    finally:
        service.stop()


def test_pairing_tokens_survive_a_backend_restart(tmp_path):
    """A phone must keep access after the desktop restarts — the exact
    scenario that stranded it with 'NODE ERROR // CHECK UPLINK'."""
    store = str(tmp_path / "pairing_tokens.json")

    first = MonitoringApi(port=0, auth_token="master",
                          pairing_store_path=store)
    first.start()
    base = f"http://127.0.0.1:{first.port}"
    _, _, raw = _get(base, "/api/v1/pairing")
    issued = _post(base, "/api/v1/pairing/exchange", {
        "code": json.loads(raw)["code"],
    })[1]
    headers = {"Authorization": f"Bearer {issued['access_token']}"}
    status, _, _ = _get(base, "/api/v1/status", headers=headers)
    assert status == 200
    first.stop()

    second = MonitoringApi(port=first.port, auth_token="master",
                           pairing_store_path=store)
    second.start()
    try:
        base = f"http://127.0.0.1:{second.port}"
        status, _, raw = _get(base, "/api/v1/status", headers=headers)
        assert status == 200
        assert json.loads(raw)["server_id"]  # genuinely a new instance
        # The stored file never contains the raw secret.
        with open(store, "r", encoding="utf-8") as fh:
            assert issued["access_token"] not in fh.read()
    finally:
        second.stop()


def test_pairing_exchange_is_rate_limited_after_failed_attempts():
    manager = PairingManager(
        max_failed_attempts=2,
        failure_window=60,
        lockout_seconds=30,
    )
    service = MonitoringApi(port=0, pairing=manager)
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        with pytest.raises(HTTPError) as first:
            _post(base, "/api/v1/pairing/exchange", {"code": "WRONG"})
        assert first.value.code == 400
        with pytest.raises(HTTPError) as second:
            _post(base, "/api/v1/pairing/exchange", {"code": "WRONG"})
        assert second.value.code == 429
        assert second.value.headers["Retry-After"] == "30"
    finally:
        service.stop()


def test_pairing_code_expiry_is_rejected():
    manager = PairingManager(code_ttl=0.001)
    service = MonitoringApi(port=0, pairing=manager)
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        _, _, raw = _get(base, "/api/v1/pairing")
        time.sleep(0.01)
        with pytest.raises(HTTPError) as exc:
            _post(base, "/api/v1/pairing/exchange", {
                "code": json.loads(raw)["code"],
            })
        assert exc.value.code == 400
    finally:
        service.stop()


def test_current_session_summary_is_available():
    service = MonitoringApi(port=0, summary_provider=lambda: {"alert_count": 2})
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        status, _, raw = _get(base, "/api/v1/sessions/current/summary")
        assert status == 200
        assert json.loads(raw)["alert_count"] == 2
    finally:
        service.stop()


def test_frame_endpoint_returns_latest_jpeg(api):
    service, _ = api
    service.publish_frame(np.zeros((12, 16, 3), dtype=np.uint8))
    base = f"http://127.0.0.1:{service.port}"

    status, headers, raw = _get(base, "/api/v1/frame.jpg")

    assert status == 200
    assert headers["Content-Type"] == "image/jpeg"
    assert raw[:2] == bytes((255, 216))


def test_mjpeg_endpoint_streams_a_frame(api):
    service, _ = api
    service.publish_frame(np.zeros((12, 16, 3), dtype=np.uint8))
    base = f"http://127.0.0.1:{service.port}"

    response = urlopen(base + "/api/v1/video.mjpg", timeout=2)
    try:
        raw = response.read(128)
        assert response.headers["Content-Type"].startswith("multipart/x-mixed-replace")
        assert b"--frame\r\nContent-Type: image/jpeg\r\n" in raw
    finally:
        response.close()


def test_device_and_session_metadata(api):
    service, store = api
    store.publish(MonitoringSnapshot(
        sequence=2,
        session_id="abc",
        trip_started_at=123.0,
        trip_active=True,
    ))
    service.metadata_provider = lambda: {"device_name": "test-device"}
    base = f"http://127.0.0.1:{service.port}"

    _, _, device = _get(base, "/api/v1/device")
    _, _, session = _get(base, "/api/v1/sessions/current")

    assert json.loads(device)["device_name"] == "test-device"
    assert json.loads(session) == {
        "id": "abc", "active": True, "started_at": 123.0,
    }


def test_event_endpoint_returns_new_snapshot(api):
    service, store = api
    base = f"http://127.0.0.1:{service.port}"

    def publish():
        store.publish(MonitoringSnapshot(sequence=2, attention=64.0))

    thread = Thread(target=publish)
    thread.start()
    _, headers, raw = _get(base, "/api/v1/events?after=1")
    thread.join()

    assert headers["Content-Type"].startswith("text/event-stream")
    event = raw.decode("utf-8")
    assert "event: monitoring_state" in event
    assert '"sequence":2' in event
    assert '"attention":64.0' in event


def test_commands_are_routed_to_handler(api):
    service, _ = api
    received = []

    def handle(command, payload):
        received.append((command, payload))
        return {"accepted": True, "command": command}

    service.command_handler = handle
    base = f"http://127.0.0.1:{service.port}"

    status, result = _post(base, "/api/v1/alarm/mute", {"reason": "test"})

    assert status == 200
    assert result["command"] == "mute_alarm"
    assert received == [("mute_alarm", {"reason": "test"})]


def test_invalid_event_sequence_is_rejected(api):
    service, _ = api
    base = f"http://127.0.0.1:{service.port}"

    with pytest.raises(HTTPError) as exc:
        _get(base, "/api/v1/events?after=nope")

    assert exc.value.code == 400


def test_lan_binding_requires_authentication():
    with pytest.raises(ValueError, match="auth_token"):
        MonitoringApi(host="0.0.0.0", port=0)


def test_options_response_allows_flutter_web_preflight(api):
    service, _ = api
    request = Request(
        f"http://127.0.0.1:{service.port}/api/v1/status",
        method="OPTIONS",
    )
    with urlopen(request, timeout=2) as response:
        assert response.status == 204
        assert response.headers["Access-Control-Allow-Origin"] == "*"


def test_authenticated_api_rejects_missing_token():
    service = MonitoringApi(port=0, auth_token="secret")
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"
        with pytest.raises(HTTPError) as exc:
            _get(base, "/api/v1/status")
        assert exc.value.code == 401

        status, _, _ = _get(
            base,
            "/api/v1/status",
            headers={"Authorization": "Bearer secret"},
        )
        assert status == 200
    finally:
        service.stop()


def test_settings_command_route(api):
    service, _ = api
    received = []
    service.command_handler = lambda cmd, payload: received.append((cmd, payload)) or {"accepted": True}
    base = f"http://127.0.0.1:{service.port}"
    status, payload = _post(base, "/api/v1/settings", {"ear_threshold": 0.22, "microsleep_duration": 1.5})
    assert status == 200
    assert payload == {"accepted": True}
    assert received == [("update_settings", {"ear_threshold": 0.22, "microsleep_duration": 1.5})]


def test_session_history_endpoint(api):
    service, _ = api
    service.history_provider = lambda **kw: [{"session_id": "s1", "safety_score": 95, "duration_s": 120.0}]
    base = f"http://127.0.0.1:{service.port}"
    status, _, body = _get(base, "/api/v1/sessions/history")
    assert status == 200
    data = json.loads(body.decode("utf-8"))
    assert data["history"] == [{"session_id": "s1", "safety_score": 95, "duration_s": 120.0}]


def test_pairing_admin_listing_and_revocation():
    service = MonitoringApi(port=0, auth_token="master")
    service.start()
    try:
        base = f"http://127.0.0.1:{service.port}"

        # Pair a companion, labeled like the phone app does.
        raw = _get(base, "/api/v1/pairing")[2].decode("utf-8")
        code = json.loads(raw)["code"]
        issued = _post(base, "/api/v1/pairing/exchange", {
            "code": code,
            "device_name": "Test Phone",
        })[1]
        companion = {"Authorization": f"Bearer {issued['access_token']}"}

        # Admin listing shows the companion, never the master or secrets.
        status, _, raw = _get(base, "/api/v1/pairings", headers={
            "Authorization": "Bearer master",
        })
        listing = json.loads(raw)
        assert status == 200
        assert listing["devices"] == [{
            "token_preview": issued["access_token"][:8],
            "device_name": "Test Phone",
            "issued_at": listing["devices"][0]["issued_at"],
            "expires_at": listing["devices"][0]["expires_at"],
        }]

        # Admin listing requires the master token.
        with pytest.raises(HTTPError) as forbidden_list:
            _get(base, "/api/v1/pairings", headers=companion)
        assert forbidden_list.value.code == 403

        # Companion tokens must not be able to revoke others.
        with pytest.raises(HTTPError) as forbidden:
            _post(base, "/api/v1/pairings/revoke", {
                "token_preview": issued["access_token"][:8],
            }, headers=companion)
        assert forbidden.value.code == 403

        # Admin revocation by preview kills the companion token.
        status, result = _post(base, "/api/v1/pairings/revoke", {
            "token_preview": issued["access_token"][:8],
        }, headers={"Authorization": "Bearer master"})
        assert status == 200 and result["revoked"] is True

        with pytest.raises(HTTPError) as dead:
            _get(base, "/api/v1/status", headers=companion)
        assert dead.value.code == 401

        # Master token itself survives and still works.
        status, _, _ = _get(base, "/api/v1/status", headers={
            "Authorization": "Bearer master",
        })
        assert status == 200
    finally:
        service.stop()
