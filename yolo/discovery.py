"""UDP discovery beacon for the WakeGuard backend.

Lets the mobile companion find the desktop backend on the LAN without the
user ever typing an IP address. Protocol (v1):

  Probe  (phone -> 255.255.255.255:48765, UDP): b"WG-DISCOVER"
  Reply  (desktop -> probe source,       UDP): JSON
      {"service": "wakeguard", "v": 1, "port": <api port>,
       "device_name": <hostname>, "platform": <os>}

The backend's IP is never in the payload — the phone reads it from the UDP
reply's source address, so a spoofed payload cannot redirect it.

Deliberately stdlib-only (socket + threading) so the desktop run needs no
extra install. The responder binds on all interfaces and answers unicast
probes too, which keeps tests deterministic; security enforcement (loopback
rejection, schema validation) lives in the Dart client.
"""

from __future__ import annotations

import json
import platform as platform_module
import socket
import threading

DISCOVERY_PORT = 48765
PROBE_MAGIC = b"WG-DISCOVER"


class DiscoveryResponder:
    """Answers UDP discovery probes with the backend's API port."""

    def __init__(
        self,
        api_host: str,
        api_port: int,
        device_name: str | None = None,
        platform: str | None = None,  # noqa: A002 - mirrors api.py metadata
        discovery_port: int = DISCOVERY_PORT,
    ):
        if api_host in ("127.0.0.1", "::1", "localhost"):
            raise ValueError(
                "discovery is pointless for loopback-only backends "
                "(no phone can reach them)"
            )
        if not 0 < api_port < 65536:
            raise ValueError("api_port out of range")
        self._api_host = api_host
        self._api_port = api_port
        self._device_name = device_name or platform_module.node() or "wakeguard-desktop"
        self._platform = platform or platform_module.system().lower()
        self._discovery_port = discovery_port
        self._sock: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()

    def payload(self) -> dict[str, object]:
        return {
            "service": "wakeguard",
            "v": 1,
            "port": self._api_port,
            "device_name": self._device_name,
            "platform": self._platform,
        }

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self) -> None:
        if self.running:
            return
        self._stop_event.clear()
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("", self._discovery_port))
        except OSError:
            sock.close()
            raise
        sock.settimeout(0.5)
        self._sock = sock
        self._thread = threading.Thread(
            target=self._serve, name="wakeguard-discovery", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        thread = self._thread
        if thread is not None:
            thread.join(timeout=2.0)
        self._thread = None
        sock = self._sock
        self._sock = None
        if sock is not None:
            sock.close()

    def _serve(self) -> None:
        reply = json.dumps(self.payload()).encode("utf-8")
        while not self._stop_event.is_set():
            sock = self._sock
            if sock is None:
                break
            try:
                data, addr = sock.recvfrom(1024)
            except socket.timeout:
                continue
            except OSError:
                break
            if data.strip() != PROBE_MAGIC:
                continue
            # Reply to the probe's source address: the phone reads our IP
            # from this reply's source, which is always a real local IP.
            try:
                sock.sendto(reply, addr)
            except OSError:
                continue
