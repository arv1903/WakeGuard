import json
import socket

import pytest

from yolo.discovery import DISCOVERY_PORT, PROBE_MAGIC, DiscoveryResponder

TEST_API_PORT = 18765
# Dedicated port: the shared DISCOVERY_PORT would race against a live
# desktop backend running on this machine (its replies break assertions).
TEST_DISCOVERY_PORT = DISCOVERY_PORT + 1000


@pytest.fixture
def responder():
    r = DiscoveryResponder(
        api_host="0.0.0.0",
        api_port=TEST_API_PORT,
        device_name="test-desktop",
        platform="windows",
        discovery_port=TEST_DISCOVERY_PORT,
    )
    r.start()
    try:
        yield r
    finally:
        r.stop()


def _send_and_recv(message: bytes, target: str = "127.0.0.1", timeout: float = 2.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        sock.sendto(message, (target, TEST_DISCOVERY_PORT))
        data, addr = sock.recvfrom(2048)
        return data, addr
    finally:
        sock.close()


def test_responder_answers_valid_probe(responder):
    data, addr = _send_and_recv(PROBE_MAGIC)
    payload = json.loads(data.decode("utf-8"))
    assert payload["service"] == "wakeguard"
    assert payload["v"] == 1
    assert payload["port"] == TEST_API_PORT
    assert payload["device_name"] == "test-desktop"
    assert payload["platform"] == "windows"
    # Addressing comes from the UDP source address, never from the payload —
    # a spoofed 'host' field must not exist for the client to trust.
    assert "host" not in payload
    assert "ip" not in payload


def test_responder_answers_broadcast_probe(responder):
    # Broadcast delivery is environment-dependent (firewalls/AP isolation);
    # a timeout here means the environment ate the broadcast, not a bug.
    try:
        data, _ = _send_and_recv(PROBE_MAGIC, target="255.255.255.255")
    except socket.timeout:
        pytest.skip("broadcast not delivered on this environment (firewall/AP isolation)")
    payload = json.loads(data.decode("utf-8"))
    assert payload["service"] == "wakeguard"


def test_responder_ignores_garbage(responder):
    with pytest.raises(socket.timeout):
        _send_and_recv(b"not-a-wakeguard-probe", timeout=0.6)
    # The responder must still be alive and answering afterwards.
    data, _ = _send_and_recv(PROBE_MAGIC)
    assert json.loads(data.decode("utf-8"))["service"] == "wakeguard"


def test_payload_schema_is_exact(responder):
    payload = responder.payload()
    assert set(payload.keys()) == {
        "service",
        "v",
        "port",
        "device_name",
        "platform",
    }


def test_stop_releases_port():
    r = DiscoveryResponder(
        api_host="0.0.0.0",
        api_port=TEST_API_PORT,
        device_name="x",
        platform="windows",
    )
    r.start()
    assert r.running
    r.stop()
    assert not r.running
    # The port must be immediately reusable (fast phone-side retry loops).
    r2 = DiscoveryResponder(
        api_host="0.0.0.0",
        api_port=TEST_API_PORT,
        device_name="x",
        platform="windows",
    )
    r2.start()
    try:
        assert r2.running
    finally:
        r2.stop()


def test_loopback_binding_is_rejected():
    # Discovery of a loopback-only backend is useless (no phone can reach it)
    # and misleading — mirror the api.py guard style and refuse to start.
    with pytest.raises(ValueError):
        DiscoveryResponder(api_host="127.0.0.1", api_port=8765)


def test_device_name_defaults_to_hostname():
    import platform as _platform

    r = DiscoveryResponder(api_host="0.0.0.0", api_port=TEST_API_PORT)
    assert r.payload()["device_name"] == _platform.node()
